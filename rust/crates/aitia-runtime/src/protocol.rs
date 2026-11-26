// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Generic Scheme-driven 5-state Mixed-Initiative inversion-of-control protocol
//! driver over [`crate::HostCapabilityRegistry`].

use crate::{
    AitiaProgram, HostCapabilityRegistry, MAX_REQUEST_BYTES, commit, project, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use serde_json::{Value, json};
use std::io;
use std::path::Path;

const MAX_PROTOCOL_ROUNDS: usize = 8;

/// Default Scheme workflow case identifier for GitOps commit reconciliation.
pub const DEFAULT_WORKFLOW_CASE: &str = "aitia/case/gitops-commit";

/// Execute the Scheme-driven 5-state workflow protocol (planning / read-only probes only).
///
/// # Errors
/// Returns an error if workspace observation, Scheme configuration projection,
/// capability dispatch, or the protocol round budget fails.
pub fn execute_project_protocol(
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    execute_project_protocol_inner(case_id, overlay, false)
}

/// Execute the Scheme-driven 5-state workflow protocol with explicit opt-in fenced execution.
///
/// Any `FencedEffect` frame is only dispatched after Scheme's own `commit_review_report`
/// verifies the caller-supplied reviewed `draft` against the exact current JJ cut, and
/// every mutation goes strictly through [`HostCapabilityRegistry::dispatch_protocol_frames`].
///
/// # Errors
/// Fails closed if the reviewed draft is missing/invalid, governance requires signed
/// approvals, fenced dispatch fails, or post-apply evidence verification fails.
pub fn execute_project_protocol_fenced(
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    execute_project_protocol_inner(case_id, overlay, true)
}

fn execute_project_protocol_inner(
    case_id: &str,
    overlay: Option<&Value>,
    execute_fenced: bool,
) -> Result<Value, Box<dyn std::error::Error>> {
    let observed = observe_project_sources(Path::new("."), usize::try_from(MAX_REQUEST_BYTES)?)?;
    with_linked_program(|program| {
        let outcome = (|| -> Result<Value, Box<dyn std::error::Error>> {
            let (mut result, archived_review) =
                drive_scheme_protocol_inner(&program, observed, case_id, overlay, execute_fenced)?;
            if execute_fenced
                && result["state"].as_str() == Some("quiescent")
                && let (Some(mut archive), Some(receipt)) = (
                    archived_review,
                    result.get("appliedReceipt").filter(|v| !v.is_null()),
                )
            {
                let revision = receipt["resulting_commit"]
                    .as_str()
                    .ok_or_else(|| {
                        io::Error::other("Applied commit receipt missing resulting_commit")
                    })?
                    .to_owned();
                archive["receipt"] = receipt.clone();
                let evidence = commit::evidence_with_program(
                    &program,
                    &revision,
                    &serde_json::to_string(&archive)?,
                    true,
                )?;
                result["evidenceLineage"] = evidence;
            }
            Ok(result)
        })();
        Ok(outcome)
    })?
}

/// Drive the 5-state Scheme protocol loop (read-only probes only) for an already-initialized [`AitiaProgram`].
///
/// # Errors
/// Fails closed if project configuration projection, Scheme step evaluation,
/// host frame dispatch, or the round budget fails.
pub fn drive_scheme_protocol(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    let (step, _) = drive_scheme_protocol_inner(program, observed, case_id, overlay, false)?;
    Ok(step)
}

fn verify_fenced_commit_draft(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    overlay: Option<&Value>,
) -> Result<(WorkspaceCut, Value, Value, Value), Box<dyn std::error::Error>> {
    let extra = overlay.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Fenced execution requires a JSON decision payload with a reviewed `draft`",
        )
    })?;
    if extra.get("approvalLive").and_then(Value::as_bool) != Some(true) {
        return Err(io::Error::other("Fenced execution requires `approvalLive: true`").into());
    }
    let raw_draft = extra.get("draft").ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Fenced execution requires a reviewed `draft` object",
        )
    })?;
    let draft: commit::CommitNarration = serde_json::from_value(raw_draft.clone())?;
    let (cut, review_report, _) =
        commit::commit_review_report(program, observed, Some(&draft), None, false)?;
    if review_report["policy"]["governance"] != "default" {
        return Err(io::Error::other(
            "Signed governance projects require explicit signed approval via `aitia jj commit`",
        )
        .into());
    }
    let description = review_report["review"]["description"]
        .as_str()
        .ok_or_else(|| {
            io::Error::other("Commit draft lacks current admitted support or violates its Contract")
        })?;
    let review_context = review_report["review"]["context"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing verified commit review context"))?;
    let binding = commit::proposal_binding(&draft.proposal)?;
    let fenced_spec = json!({
        "expectedCommit": cut.commit_id(),
        "expectedOperation": cut.operation_id(),
        "description": description,
        "reviewContext": review_context,
        "proposalBinding": binding,
    });
    let proposal_json = serde_json::to_value(&draft.proposal)?;
    Ok((cut, fenced_spec, proposal_json, review_report))
}

fn drive_scheme_protocol_inner(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&Value>,
    execute_fenced: bool,
) -> Result<(Value, Option<Value>), Box<dyn std::error::Error>> {
    let (_, projection) =
        program.resolve_project_config(&project::recorded_configuration_input(&observed.1)?)?;
    let cfg = project::decode_configuration_projection(&projection)?;
    let (cut, verified_fenced) = if execute_fenced {
        let (cut, fenced_spec, proposal_json, review_report) =
            verify_fenced_commit_draft(program, observed, overlay)?;
        (cut, Some((fenced_spec, proposal_json, review_report)))
    } else {
        (observed.0, None)
    };
    let policy = cfg
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile"))?;
    let project = policy["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("No commit project"))?;
    let mut state = json!({
        "caseId": case_id,
        "project": project,
        "profile": policy["profile"],
        "checks": policy["checks"],
        "directory": cut.workspace_root().to_string_lossy().into_owned(),
        "requestedPaths": project::review_source_paths(policy)?,
        "modelCheckEnabled": cfg.model_check_enabled(),
        "naming": policy["naming"],
        "receipts": {},
        "proposals": [],
        "observations": [],
        "approvalLive": false,
        "reconcile": true,
    });
    const OVERLAY_FIELDS: &[&str] = &[
        "proposals",
        "proposal",
        "observations",
        "approvalLive",
        "reconcile",
        "includePrObservation",
        "forbiddenScopes",
        "candidateOffers",
    ];
    if let Some(extra) = overlay {
        for &field in OVERLAY_FIELDS {
            if let Some(value) = extra.get(field) {
                state[field] = value.clone();
            }
        }
    }
    let mut archived_review = None;
    if let Some((fenced_spec, proposal_json, review_report)) = verified_fenced {
        state["fencedCommitSpec"] = fenced_spec;
        if state["proposals"]
            .as_array()
            .is_none_or(|rows| rows.is_empty())
        {
            state["proposals"] = json!([proposal_json]);
        }
        state["reconcile"] = json!(false);
        archived_review = Some(review_report);
    }
    let registry = HostCapabilityRegistry::default_linked();
    for _ in 0..MAX_PROTOCOL_ROUNDS {
        let req = serde_json::to_string(&state)?;
        let step: Value = serde_json::from_str(&program.workflow_protocol_step(&req)?)?;
        let state_name = step["state"].as_str();
        let should_dispatch = state_name == Some("need-host-frames")
            || (execute_fenced && state_name == Some("need-fenced-frames"));
        if !should_dispatch {
            return Ok((step, archived_review));
        }
        let raw_frames = step["frames"]
            .as_array()
            .ok_or_else(|| io::Error::other("Scheme protocol step missing frames array"))?;
        let map = state["receipts"]
            .as_object_mut()
            .ok_or_else(|| io::Error::other("protocol receipts must be an object"))?;
        for (key, payload) in registry.dispatch_protocol_frames(raw_frames)? {
            map.insert(key, payload);
        }
        if state["receipts"]
            .get("gitops.jj.apply-description")
            .is_some()
        {
            state["reconcile"] = json!(true);
        }
    }
    Err(io::Error::other("workflow protocol exceeded host frame round budget").into())
}
