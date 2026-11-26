// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Generic Scheme-driven 4-state inversion-of-control protocol driver over
//! [`crate::HostCapabilityRegistry`].

use crate::{
    AitiaProgram, HostCapabilityRegistry, MAX_REQUEST_BYTES, project, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use std::io;
use std::path::Path;

const MAX_PROTOCOL_ROUNDS: usize = 8;

/// Default Scheme workflow case identifier for GitOps commit reconciliation.
pub const DEFAULT_WORKFLOW_CASE: &str = "aitia/case/gitops-commit";

/// Execute the Scheme-driven 4-state workflow protocol against the current workspace.
///
/// # Errors
/// Returns an error if workspace observation, Scheme configuration projection,
/// capability dispatch, or the protocol round budget fails.
pub fn execute_project_protocol(
    case_id: &str,
    overlay: Option<&serde_json::Value>,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let observed = observe_project_sources(Path::new("."), usize::try_from(MAX_REQUEST_BYTES)?)?;
    with_linked_program(|program| Ok(drive_scheme_protocol(&program, observed, case_id, overlay)))?
}

/// Drive the 4-state Scheme protocol loop for an already-initialized [`AitiaProgram`].
///
/// # Errors
/// Fails closed if project configuration projection, Scheme step evaluation,
/// host frame dispatch, or the round budget fails.
pub fn drive_scheme_protocol(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&serde_json::Value>,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let (cut, project_sources) = observed;
    let (_, projection) = program
        .resolve_project_config(&project::recorded_configuration_input(&project_sources)?)?;
    let cfg = project::decode_configuration_projection(&projection)?;
    let policy = cfg
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile"))?;
    let project = policy["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("No commit project"))?;
    let mut state = serde_json::json!({
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
    let registry = HostCapabilityRegistry::default_linked();
    for _ in 0..MAX_PROTOCOL_ROUNDS {
        let req = serde_json::to_string(&state)?;
        let step: serde_json::Value = serde_json::from_str(&program.workflow_protocol_step(&req)?)?;
        if step["state"].as_str() != Some("need-host-frames") {
            return Ok(step);
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
    }
    Err(io::Error::other("workflow protocol exceeded host frame round budget").into())
}
