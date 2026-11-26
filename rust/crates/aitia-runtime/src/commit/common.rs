// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Shared commit helpers and high-level command orchestration over review & governance modules.

use super::{
    Apply, CommitNarration, CommitProposal, CommitRecovery, apply, attach_revision,
    commit_review_report, prepare, record, recover, recover_attempt,
};
use crate::{
    HostCapabilityRegistry, HostEffectClass, MAX_REQUEST_BYTES, project, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use serde_json::{Value, json};
use std::io;
use std::path::Path;

pub(crate) type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

pub(crate) enum CommitOutcome {
    Accepted(Value),
    RejectedDraft(Value),
}

pub(crate) fn err(message: impl Into<String>) -> Box<dyn std::error::Error> {
    io::Error::other(message.into()).into()
}

pub(crate) fn dispatch_capability(
    id: &str,
    effect_class: HostEffectClass,
    payload: &Value,
    fence: Option<String>,
) -> Result<Value> {
    Ok(HostCapabilityRegistry::default_linked().dispatch_json(id, effect_class, payload, fence)?)
}

pub(crate) fn project_id(report: &Value) -> Result<&str> {
    report["policy"]["project"]
        .as_str()
        .ok_or_else(|| err("Missing project identity"))
}

pub(crate) fn proposal_binding(proposal: &CommitProposal) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(proposal)?))
}

pub(crate) fn review_context(report: &Value) -> Result<&str> {
    report["review"]["context"]
        .as_str()
        .ok_or_else(|| err("Missing commit review context"))
}

pub(crate) fn description(report: &Value) -> Result<&str> {
    report["review"]["description"]
        .as_str()
        .ok_or_else(|| err("Missing reviewed description"))
}

pub(crate) fn review_cut_value(cut: &WorkspaceCut) -> Value {
    json!({
        "workspace": cut.workspace_name(),
        "change": cut.change_id(),
        "operation": cut.operation_id(),
        "commit": cut.commit_id(),
        "tree": cut.tree_id(),
        "parents": cut.parent_ids(),
    })
}

pub(crate) fn review_input_digest(
    cut: &Value,
    sources: &aitia_jj::RecordedProjectSources,
    changes: &[aitia_jj::RecordedPathChange],
) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(&json!([
        cut, sources, changes
    ]))?))
}

pub(crate) fn check_execution_identity(
    check: &Value,
    input_digest: &str,
    report_digest: &str,
) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(&json!([
        check,
        input_digest,
        report_digest
    ]))?))
}

pub(crate) fn execute_decision_or_recover(command: &str, input: &str) -> Result<Value> {
    let approval = if command == "recover" {
        match serde_json::from_str(input)? {
            CommitRecovery::Attempt { attempt } => {
                return recover_attempt(Path::new("."), &attempt);
            }
            CommitRecovery::Approval { approval } => Some(approval),
        }
    } else {
        None
    };
    with_linked_program(|program| {
        Ok((|| {
            let (cut, config) = project::resolve_recorded_project(&program, Path::new("."))?;
            let project = config
                .commit
                .as_ref()
                .and_then(|policy| policy["project"].as_str())
                .ok_or_else(|| err("No recorded commit project"))?;
            if let Some(approval) = approval.as_deref() {
                recover(&program, &cut, project, approval)
            } else {
                if config
                    .commit
                    .as_ref()
                    .is_none_or(|policy| policy["governance"] != "signed")
                {
                    return Err(err("This project does not use signed commit approvals"));
                }
                record(&program, &cut, project, input)
            }
        })())
    })?
}

pub(crate) fn execute_commit_action(
    command: Option<&str>,
    preview_applied: bool,
    input: Option<&str>,
) -> Result<CommitOutcome> {
    let (draft, attempt) = if command == Some("apply") || preview_applied {
        let raw = input.ok_or_else(|| err("Missing commit apply input"))?;
        (None, Some(serde_json::from_str::<Apply>(raw)?))
    } else if command.is_some() {
        let raw = input.ok_or_else(|| err("Missing commit narration input"))?;
        (Some(serde_json::from_str::<CommitNarration>(raw)?), None)
    } else {
        (None, None)
    };
    let draft = attempt.as_ref().map(|item| &item.draft).or(draft.as_ref());
    let reviewed = attempt.as_ref().filter(|_| preview_applied);
    let observed = observe_project_sources(Path::new("."), MAX_REQUEST_BYTES as usize)?;
    let origin = reviewed
        .map(|item| aitia_jj::observe_description_origin(&observed.0, &item.attempt))
        .transpose()?;
    if let Some(item) = attempt.as_ref().filter(|_| command == Some("apply")) {
        item.attempt.require_expected_cut(&observed.0)?;
    }
    with_linked_program(|program| {
        Ok((|| {
            let (cut, mut result, _) = commit_review_report(
                &program,
                observed,
                draft,
                origin.as_ref(),
                command == Some("preview"),
            )?;
            if let Some(item) = reviewed {
                result["review"]["reviewContextCurrent"] = json!(
                    result["review"]["context"].as_str() == Some(item.draft.context.as_str())
                );
                result["review"]["matchesWrittenDescription"] = json!(
                    result["review"]["previewDescription"].as_str()
                        == Some(item.attempt.description.as_str())
                );
            }
            let required_text = if command == Some("preview") {
                "previewDescription"
            } else {
                "description"
            };
            if draft.is_some() && result["review"][required_text].is_null() {
                return Ok(CommitOutcome::RejectedDraft(result));
            }
            match command {
                Some("prepare") => prepare(&program, &cut, &mut result)?,
                None => attach_revision(&cut, &mut result)?,
                _ => {}
            }
            if let Some(item) = attempt.as_ref().filter(|_| command == Some("apply")) {
                result["receipt"] = apply(&program, &cut, &result, item)?;
            }
            Ok(CommitOutcome::Accepted(result))
        })())
    })?
}
