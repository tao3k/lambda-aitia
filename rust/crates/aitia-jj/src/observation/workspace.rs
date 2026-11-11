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

/// An observation of an already recorded workspace. This carries no grant.
/// Identity fields are fixed by the adapter when it observes the workspace.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
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
    Output(String),
    Repository(String),
    ChangedOperation,
}

impl std::fmt::Display for JjObservationError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Output(error) | Self::Repository(error) => formatter.write_str(error),
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

pub(crate) fn open_workspace(directory: &Path) -> Result<Workspace, JjObservationError> {
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

pub(crate) async fn capture_workspace(
    workspace: &Workspace,
) -> Result<WorkspaceCut, JjObservationError> {
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

pub(super) async fn require_current(
    workspace: &Workspace,
    cut: &WorkspaceCut,
) -> Result<(), JjObservationError> {
    if current_operation(workspace).await?.hex() != cut.operation_id {
        return Err(JjObservationError::ChangedOperation);
    }
    Ok(())
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

/// Git object identities observed independently of JJ's workspace view.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct RecordedConfigurationAudit {
    pub git_commit: String,
    pub git_tree: String,
    pub git_parents: Vec<String>,
}

/// Check the Git commit object against the exact recorded JJ workspace cut.
///
/// # Errors
/// Rejects a stale cut or a Git object whose version, tree or parent order differs.
pub fn audit_recorded_configuration(
    cut: &WorkspaceCut,
) -> Result<RecordedConfigurationAudit, JjObservationError> {
    let workspace = open_workspace(cut.workspace_root())?;
    block_on(async {
        if capture_workspace(&workspace).await? != *cut {
            return Err(JjObservationError::ChangedOperation);
        }
        let store = workspace.repo_loader().store();
        let repository = jj_lib::git::get_git_backend(store)
            .map_err(repository_error)?
            .git_repo();
        let expected = jj_lib::backend::CommitId::try_from_hex(cut.commit_id())
            .ok_or_else(|| JjObservationError::Output("invalid recorded commit ID".into()))?;
        let mut git_id = repository.object_hash().null();
        if git_id.as_mut_slice().len() != expected.as_bytes().len() {
            return Err(JjObservationError::Output(
                "incompatible Git object ID".into(),
            ));
        }
        git_id.as_mut_slice().copy_from_slice(expected.as_bytes());
        let commit = repository.find_commit(git_id).map_err(repository_error)?;
        let audit = RecordedConfigurationAudit {
            git_commit: commit.id().to_string(),
            git_tree: commit.tree_id().map_err(repository_error)?.to_string(),
            git_parents: commit.parent_ids().map(|id| id.to_string()).collect(),
        };
        // The synthetic JJ root represents a Git commit with no parents.
        let parents = if cut.parent_ids() == [store.root_commit_id().hex()] {
            &[][..]
        } else {
            cut.parent_ids()
        };
        if audit.git_commit != cut.commit_id()
            || audit.git_tree != cut.tree_id()
            || audit.git_parents != parents
        {
            return Err(JjObservationError::Output(
                "Git configuration differs from the recorded JJ cut".into(),
            ));
        }
        require_current(&workspace, cut).await?;
        Ok(audit)
    })
}

/// One difference between the recorded commit and its single parent.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct RecordedPathChange {
    pub path: String,
    pub before: Option<RecordedTreeEntry>,
    pub after: Option<RecordedTreeEntry>,
}

#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum RecordedTreeEntry {
    File { id: String, executable: bool },
    Symlink { id: String },
    GitSubmodule { id: String },
}

fn recorded_tree_entry(
    value: &jj_lib::backend::MergedTreeValue,
) -> Result<Option<RecordedTreeEntry>, JjObservationError> {
    let entry = match value.as_resolved() {
        Some(None) => None,
        Some(Some(TreeValue::File { id, executable, .. })) => Some(RecordedTreeEntry::File {
            id: id.hex(),
            executable: *executable,
        }),
        Some(Some(TreeValue::Symlink(id))) => Some(RecordedTreeEntry::Symlink { id: id.hex() }),
        Some(Some(TreeValue::GitSubmodule(id))) => {
            Some(RecordedTreeEntry::GitSubmodule { id: id.hex() })
        }
        _ => {
            return Err(JjObservationError::Output(
                "recorded change has an unresolved path".into(),
            ));
        }
    };
    Ok(entry)
}

/// Read a stable configuration inventory without snapshotting working files.
///
/// # Errors
/// Refuses stale cuts, merges and unresolved entries.
pub fn recorded_changes(cut: &WorkspaceCut) -> Result<Vec<RecordedPathChange>, JjObservationError> {
    let workspace = open_workspace(cut.workspace_root())?;
    block_on(async {
        require_current(&workspace, cut).await?;
        let commit = recorded_commit(&workspace, cut)?;
        let [parent_id] = commit.parent_ids() else {
            return Err(JjObservationError::Output(
                "recorded inventory requires a single parent".into(),
            ));
        };
        let parent = workspace
            .repo_loader()
            .store()
            .get_commit(parent_id)
            .map_err(repository_error)?;
        let mut diff = parent
            .tree()
            .diff(&commit.tree(), &jj_lib::matchers::EverythingMatcher);
        let mut changes = Vec::new();
        while let Some(entry) = diff.next().await {
            let values = entry.values.map_err(repository_error)?;
            changes.push(RecordedPathChange {
                path: entry.path.as_internal_file_string().to_owned(),
                before: recorded_tree_entry(&values.before)?,
                after: recorded_tree_entry(&values.after)?,
            });
        }
        changes.sort_unstable_by(|a, b| a.path.cmp(&b.path));
        require_current(&workspace, cut).await?;
        Ok(changes)
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

/// Read a declared input set from one recorded tree under a total byte limit.
///
/// # Errors
/// Refuses invalid paths, non-files, inputs over the limit and a changed operation.
pub fn read_recorded_files(
    cut: &WorkspaceCut,
    paths: &[&str],
    byte_limit: usize,
) -> Result<Vec<Vec<u8>>, JjObservationError> {
    let workspace = open_workspace(&cut.workspace_root)?;
    block_on(async {
        require_current(&workspace, cut).await?;
        let commit = recorded_commit(&workspace, cut)?;
        let mut remaining = byte_limit;
        let mut files = Vec::with_capacity(paths.len());
        for path in paths {
            let mut bytes = Vec::new();
            file_at_commit(&workspace, &commit, path)
                .await?
                .take((remaining as u64).saturating_add(1))
                .read_to_end(&mut bytes)
                .await
                .map_err(JjObservationError::Io)?;
            remaining = remaining.checked_sub(bytes.len()).ok_or_else(|| {
                JjObservationError::Output("recorded inputs exceed the byte limit".into())
            })?;
            files.push(bytes);
        }
        require_current(&workspace, cut).await?;
        Ok(files)
    })
}

pub(super) async fn read_at_cut(
    workspace: &Workspace,
    cut: &WorkspaceCut,
    relative_path: &str,
) -> Result<String, JjObservationError> {
    let commit = recorded_commit(workspace, cut)?;
    let mut reader = file_at_commit(workspace, &commit, relative_path).await?;
    let mut content = String::new();
    reader
        .read_to_string(&mut content)
        .await
        .map_err(JjObservationError::Io)?;
    Ok(content)
}

async fn file_at_commit(
    workspace: &Workspace,
    commit: &jj_lib::commit::Commit,
    relative_path: &str,
) -> Result<impl futures::io::AsyncRead + Unpin + use<>, JjObservationError> {
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
    store.read_file(path, id).await.map_err(repository_error)
}

/// Resolve the Git project for a directory.
///
/// # Errors
/// The directory must be in a Git working tree.
pub fn git_project_root(directory: &Path) -> Result<PathBuf, JjObservationError> {
    // Bootstrap has no JJ workspace yet. Reuse its backend's read-only
    // discovery primitive; recorded trees and all mutations remain JJ-owned.
    // This API does not apply GIT_DIR/GIT_WORK_TREE environment overrides.
    let (repository, _) = gix::discover::upwards(directory).map_err(repository_error)?;
    let (_, root) = repository.into_repository_and_work_tree_directories();
    root.ok_or_else(|| {
        JjObservationError::Output("nearest Git repository has no working tree".into())
    })?
    .canonicalize()
    .map_err(JjObservationError::Io)
}
