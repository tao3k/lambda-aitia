// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Publish one reviewed commit through JJ's Git backend.

use crate::observation::workspace::{capture_workspace, open_workspace};
use crate::{JjObservationError, WorkspaceCut};
use futures::executor::block_on;
use jj_lib::backend::CommitId;
use jj_lib::git::{
    GitProgress, GitPushOptions, GitPushRefTargets, GitSidebandLineTerminator,
    GitSubprocessCallback, GitSubprocessOptions, push_refs,
};
use jj_lib::merge::Diff;
use jj_lib::object_id::ObjectId;
use jj_lib::op_store::{OperationId, RefTarget};
use jj_lib::ref_name::{RefName, RemoteName};
use jj_lib::repo::Repo;
use jj_lib::simple_op_heads_store::SimpleOpHeadsStore;
use serde::Serialize;
use std::io::{self, Write};

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

/// Push an existing remote bookmark after rechecking its reviewed cut and description.
/// The caller owns effect admission. JJ owns remote leases and transport.
///
/// # Errors
/// Refuses stale cuts, description mismatches, conflicting or absent bookmarks,
/// non-fast-forward remote history, denied admission and rejected remote updates.
/// Independent local bookmark work is preserved.
/// A transport error retains an unknown remote outcome for reconciliation.
pub fn push_reviewed_description(
    expected: &WorkspaceCut,
    description: &str,
    remote: &str,
    bookmark: &str,
    consume_admission: impl FnOnce() -> bool,
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
        let previous = repo
            .view()
            .get_remote_bookmark(name.to_remote_symbol(remote))
            .target
            .as_normal()
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
        if !consume_admission() {
            return Err(repository_error("push admission refused"));
        }
        let mut transaction = repo.start_transaction();
        let subprocess =
            GitSubprocessOptions::from_settings(repo.settings()).map_err(repository_error)?;
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
        if advance_local {
            transaction
                .repo_mut()
                .set_local_bookmark_target(name, RefTarget::normal(commit_id.clone()));
        }
        transaction.set_workspace_name(workspace.workspace_name());
        let written = transaction
            .write("AITIA: push reviewed commit")
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
