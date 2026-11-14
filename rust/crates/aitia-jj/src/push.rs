// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Publish one reviewed commit through JJ's Git backend.

use crate::description::{DescriptionRecovery, verify_description_operation};
use crate::observation::review_bookmarks::{
    configured_push_remote, resolved_remote_commit, route_identity,
};
use crate::observation::workspace::{capture_workspace, open_project_workspace, open_workspace};
use crate::{JjObservationError, PushRemote, WorkspaceCut};
use futures::{StreamExt, executor::block_on};
use gix::remote::Direction::{Fetch, Push};
use jj_lib::backend::CommitId;
use jj_lib::git::{
    GitProgress, GitPushOptions, GitPushRefTargets, GitSidebandLineTerminator,
    GitSubprocessCallback, GitSubprocessOptions, push_refs,
};
use jj_lib::merge::Diff;
use jj_lib::object_id::ObjectId;
use jj_lib::op_store::{OperationId, RefTarget};
use jj_lib::op_walk::walk_ancestors;
use jj_lib::ref_name::{RefName, RemoteName};
use jj_lib::repo::Repo;
use jj_lib::simple_op_heads_store::SimpleOpHeadsStore;
use serde::Serialize;
use std::fmt::Write as _;
use std::io::{self, Write};
use std::path::Path;

const PUSH_OPERATION: &str = "AITIA: push reviewed commit";
const PUSH_REMOTE: &str = "aitia.push.remote";
const PUSH_BOOKMARK: &str = "aitia.push.bookmark";

/// A remote update acknowledged and recorded in JJ history.
#[derive(Debug, Serialize)]
pub struct PushReceipt {
    pub remote: String,
    pub bookmark: String,
    pub commit: String,
    pub operation: String,
}

struct GitOutput;

impl GitSubprocessCallback for GitOutput {
    fn needs_progress(&self) -> bool {
        false
    }

    fn progress(&mut self, _progress: &GitProgress) -> io::Result<()> {
        Ok(())
    }

    fn local_sideband(
        &mut self,
        message: &[u8],
        term: Option<GitSidebandLineTerminator>,
    ) -> io::Result<()> {
        let mut output = io::stderr().lock();
        output.write_all(message)?;
        if let Some(term) = term {
            output.write_all(&[term.as_byte()])?;
        }
        Ok(())
    }

    fn remote_sideband(
        &mut self,
        message: &[u8],
        term: Option<GitSidebandLineTerminator>,
    ) -> io::Result<()> {
        self.local_sideband(message, term)
    }
}

fn repository_error(error: impl std::fmt::Display) -> JjObservationError {
    JjObservationError::Repository(error.to_string())
}

fn require_bookmark_only_push(
    git: &gix::Repository,
    remote: &RemoteName,
) -> Result<(), JjObservationError> {
    let config = git.config_snapshot();
    for key in [
        "push.followTags",
        &format!("remote.{}.mirror", remote.as_str()),
    ] {
        if config.try_boolean(key).map_err(repository_error)? == Some(true) {
            return Err(repository_error(format!("reviewed push cannot use {key}")));
        }
    }
    if config
        .string("push.recurseSubmodules")
        .is_some_and(|mode| !matches!(mode.as_slice(), b"no" | b"check"))
    {
        return Err(repository_error(
            "reviewed push requires push.recurseSubmodules to be no or check",
        ));
    }
    Ok(())
}

fn pin_push_destination(
    parameters: &mut std::ffi::OsString,
    remote: &RemoteName,
    url: &gix::Url,
) -> Result<(), JjObservationError> {
    let url = url.to_bstring();
    let url = std::str::from_utf8(url.as_slice())
        .map_err(|_| repository_error("reviewed push URL must be UTF-8"))?;
    let mut random = [0; 16];
    getrandom::fill(&mut random).map_err(repository_error)?;
    let mut alias = String::from("aitia-reviewed-");
    for byte in random {
        write!(alias, "{byte:02x}").expect("formatting into String");
    }
    alias.push(':');
    // An empty pushurl clears Git's ordered list. The one-use alias makes
    // Git's single insteadOf substitution yield the already resolved URL.
    let push_url_key = format!("remote.{}.pushurl", remote.as_str()).replace('\'', "'\\''");
    let rewrite_key = format!("url.{url}.insteadOf").replace('\'', "'\\''");
    parameters.push(format!(
        " '{push_url_key}'='' '{push_url_key}'='{alias}' '{rewrite_key}'='{alias}'"
    ));
    Ok(())
}

fn require_push_url_reset(
    subprocess: &GitSubprocessOptions,
    git_dir: &Path,
    remote: &RemoteName,
) -> Result<(), JjObservationError> {
    // Older Git appends even an empty pushurl. Check the actual executable
    // before using reset semantics on a remote that might have changed.
    let key = format!("remote.{}.pushurl", remote.as_str());
    let output = std::process::Command::new(&subprocess.executable_path)
        .arg("--git-dir")
        .arg(git_dir)
        .args(["-c", &format!("{key}=aitia-url-reset-old:")])
        .args(["-c", &format!("{key}=")])
        .args(["-c", &format!("{key}=aitia-url-reset-new:")])
        .args([
            "remote",
            "get-url",
            "--push",
            "--all",
            "--",
            remote.as_str(),
        ])
        .output()
        .map_err(repository_error)?;
    if !output.status.success() || output.stdout != b"aitia-url-reset-new:\n" {
        return Err(repository_error(
            "reviewed push requires Git push URL reset support",
        ));
    }
    Ok(())
}

/// Recover an acknowledged push from visible JJ history without transport.
///
/// A missing record leaves the remote outcome unresolved. An existing record
/// describes the past update, regardless of subsequent remote changes.
///
/// # Errors
/// Rejects inconsistent descriptions, foreign workspaces and unreadable history.
pub fn recover_reviewed_push(
    directory: &Path,
    attempt: &DescriptionRecovery,
    remote: &str,
    bookmark: &str,
) -> Result<Option<PushReceipt>, JjObservationError> {
    let workspace = open_project_workspace(directory)?;
    if attempt.workspace != workspace.workspace_name().as_str() {
        return Err(JjObservationError::Output("foreign JJ workspace".into()));
    }
    let applied = OperationId::try_from_hex(&attempt.resulting_operation)
        .ok_or_else(|| repository_error("invalid applied operation"))?;
    let commit = CommitId::try_from_hex(&attempt.resulting_commit)
        .ok_or_else(|| repository_error("invalid applied commit"))?;
    block_on(async {
        let loader = workspace.repo_loader();
        let heads = loader.op_heads_store();
        if heads.downcast_ref::<SimpleOpHeadsStore>().is_none() {
            return Err(repository_error("unsupported JJ operation-head store"));
        }
        let _lock = heads.lock().await.map_err(repository_error)?;
        let current = heads.get_op_heads().await.map_err(repository_error)?;
        let [head] = current.as_slice() else {
            return Ok(None);
        };
        let head = loader
            .load_operation(head)
            .await
            .map_err(repository_error)?;
        let mut history = Box::pin(walk_ancestors(&[head]));
        while let Some(operation) = history.next().await {
            let operation = operation.map_err(repository_error)?;
            let metadata = operation.metadata();
            if metadata.description != PUSH_OPERATION
                || metadata.workspace_name.as_deref() != Some(workspace.workspace_name())
                || metadata.attributes.get(PUSH_REMOTE).map(String::as_str) != Some(remote)
                || metadata.attributes.get(PUSH_BOOKMARK).map(String::as_str) != Some(bookmark)
                || operation.parent_ids() != std::slice::from_ref(&applied)
            {
                continue;
            }
            let before = loader
                .load_operation(&applied)
                .await
                .map_err(repository_error)?;
            verify_description_operation(&workspace, &before, attempt).await?;
            let view = operation.view().await.map_err(repository_error)?;
            let route = RefName::new(bookmark).to_remote_symbol(RemoteName::new(remote));
            if resolved_remote_commit(&view, route) != Some(&commit) {
                return Err(repository_error(
                    "recorded push target differs from the applied commit",
                ));
            }
            return Ok(Some(PushReceipt {
                remote: remote.to_owned(),
                bookmark: bookmark.to_owned(),
                commit: commit.hex(),
                operation: operation.id().hex(),
            }));
        }
        Ok(None)
    })
}

/// Push an existing remote bookmark after rechecking its reviewed cut and description.
/// The caller owns effect admission. JJ owns remote leases and transport.
///
/// # Errors
/// Refuses stale cuts, description mismatches, conflicting or absent bookmarks,
/// non-fast-forward remote history, multiple push URLs, denied admission and
/// rejected remote updates.
/// Independent local bookmark work is preserved.
/// A transport error retains an unknown remote outcome for reconciliation.
pub fn push_reviewed_description(
    expected: &WorkspaceCut,
    description: &str,
    remote: &str,
    bookmark: &str,
    consume_admission: impl FnOnce(PushRemote, &str, &str) -> bool,
) -> Result<PushReceipt, JjObservationError> {
    let workspace = open_workspace(expected.workspace_root())?;
    block_on(async {
        let loader = workspace.repo_loader();
        let heads = loader.op_heads_store();
        if heads.downcast_ref::<SimpleOpHeadsStore>().is_none() {
            return Err(repository_error(
                "push requires the JJ simple operation-head store",
            ));
        }
        let _lock = heads.lock().await.map_err(repository_error)?;
        if capture_workspace(&workspace).await? != *expected {
            return Err(JjObservationError::ChangedOperation);
        }
        let operation_id = OperationId::try_from_hex(expected.operation_id())
            .ok_or_else(|| repository_error("invalid reviewed operation"))?;
        let operation = loader
            .load_operation(&operation_id)
            .await
            .map_err(repository_error)?;
        let repo = loader.load_at(&operation).await.map_err(repository_error)?;
        let commit_id = CommitId::try_from_hex(expected.commit_id())
            .ok_or_else(|| repository_error("invalid reviewed commit"))?;
        let commit = repo
            .store()
            .get_commit(&commit_id)
            .map_err(repository_error)?;
        if description.trim().is_empty() || commit.description() != description {
            return Err(repository_error(
                "actual commit differs from the reviewed description",
            ));
        }
        let name = RefName::new(bookmark);
        let remote = RemoteName::new(remote);
        let local = repo.view().get_local_bookmark(name).as_normal();
        let previous = resolved_remote_commit(repo.view(), name.to_remote_symbol(remote))
            .ok_or_else(|| {
                repository_error("push requires an existing resolved remote bookmark")
            })?;
        if !repo
            .index()
            .is_ancestor(previous, &commit_id)
            .await
            .map_err(repository_error)?
        {
            return Err(repository_error(
                "reviewed push must preserve bookmark history",
            ));
        }
        // A separate worktree may own unpublished work on the local bookmark.
        // Remote admission is bound to the reviewed cut and remote lease, not
        // permission to replace that independent local branch.
        let advance_local = match local {
            Some(local) => repo
                .index()
                .is_ancestor(local, &commit_id)
                .await
                .map_err(repository_error)?,
            None => false,
        };
        let git = jj_lib::git::get_git_backend(repo.store())
            .map_err(repository_error)?
            .git_repo();
        let (reviewed_route, destination) = configured_push_remote(&git, remote)?;
        require_bookmark_only_push(&git, remote)?;
        // Git pushes to every configured push URL. A single JJ bookmark
        // lease and acknowledgement can only qualify one destination.
        if reviewed_route.urls(Push).count() != 1 {
            return Err(repository_error(
                "reviewed push requires exactly one destination URL",
            ));
        }
        let mut subprocess =
            GitSubprocessOptions::from_settings(repo.settings()).map_err(repository_error)?;
        require_push_url_reset(&subprocess, git.git_dir(), remote)?;
        if !consume_admission(
            destination,
            &previous.hex(),
            &route_identity(&reviewed_route),
        ) {
            return Err(repository_error("push admission refused"));
        }
        // The admission callback can perform I/O. The backend's existing
        // repository handle retains its configuration snapshot, whereas Git's
        // subprocess will read the live configuration when it starts.
        let reopened = gix::open_opts(
            git.git_dir(),
            git.open_options().clone().open_path_as_is(true),
        )
        .map_err(|_| repository_error("could not re-read Git push configuration"))?;
        require_bookmark_only_push(&reopened, remote)?;
        let (current_route, _) = configured_push_remote(&reopened, remote)
            .map_err(|_| repository_error("could not re-read Git push destination"))?;
        if [Fetch, Push].into_iter().any(|direction| {
            reviewed_route
                .urls(direction)
                .ne(current_route.urls(direction))
        }) {
            return Err(repository_error(
                "Git push destination changed during admission",
            ));
        }
        let mut transaction = repo.start_transaction();
        // Command-scope settings keep a late config write from widening the
        // refspec. Retain the caller's other command-scope Git settings.
        let mut parameters = std::env::var_os("GIT_CONFIG_PARAMETERS").unwrap_or_default();
        let mirror_key = format!("remote.{}.mirror", remote.as_str()).replace('\'', "'\\''");
        if !parameters.is_empty() {
            parameters.push(" ");
        }
        // Keep a check-only setting, but never let Git publish submodules.
        let recurse = reopened.config_snapshot().string("push.recurseSubmodules");
        let recurse = if recurse
            .as_ref()
            .is_some_and(|mode| mode.as_slice() == b"check")
        {
            "check"
        } else {
            "no"
        };
        parameters.push(format!(
            "'push.followTags'='false' '{mirror_key}'='false' 'push.recurseSubmodules'='{recurse}'"
        ));
        let push_url = reviewed_route
            .url(Push)
            .ok_or_else(|| repository_error("reviewed push destination is missing"))?;
        pin_push_destination(&mut parameters, remote, push_url)?;
        subprocess
            .environment
            .insert("GIT_CONFIG_PARAMETERS".into(), parameters);
        let targets = GitPushRefTargets {
            bookmarks: vec![(
                name.to_owned(),
                Diff {
                    before: Some(previous.clone()),
                    after: Some(commit_id.clone()),
                },
            )],
            tags: Vec::new(),
        };
        let stats = push_refs(
            transaction.repo_mut(),
            subprocess,
            remote,
            &targets,
            &mut GitOutput,
            &GitPushOptions::default(),
        )
        .map_err(repository_error)?;
        if !stats.all_ok() {
            return Err(repository_error(format!(
                "JJ rejected the remote update: {stats:?}"
            )));
        }
        // JJ's all_ok checks for rejections. Publication also needs the
        // positive acknowledgement and corresponding update to its view.
        let expected_ref = format!("refs/heads/{bookmark}");
        if !matches!(stats.pushed.as_slice(), [reference] if reference.as_str() == expected_ref)
            || resolved_remote_commit(transaction.repo().view(), name.to_remote_symbol(remote))
                != Some(&commit_id)
        {
            return Err(repository_error(
                "JJ did not acknowledge the selected bookmark; push outcome is unresolved",
            ));
        }
        if advance_local {
            transaction
                .repo_mut()
                .set_local_bookmark_target(name, RefTarget::normal(commit_id.clone()));
        }
        transaction.set_workspace_name(workspace.workspace_name());
        transaction.set_attribute(PUSH_REMOTE.into(), remote.as_str().to_owned());
        transaction.set_attribute(PUSH_BOOKMARK.into(), bookmark.to_owned());
        let written = transaction
            .write(PUSH_OPERATION)
            .await
            .map_err(repository_error)?;
        heads
            .update_op_heads(written.operation().parent_ids(), written.operation().id())
            .await
            .map_err(repository_error)?;
        Ok(PushReceipt {
            remote: remote.as_str().to_owned(),
            bookmark: bookmark.to_owned(),
            commit: commit_id.hex(),
            operation: written.operation().id().hex(),
        })
    })
}
