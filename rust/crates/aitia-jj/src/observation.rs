// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Observe recorded Git-backed JJ workspaces and discover inputs at a fixed cut.

use futures::{executor::block_on, io::AsyncReadExt, stream::StreamExt};
use jj_lib::{
    backend::TreeValue,
    config::StackedConfig,
    default_backend_factories::{
        default_backend_factories, default_working_copy_factories, default_workspace_loader_factory,
    },
    object_id::ObjectId,
    op_store::OperationId,
    repo_path::RepoPath,
    settings::UserSettings,
    workspace::Workspace,
};
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::process::Command;

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

/// Failure to resolve or read a recorded workspace cut.
#[derive(Debug)]
pub enum JjObservationError {
    Io(std::io::Error),
    Command(String),
    Output(String),
    Repository(String),
    ChangedOperation,
}

impl std::fmt::Display for JjObservationError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Command(error) | Self::Output(error) | Self::Repository(error) => {
                formatter.write_str(error)
            }
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
pub fn observe_workspace(directory: &Path) -> Result<WorkspaceCut, JjObservationError> {
    let workspace = open_workspace(directory)?;
    block_on(async {
        let cut = capture_workspace(&workspace).await?;
        require_current(&workspace, &cut).await?;
        Ok(cut)
    })
}

fn repository_error(error: impl std::fmt::Display) -> JjObservationError {
    JjObservationError::Repository(error.to_string())
}

fn open_workspace(directory: &Path) -> Result<Workspace, JjObservationError> {
    let directory = directory.canonicalize().map_err(JjObservationError::Io)?;
    let root = directory
        .ancestors()
        .find(|ancestor| ancestor.join(".jj").is_dir())
        .ok_or_else(|| JjObservationError::Output("no JJ workspace found".into()))?;
    let settings = UserSettings::from_config_and_home_dir(StackedConfig::with_defaults(), None)
        .map_err(repository_error)?;
    let workspace = default_workspace_loader_factory()
        .create(root)
        .and_then(|loader| {
            loader.load(
                &settings,
                &default_backend_factories(),
                &default_working_copy_factories(),
            )
        })
        .map_err(repository_error)?;
    jj_lib::git::get_git_backend(workspace.repo_loader().store()).map_err(repository_error)?;
    Ok(workspace)
}

async fn capture_workspace(workspace: &Workspace) -> Result<WorkspaceCut, JjObservationError> {
    let operation_id = current_operation(workspace).await?;
    let loader = workspace.repo_loader();
    let operation = loader
        .load_operation(&operation_id)
        .await
        .map_err(repository_error)?;
    let view = operation.view().await.map_err(repository_error)?;
    let name = workspace.workspace_name();
    let commit_id = view.wc_commit_ids().get(name).ok_or_else(|| {
        JjObservationError::Output("current operation has no commit for this JJ workspace".into())
    })?;
    let commit = loader
        .store()
        .get_commit(commit_id)
        .map_err(repository_error)?;
    let tree = commit
        .tree_ids()
        .as_resolved()
        .ok_or_else(|| JjObservationError::Output("recorded JJ tree must be resolved".into()))?;
    Ok(WorkspaceCut {
        workspace_root: workspace.workspace_root().to_path_buf(),
        workspace_name: name.as_str().to_owned(),
        operation_id: operation_id.hex(),
        change_id: commit.change_id().reverse_hex(),
        commit_id: commit_id.hex(),
        tree_id: tree.hex(),
        parent_ids: commit.parent_ids().iter().map(ObjectId::hex).collect(),
    })
}

async fn current_operation(workspace: &Workspace) -> Result<OperationId, JjObservationError> {
    let heads = workspace
        .repo_loader()
        .op_heads_store()
        .get_op_heads()
        .await
        .map_err(repository_error)?;
    let [head] = heads.as_slice() else {
        return Err(JjObservationError::ChangedOperation);
    };
    Ok(head.clone())
}

async fn require_current(
    workspace: &Workspace,
    cut: &WorkspaceCut,
) -> Result<(), JjObservationError> {
    if current_operation(workspace).await?.hex() != cut.operation_id {
        return Err(JjObservationError::ChangedOperation);
    }
    Ok(())
}

// Git appends a newline to path output. Trailing spaces belong
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
    directory: &Path,
) -> Result<(WorkspaceCut, String), JjObservationError> {
    let root = git_project_root(directory)?;
    let workspace = open_workspace(&root)?;
    if workspace.workspace_root() != root {
        return Err(JjObservationError::Output(
            "nearest Git project has no matching JJ workspace".into(),
        ));
    }
    block_on(async {
        let cut = capture_workspace(&workspace).await?;
        let manifest = read_at_cut(&workspace, &cut, ".agents/aita/project.json").await?;
        require_current(&workspace, &cut).await?;
        Ok((cut, manifest))
    })
}

/// Discover recorded regular SysML documents in stable project-relative order.
///
/// # Errors
/// Refuses invalid tree entries and stale or ambiguous operation heads.
pub fn recorded_sysml_paths(cut: &WorkspaceCut) -> Result<Vec<String>, JjObservationError> {
    let workspace = open_workspace(&cut.workspace_root)?;
    block_on(async {
        require_current(&workspace, cut).await?;
        let commit = recorded_commit(&workspace, cut)?;
        let mut entries = commit.tree().entries();
        let mut paths = Vec::new();
        while let Some((path, value)) = entries.next().await {
            let value = value.map_err(repository_error)?;
            let path = path.as_internal_file_string();
            if path.ends_with(".sysml") {
                if !matches!(value.as_resolved(), Some(Some(TreeValue::File { .. }))) {
                    return Err(JjObservationError::Output(format!(
                        "recorded SysML path must be a regular file: {path}"
                    )));
                }
                paths.push(path.to_owned());
            }
        }
        require_current(&workspace, cut).await?;
        paths.sort_unstable();
        Ok(paths)
    })
}

fn recorded_commit(
    workspace: &Workspace,
    cut: &WorkspaceCut,
) -> Result<jj_lib::commit::Commit, JjObservationError> {
    let commit_id = jj_lib::backend::CommitId::try_from_hex(&cut.commit_id)
        .ok_or_else(|| JjObservationError::Output("invalid recorded commit ID".into()))?;
    workspace
        .repo_loader()
        .store()
        .get_commit(&commit_id)
        .map_err(repository_error)
}

/// Read one regular UTF-8 file at the exact cut returned by the JJ adapter.
///
/// # Errors
/// Refuses paths outside the project, non-files, and a changed operation.
pub fn read_recorded_file(
    cut: &WorkspaceCut,
    relative_path: &str,
) -> Result<String, JjObservationError> {
    let workspace = open_workspace(&cut.workspace_root)?;
    block_on(async {
        require_current(&workspace, cut).await?;
        let content = read_at_cut(&workspace, cut, relative_path).await?;
        require_current(&workspace, cut).await?;
        Ok(content)
    })
}

async fn read_at_cut(
    workspace: &Workspace,
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
    let path = RepoPath::from_internal_string(relative_path).map_err(repository_error)?;
    let store = workspace.repo_loader().store();
    let commit = recorded_commit(workspace, cut)?;
    let value = commit
        .tree()
        .path_value(path)
        .await
        .map_err(repository_error)?;
    let Some(Some(TreeValue::File { id, .. })) = value.as_resolved() else {
        return Err(JjObservationError::Output(
            "recorded project path must be a regular file".into(),
        ));
    };
    let mut reader = store.read_file(path, id).await.map_err(repository_error)?;
    let mut content = String::new();
    reader
        .read_to_string(&mut content)
        .await
        .map_err(JjObservationError::Io)?;
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

#[cfg(all(test, feature = "real-jj"))]
mod tests;
