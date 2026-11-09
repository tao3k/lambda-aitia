// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Prepare a description-only rewrite, then conditionally publish its JJ operation.

use crate::observation::workspace::{capture_workspace, open_workspace};
use crate::{JjObservationError, WorkspaceCut};
use futures::{StreamExt, executor::block_on};
use jj_lib::backend::CommitId;
use jj_lib::object_id::ObjectId;
use jj_lib::op_store::OperationId;
use jj_lib::op_walk::walk_ancestors;
use jj_lib::operation::Operation;
use jj_lib::repo::Repo;
use jj_lib::simple_op_heads_store::SimpleOpHeadsStore;
use jj_lib::workspace::Workspace;
use serde::{Deserialize, Serialize};
use std::path::Path;

const DESCRIPTION_OPERATION: &str = "AITIA: finalize commit description";

/// Exact identity of the prepared write. It becomes a receipt only after readback.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct DescriptionReceipt {
    pub expected: WorkspaceCut,
    pub resulting_operation: String,
    pub resulting_commit: String,
    pub description: String,
}

/// Read-only recovery input suitable for storage by the admission owner.
#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DescriptionRecovery {
    pub workspace: String,
    pub expected_operation: String,
    pub expected_commit: String,
    pub resulting_operation: String,
    pub resulting_commit: String,
    pub description: String,
}

impl DescriptionReceipt {
    pub fn recovery_record(&self) -> DescriptionRecovery {
        DescriptionRecovery {
            workspace: self.expected.workspace_name().to_owned(),
            expected_operation: self.expected.operation_id().to_owned(),
            expected_commit: self.expected.commit_id().to_owned(),
            resulting_operation: self.resulting_operation.clone(),
            resulting_commit: self.resulting_commit.clone(),
            description: self.description.clone(),
        }
    }
}

#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DescriptionOutcome {
    Applied,
    Unresolved,
}

/// Recover a prepared operation from the visible history of one JJ workspace.
///
/// The caller must obtain the recovery input from its trusted attempt record.
/// The result describes a repository effect. It confers no write or push authority.
///
/// # Errors
/// Refuses malformed identities, ambiguous heads, and inconsistent history.
pub fn reconcile_description(
    directory: &Path,
    record: &DescriptionRecovery,
) -> Result<DescriptionOutcome, JjObservationError> {
    let workspace = open_workspace(directory)?;
    if record.workspace != workspace.workspace_name().as_str() {
        return Err(JjObservationError::Output("foreign JJ workspace".into()));
    }
    let resulting_operation = OperationId::try_from_hex(&record.resulting_operation)
        .ok_or_else(|| JjObservationError::Output("invalid resulting operation".into()))?;

    block_on(async {
        let loader = workspace.repo_loader();
        let heads = loader.op_heads_store();
        if heads.downcast_ref::<SimpleOpHeadsStore>().is_none() {
            return Err(JjObservationError::Output(
                "unsupported JJ operation-head store".into(),
            ));
        }
        let _lock = heads.lock().await.map_err(repository_error)?;
        let current = heads.get_op_heads().await.map_err(repository_error)?;
        let [head] = current.as_slice() else {
            return Ok(DescriptionOutcome::Unresolved);
        };
        let head = loader
            .load_operation(head)
            .await
            .map_err(repository_error)?;
        let mut history = Box::pin(walk_ancestors(&[head]));
        while let Some(operation) = history.next().await {
            let operation = operation.map_err(repository_error)?;
            if operation.id() != &resulting_operation {
                continue;
            }
            verify_description_operation(&workspace, &operation, record).await?;
            return Ok(DescriptionOutcome::Applied);
        }
        // A missing operation is not evidence that a previous write never happened.
        Ok(DescriptionOutcome::Unresolved)
    })
}

/// Reopen an unpublished rewrite after review without generating a new operation.
///
/// The caller supplies the current recorded cut and the description freshly
/// verified by the draft Contract. Publishing still requires independent admission.
///
/// # Errors
/// Rejects a stale cut, missing operation or any change outside the reviewed rewrite.
pub fn reopen_description(
    expected: &WorkspaceCut,
    description: &str,
    record: &DescriptionRecovery,
) -> Result<PreparedDescription, JjObservationError> {
    if record.workspace != expected.workspace_name()
        || record.expected_operation != expected.operation_id()
        || record.expected_commit != expected.commit_id()
        || record.description != description
    {
        return Err(JjObservationError::Output(
            "prepared rewrite does not match the reviewed cut and description".into(),
        ));
    }
    let workspace = open_workspace(expected.workspace_root())?;
    let operation = OperationId::try_from_hex(&record.resulting_operation)
        .ok_or_else(|| JjObservationError::Output("invalid resulting operation".into()))?;
    block_on(async {
        if capture_workspace(&workspace).await? != *expected {
            return Err(JjObservationError::ChangedOperation);
        }
        let loaded = workspace
            .repo_loader()
            .load_operation(&operation)
            .await
            .map_err(repository_error)?;
        verify_description_operation(&workspace, &loaded, record).await
    })?;
    Ok(PreparedDescription {
        workspace,
        operation,
        receipt: DescriptionReceipt {
            expected: expected.clone(),
            resulting_operation: record.resulting_operation.clone(),
            resulting_commit: record.resulting_commit.clone(),
            description: description.to_owned(),
        },
    })
}

async fn verify_description_operation(
    workspace: &Workspace,
    operation: &Operation,
    record: &DescriptionRecovery,
) -> Result<(), JjObservationError> {
    let loader = workspace.repo_loader();
    let expected_operation = OperationId::try_from_hex(&record.expected_operation)
        .ok_or_else(|| JjObservationError::Output("invalid expected operation".into()))?;
    let expected_commit = CommitId::try_from_hex(&record.expected_commit)
        .ok_or_else(|| JjObservationError::Output("invalid expected commit".into()))?;
    let resulting_commit = CommitId::try_from_hex(&record.resulting_commit)
        .ok_or_else(|| JjObservationError::Output("invalid resulting commit".into()))?;
    if operation.metadata().description != DESCRIPTION_OPERATION
        || operation.parent_ids() != std::slice::from_ref(&expected_operation)
    {
        return Err(JjObservationError::Output(
            "recovery operation does not match the prepared rewrite".into(),
        ));
    }

    let before = loader
        .load_operation(&expected_operation)
        .await
        .map_err(repository_error)?;
    let before_view = before.view().await.map_err(repository_error)?;
    let after_view = operation.view().await.map_err(repository_error)?;
    let name = workspace.workspace_name();
    if before_view.wc_commit_ids().get(name) != Some(&expected_commit)
        || after_view.wc_commit_ids().get(name) != Some(&resulting_commit)
    {
        return Err(JjObservationError::Output(
            "recovery workspace commits do not match".into(),
        ));
    }
    let mut intended_view = before_view.store_view().clone();
    if !intended_view.head_ids.remove(&expected_commit) {
        return Err(JjObservationError::Output(
            "recovered description was not a leaf rewrite".into(),
        ));
    }
    intended_view.head_ids.insert(resulting_commit.clone());
    intended_view
        .wc_commit_ids
        .insert(name.to_owned(), resulting_commit.clone());
    let old = loader
        .store()
        .get_commit(&expected_commit)
        .map_err(repository_error)?;
    let new = loader
        .store()
        .get_commit(&resulting_commit)
        .map_err(repository_error)?;
    if old.is_signed()
        || new.is_signed()
        || old.description() == record.description
        || record.description.trim().is_empty()
        || after_view.store_view() != &intended_view
        || old.change_id() != new.change_id()
        || old.tree_ids() != new.tree_ids()
        || old.parent_ids() != new.parent_ids()
        || old.author() != new.author()
        || old.committer() != new.committer()
        || new.description() != record.description
    {
        return Err(JjObservationError::Output(
            "recovered description does not match the recorded effect".into(),
        ));
    }
    Ok(())
}

/// A prepared operation is still invisible from the repository head.
#[must_use]
pub struct PreparedDescription {
    workspace: Workspace,
    operation: OperationId,
    receipt: DescriptionReceipt,
}

fn repository_error(error: impl std::fmt::Display) -> JjObservationError {
    JjObservationError::Repository(error.to_string())
}

/// Prepare an operation for an already recorded working-copy commit.
/// This allows a description rewrite at a leaf without changing refs or files.
///
/// # Errors
/// Rejects a stale cut, unsupported operation-head store or wider rewrite.
pub fn prepare_description(
    expected: &WorkspaceCut,
    description: &str,
) -> Result<PreparedDescription, JjObservationError> {
    if description.trim().is_empty() {
        return Err(JjObservationError::Output(
            "commit description is empty".into(),
        ));
    }
    let workspace = open_workspace(expected.workspace_root())?;
    let loader = workspace.repo_loader();
    if loader
        .op_heads_store()
        .downcast_ref::<SimpleOpHeadsStore>()
        .is_none()
    {
        return Err(JjObservationError::Output(
            "description writes require the JJ simple operation-head store".into(),
        ));
    }

    let (operation, receipt) = block_on(async {
        if capture_workspace(&workspace).await? != *expected {
            return Err(JjObservationError::ChangedOperation);
        }
        let base_id = jj_lib::op_store::OperationId::try_from_hex(expected.operation_id())
            .ok_or_else(|| JjObservationError::Output("invalid expected operation".into()))?;
        let base = loader
            .load_operation(&base_id)
            .await
            .map_err(repository_error)?;
        let repo = loader.load_at(&base).await.map_err(repository_error)?;
        let commit_id = CommitId::try_from_hex(expected.commit_id())
            .ok_or_else(|| JjObservationError::Output("invalid expected commit".into()))?;
        let commit = repo
            .store()
            .get_commit(&commit_id)
            .map_err(repository_error)?;
        if commit.is_signed() || commit.description() == description {
            return Err(JjObservationError::Output(
                "description writes require a changed description and an unsigned leaf".into(),
            ));
        }
        let mut intended_view = repo.view().store_view().clone();
        if !intended_view.head_ids.remove(&commit_id) {
            return Err(JjObservationError::Output(
                "description writes require a working-copy leaf".into(),
            ));
        }

        let mut transaction = repo.start_transaction();
        let rewritten = transaction
            .repo_mut()
            .rewrite_commit(&commit)
            .set_description(description)
            .set_author(commit.author().clone())
            .set_committer(commit.committer().clone())
            .write()
            .await
            .map_err(repository_error)?;
        transaction
            .repo_mut()
            .rebase_descendants()
            .await
            .map_err(repository_error)?;
        intended_view.head_ids.insert(rewritten.id().clone());
        intended_view.wc_commit_ids.insert(
            workspace.workspace_name().to_owned(),
            rewritten.id().clone(),
        );
        if rewritten.id() == commit.id()
            || rewritten.change_id() != commit.change_id()
            || rewritten.tree_ids() != commit.tree_ids()
            || rewritten.parent_ids() != commit.parent_ids()
            || transaction.repo().view().store_view() != &intended_view
        {
            return Err(JjObservationError::Output(
                "description would change more than the recorded workspace leaf".into(),
            ));
        }

        transaction.set_workspace_name(workspace.workspace_name());
        let prepared = transaction
            .write(DESCRIPTION_OPERATION)
            .await
            .map_err(repository_error)?;
        let operation = prepared.operation().id().clone();
        let receipt = DescriptionReceipt {
            expected: expected.clone(),
            resulting_operation: operation.hex(),
            resulting_commit: rewritten.id().hex(),
            description: description.to_owned(),
        };
        prepared.leave_unpublished();
        Ok((operation, receipt))
    })?;
    Ok(PreparedDescription {
        workspace,
        operation,
        receipt,
    })
}

impl PreparedDescription {
    /// Facts the independent authority must bind to its one-shot decision.
    pub fn proposed_receipt(&self) -> &DescriptionReceipt {
        &self.receipt
    }

    /// Publish through the same operation-head lock that JJ publication uses.
    ///
    /// The owning application supplies a durable, one-shot admission for this
    /// exact proposed operation. The callback runs under the repository lock
    /// and must not take it again.
    ///
    /// # Errors
    /// Refuses stale or denied writes. An error during or after publication
    /// requires reconciliation of the recorded attempt before retry.
    pub fn publish(
        self,
        consume_admission: impl FnOnce(&DescriptionReceipt) -> bool,
    ) -> Result<DescriptionReceipt, JjObservationError> {
        block_on(async {
            let loader = self.workspace.repo_loader();
            let heads = loader.op_heads_store();
            if heads.downcast_ref::<SimpleOpHeadsStore>().is_none() {
                return Err(JjObservationError::Output(
                    "description writes require the JJ simple operation-head store".into(),
                ));
            }
            let _lock = heads.lock().await.map_err(repository_error)?;
            if capture_workspace(&self.workspace).await? != self.receipt.expected {
                return Err(JjObservationError::ChangedOperation);
            }
            let operation = loader
                .load_operation(&self.operation)
                .await
                .map_err(repository_error)?;
            if !consume_admission(&self.receipt) {
                return Err(JjObservationError::Output(
                    "description write admission refused".into(),
                ));
            }
            heads
                .update_op_heads(operation.parent_ids(), operation.id())
                .await
                .map_err(repository_error)?;
            let observed = capture_workspace(&self.workspace).await?;
            let commit_id = CommitId::try_from_hex(observed.commit_id())
                .ok_or_else(|| JjObservationError::Output("invalid resulting commit".into()))?;
            let commit = loader
                .store()
                .get_commit(&commit_id)
                .map_err(repository_error)?;
            if observed.operation_id() != self.receipt.resulting_operation
                || observed.commit_id() != self.receipt.resulting_commit
                || observed.change_id() != self.receipt.expected.change_id()
                || observed.tree_id() != self.receipt.expected.tree_id()
                || observed.parent_ids() != self.receipt.expected.parent_ids()
                || commit.description() != self.receipt.description
            {
                return Err(JjObservationError::Output(
                    "published description did not match prepared operation".into(),
                ));
            }
            Ok(self.receipt)
        })
    }
}
