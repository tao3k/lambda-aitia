// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Native `gix` (gitoxide) + `jj-lib` read-only VCS observer for SDLC Git/JJ sidecar audits.
//!
//! Rust provides the native VCS ecosystem (`gix` repository/worktree/ref/OID resolution and
//! `jj-lib` workspace-cut observation) so Scheme POO + ASCENT owns all governance semantics,
//! subdomain rule packs, and temporal causality without duplicating VCS parsers in Scheme.

use crate::{JjObservationError, observe_workspace};
use serde::Serialize;
use std::path::Path;
use std::process::Command;

/// Structured read-only VCS metadata observed natively via `gix` and (when present) `jj-lib`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VcsSidecarObservation {
    pub vcs_backend: String,
    pub workdir: String,
    pub git_dir: String,
    pub is_linked_worktree: bool,
    pub head_commit: String,
    pub base_ref: String,
    pub base_commit: String,
    pub has_jj_workspace: bool,
    pub jj_workspace_name: Option<String>,
    pub jj_change_id: Option<String>,
    pub jj_operation_id: Option<String>,
    pub jj_commit_id: Option<String>,
}

fn vcs_err(message: impl Into<String>) -> JjObservationError {
    JjObservationError::Repository(message.into())
}

fn resolve_base_commit(
    repo: &gix::Repository,
    repo_dir: &Path,
    head_commit: &str,
    base_ref: &str,
) -> Result<String, JjObservationError> {
    if base_ref == "HEAD" {
        return Ok(head_commit.to_owned());
    }
    if let Ok(mut reference) = repo.find_reference(base_ref)
        && let Ok(id) = reference.peel_to_id()
    {
        return Ok(id.to_string());
    }
    if let Ok(oid) = gix::ObjectId::from_hex(base_ref.as_bytes())
        && let Ok(obj) = repo.find_object(oid)
        && let Ok(commit) = obj.peel_to_commit()
    {
        return Ok(commit.id().to_string());
    }
    let spec = format!("{base_ref}^{{commit}}");
    let raw = read_sanitized_git_diff(repo_dir, &["rev-parse", "--verify", &spec])?;
    let hex = raw.trim();
    let oid = gix::ObjectId::from_hex(hex.as_bytes()).map_err(|e| {
        vcs_err(format!(
            "gix rejected resolved OID `{hex}` for `{base_ref}`: {e}"
        ))
    })?;
    let verified = repo
        .find_object(oid)
        .map_err(|e| vcs_err(format!("gix ODB could not verify `{hex}`: {e}")))?
        .peel_to_commit()
        .map_err(|e| vcs_err(format!("gix object `{hex}` is not a commit: {e}")))?
        .id()
        .to_string();
    Ok(verified)
}

/// Observe a Git repository, Git worktree, or colocated JJ+Git workspace natively via
/// `gix` and (when `.jj` is present) `jj-lib`. Never mutates repository state.
///
/// # Errors
/// Fails closed if `repo_dir` is not inside a valid Git repository or `base_ref` cannot be
/// resolved and verified in the `gix` object database.
pub fn observe_vcs_sidecar_state(
    repo_dir: &Path,
    base_ref: &str,
) -> Result<VcsSidecarObservation, JjObservationError> {
    let repo = gix::discover(repo_dir)
        .map_err(|e| vcs_err(format!("gix failed to discover repository: {e}")))?;
    let workdir = repo
        .workdir()
        .ok_or_else(|| vcs_err("bare Git repository has no working tree for sidecar audit"))?
        .to_string_lossy()
        .into_owned();
    let git_dir_path = repo.git_dir().to_path_buf();
    let common_dir_path = repo.common_dir().to_path_buf();
    let is_linked_worktree = git_dir_path != common_dir_path;
    let head_commit = repo
        .head_id()
        .map_err(|e| vcs_err(format!("gix failed to resolve HEAD commit: {e}")))?
        .to_string();
    let base_commit = resolve_base_commit(&repo, repo_dir, &head_commit, base_ref)?;

    let jj_cut = observe_workspace(repo_dir).ok();
    let has_jj_workspace = jj_cut.is_some();
    let vcs_backend = if has_jj_workspace {
        "gix+jj-lib".to_owned()
    } else {
        "gix".to_owned()
    };

    Ok(VcsSidecarObservation {
        vcs_backend,
        workdir,
        git_dir: git_dir_path.to_string_lossy().into_owned(),
        is_linked_worktree,
        head_commit,
        base_ref: base_ref.to_owned(),
        base_commit,
        has_jj_workspace,
        jj_workspace_name: jj_cut.as_ref().map(|c| c.workspace_name().to_owned()),
        jj_change_id: jj_cut.as_ref().map(|c| c.change_id().to_owned()),
        jj_operation_id: jj_cut.as_ref().map(|c| c.operation_id().to_owned()),
        jj_commit_id: jj_cut.as_ref().map(|c| c.commit_id().to_owned()),
    })
}

/// Read-only unified diff extraction with SM32 environment neutralization (`GIT_DIR`,
/// `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_CONFIG_*`, `core.fsmonitor=false`,
/// `core.hooksPath=/dev/null`).
///
/// # Errors
/// Fails closed if Git execution fails.
pub fn read_sanitized_git_diff(
    repo_dir: &Path,
    args: &[&str],
) -> Result<String, JjObservationError> {
    let mut cmd = Command::new("git");
    cmd.current_dir(repo_dir)
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE")
        .env_remove("GIT_OBJECT_DIRECTORY")
        .env_remove("GIT_ALTERNATE_OBJECT_DIRECTORIES")
        .env_remove("GIT_CONFIG_PARAMETERS")
        .env_remove("GIT_CONFIG_COUNT")
        .env_remove("GIT_EXTERNAL_DIFF")
        .args([
            "-c",
            "core.fsmonitor=false",
            "-c",
            "core.hooksPath=/dev/null",
        ])
        .args(args);
    let output = cmd
        .output()
        .map_err(|e| vcs_err(format!("Failed to execute sanitized git {:?}: {e}", args)))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(vcs_err(format!(
            "Sanitized git {:?} failed: {}",
            args,
            stderr.trim()
        )));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}
