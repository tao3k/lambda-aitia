// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! GitOps commit review, signed governance, archived evidence verification, and reviewed push.

pub(crate) mod attestation;
pub(crate) mod audit;
mod common;
pub(crate) mod dsse;
mod evidence;
pub(crate) mod governance;
pub(crate) mod merkle;
mod push;
mod review;
pub(crate) mod sidecar;
pub(crate) mod sigstore;
pub(crate) mod transparency;
pub(crate) mod witness;

pub(crate) use common::{
    CommitOutcome, Result, check_execution_identity, description, dispatch_capability, err,
    execute_commit_action, execute_decision_or_recover, project_id, proposal_binding,
    review_context, review_cut_value, review_input_digest,
};
pub(crate) use evidence::{evidence, evidence_with_program_in};
pub(crate) use governance::{
    Apply, CommitRecovery, apply, attach_revision, prepare, record, recover, recover_attempt,
};
pub(crate) use push::{push, recover_push};
pub(crate) use review::{CommitNarration, CommitProposal, commit_review_report};
