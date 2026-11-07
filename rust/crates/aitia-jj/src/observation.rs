// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;

const OPERATION: &str = r#"json({"id" => id, "current" => current_operation})"#;
const WORKSPACE: &str = r#"json({"name" => name, "current" => current_workspace, "commit_id" => target.commit_id(), "change_id" => target.change_id(), "parent_ids" => target.parents().map(|c| c.commit_id())}) ++ "\n""#;

#[derive(Deserialize)]
struct Operation {
    id: String,
    current: bool,
}

#[derive(Deserialize)]
struct Workspace {
    name: String,
    current: bool,
    commit_id: String,
    change_id: String,
    parent_ids: Vec<String>,
}

/// An observation of an already recorded workspace. This carries no grant.
/// Identity fields are fixed by the adapter when it observes the workspace.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct WorkspaceCut {
    workspace_root: PathBuf,
    workspace_name: String,
    operation_id: String,
    change_id: String,
    commit_id: String,
    tree_id: String,
    parent_ids: Vec<String>,
}

impl WorkspaceCut {
    pub fn workspace_root(&self) -> &Path {
        &self.workspace_root
    }

    pub fn workspace_name(&self) -> &str {
        &self.workspace_name
    }

    pub fn operation_id(&self) -> &str {
        &self.operation_id
    }

    pub fn change_id(&self) -> &str {
        &self.change_id
    }

    pub fn commit_id(&self) -> &str {
        &self.commit_id
    }

    pub fn tree_id(&self) -> &str {
        &self.tree_id
    }

    pub fn parent_ids(&self) -> &[String] {
        &self.parent_ids
    }
}

#[derive(Debug)]
pub enum JjObservationError {
    Io(std::io::Error),
    Command(String),
    Output(String),
    ChangedOperation,
}

impl std::fmt::Display for JjObservationError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Command(error) | Self::Output(error) => formatter.write_str(error),
            Self::ChangedOperation => {
                formatter.write_str("JJ operation changed during observation")
            }
        }
    }
}

impl std::error::Error for JjObservationError {}

/// Read an existing workspace cut without snapshotting or reconciling it.
///
/// # Errors
///
/// Rejects unsupported output, an ambiguous workspace, or a changed operation.
pub fn observe_workspace(jj: &Path, workspace: &Path) -> Result<WorkspaceCut, JjObservationError> {
    let cut = capture_workspace(jj, workspace)?;
    if current_operation(jj, workspace)? != cut.operation_id {
        return Err(JjObservationError::ChangedOperation);
    }
    Ok(cut)
}

// The caller must check operation currentness after its last recorded read.
fn capture_workspace(jj: &Path, workspace: &Path) -> Result<WorkspaceCut, JjObservationError> {
    let operation = current_operation(jj, workspace)?;
    let workspace_root = output(jj_command(jj, workspace, &operation).args(["workspace", "root"]))?;
    let rows = output(jj_command(jj, workspace, &operation).args([
        "workspace",
        "list",
        "--template",
        WORKSPACE,
    ]))?;
    let mut current = rows
        .lines()
        .map(serde_json::from_str::<Workspace>)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| JjObservationError::Output(error.to_string()))?
        .into_iter()
        .filter(|row| row.current);
    let row = current
        .next()
        .filter(|_| current.next().is_none())
        .ok_or_else(|| {
            JjObservationError::Output("expected exactly one current JJ workspace".into())
        })?;
    let git_dir = output(jj_command(jj, workspace, &operation).args(["git", "root"]))?;
    let tree = output(
        Command::new("git")
            .current_dir(workspace)
            .env("GIT_NO_REPLACE_OBJECTS", "1")
            .env("GIT_NO_LAZY_FETCH", "1")
            .arg("--git-dir")
            .arg(path_line(&git_dir))
            .args([
                "rev-parse",
                "--verify",
                "--end-of-options",
                &format!("{}^{{tree}}", row.commit_id),
            ]),
    )?;
    Ok(WorkspaceCut {
        workspace_root: PathBuf::from(path_line(&workspace_root)),
        workspace_name: row.name,
        operation_id: operation,
        change_id: row.change_id,
        commit_id: row.commit_id,
        tree_id: tree.trim_end().into(),
        parent_ids: row.parent_ids,
    })
}

fn current_operation(jj: &Path, workspace: &Path) -> Result<String, JjObservationError> {
    let row = output(jj_command(jj, workspace, "@").args([
        "op",
        "log",
        "--no-graph",
        "--limit",
        "1",
        "--template",
        OPERATION,
    ]))?;
    let operation: Operation = serde_json::from_str(&row)
        .map_err(|error| JjObservationError::Output(error.to_string()))?;
    if !operation.current || operation.id.is_empty() {
        return Err(JjObservationError::Output(
            "missing current JJ operation".into(),
        ));
    }
    Ok(operation.id)
}

fn jj_command(jj: &Path, workspace: &Path, operation: &str) -> Command {
    let mut command = Command::new(jj);
    command.current_dir(workspace).args([
        "--ignore-working-copy",
        "--at-op",
        operation,
        "--color=never",
        "--no-pager",
    ]);
    command
}

// Git and JJ append a newline to path output. Trailing spaces belong
// to the path, and stripping them can select a different repository.
fn path_line(output: &str) -> &str {
    output.strip_suffix('\n').unwrap_or(output)
}

fn output(command: &mut Command) -> Result<String, JjObservationError> {
    let result = command.output().map_err(JjObservationError::Io)?;
    if !result.status.success() {
        return Err(JjObservationError::Command(
            String::from_utf8_lossy(&result.stderr).into_owned(),
        ));
    }
    String::from_utf8(result.stdout).map_err(|error| JjObservationError::Output(error.to_string()))
}

/// Read project configuration from the recorded commit of the nearest Git project.
///
/// # Errors
/// Requires a JJ workspace rooted at that Git project and a recorded manifest.
pub fn observe_project_manifest(
    jj: &Path,
    directory: &Path,
) -> Result<(WorkspaceCut, String), JjObservationError> {
    let root = git_project_root(directory)?;
    let cut = capture_workspace(jj, &root)?;
    if cut
        .workspace_root
        .canonicalize()
        .map_err(JjObservationError::Io)?
        != root
    {
        return Err(JjObservationError::Output(
            "nearest Git project has no matching JJ workspace".into(),
        ));
    }
    let manifest = read_recorded_file(jj, &cut, ".agents/aita/project.json")?;
    Ok((cut, manifest))
}

/// Read one regular UTF-8 file at the exact cut returned by the JJ adapter.
///
/// # Errors
/// Refuses paths outside the project, non-files, and a changed operation.
pub fn read_recorded_file(
    jj: &Path,
    cut: &WorkspaceCut,
    relative_path: &str,
) -> Result<String, JjObservationError> {
    if relative_path.split('/').any(|part| {
        part.is_empty()
            || part == "."
            || part == ".."
            || part.contains('\\')
            || part.chars().any(char::is_control)
    }) {
        return Err(JjObservationError::Output(
            "invalid project-relative file path".into(),
        ));
    }
    let fileset = format!(
        "file:{}",
        serde_json::to_string(relative_path)
            .map_err(|error| JjObservationError::Output(error.to_string()))?
    );
    let root = &cut.workspace_root;
    let entry = output(jj_command(jj, root, &cut.operation_id).args([
        "file",
        "list",
        "--revision",
        &cut.commit_id,
        "--template",
        r#"file_type ++ " " ++ path"#,
        &fileset,
    ]))?;
    if entry.strip_prefix("file ") != Some(relative_path) {
        return Err(JjObservationError::Output(
            "recorded project path must be a regular file".into(),
        ));
    }
    let content = output(jj_command(jj, root, &cut.operation_id).args([
        "file",
        "show",
        "--revision",
        &cut.commit_id,
        &fileset,
    ]))?;
    if current_operation(jj, root)? != cut.operation_id {
        return Err(JjObservationError::ChangedOperation);
    }
    Ok(content)
}

/// Resolve the Git project for a directory.
///
/// # Errors
/// The directory must be in a Git working tree.
pub fn git_project_root(directory: &Path) -> Result<PathBuf, JjObservationError> {
    let root = output(
        Command::new("git")
            .current_dir(directory)
            .env_remove("GIT_DIR")
            .env_remove("GIT_WORK_TREE")
            .env_remove("GIT_COMMON_DIR")
            .args(["rev-parse", "--show-toplevel"]),
    )?;
    Path::new(path_line(&root))
        .canonicalize()
        .map_err(JjObservationError::Io)
}
