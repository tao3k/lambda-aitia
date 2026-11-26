// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin `aitia flow` CLI adapter implementing the generic Scheme-driven
//! 4-state inversion-of-control loop over [`crate::HostCapabilityRegistry`].

use crate::{AitiaProgram, HostCapabilityRegistry, MAX_REQUEST_BYTES, cli, with_linked_program};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use std::io::{self, Write};
use std::path::Path;

const MAX_PROTOCOL_ROUNDS: usize = 8;
const DEFAULT_CASE: &str = "aitia/case/gitops-commit";
const USAGE: &str = "usage: aitia flow capabilities\n       aitia flow reconcile < request.json\n       aitia flow run [--case <id>] [--proposal-stdin]\n       aitia flow gitops [--proposal-stdin]\n       aitia flow submit-patch < proposal.json\n       aitia flow submit-decision < decision.json";

pub(super) fn run_flow(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    match operation {
        ["--help" | "-h"] => writeln!(io::stdout().lock(), "{USAGE}").map_err(Into::into),
        ["capabilities"] => {
            print_json(&HostCapabilityRegistry::default_linked().descriptors_json())
        }
        ["reconcile"] => {
            let request = cli::read_request()?;
            let response = with_linked_program(|program| program.workflow_reconcile(&request))?;
            writeln!(io::stdout().lock(), "{response}").map_err(Into::into)
        }
        ["run", rest @ ..] => {
            let (case_id, overlay) = parse_run_args(rest)?;
            print_json(&execute_project_protocol(case_id, overlay.as_ref())?)
        }
        ["gitops"] | ["gitops", "--proposal-stdin"] => {
            let overlay = (operation.len() == 2).then(read_json_stdin).transpose()?;
            print_json(&execute_project_protocol(DEFAULT_CASE, overlay.as_ref())?["reconciliation"])
        }
        ["submit-patch"] => {
            let overlay = serde_json::json!({ "proposal": read_json_stdin()?, "reconcile": false });
            print_json(&execute_project_protocol(DEFAULT_CASE, Some(&overlay))?["reconciliation"])
        }
        ["submit-decision"] => {
            let mut decision = read_json_stdin()?;
            let obj = decision.as_object_mut().ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidInput, "expected JSON object")
            })?;
            if let Some(approved) = obj.remove("approved") {
                obj.entry("approvalLive").or_insert(approved);
            }
            print_json(&execute_project_protocol(DEFAULT_CASE, Some(&decision))?)
        }
        _ => Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    }
}

fn read_json_stdin() -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    Ok(serde_json::from_str(&cli::read_request()?)?)
}

fn print_json(value: &serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
    writeln!(io::stdout().lock(), "{}", serde_json::to_string(value)?).map_err(Into::into)
}

fn parse_run_args<'a>(
    rest: &'a [&'a str],
) -> Result<(&'a str, Option<serde_json::Value>), Box<dyn std::error::Error>> {
    let (case_id, read_stdin) = match rest {
        [] => (DEFAULT_CASE, false),
        ["--proposal-stdin"] => (DEFAULT_CASE, true),
        ["--case", id] => (*id, false),
        ["--case", id, "--proposal-stdin"] | ["--proposal-stdin", "--case", id] => (*id, true),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    Ok((case_id, read_stdin.then(read_json_stdin).transpose()?))
}

fn execute_project_protocol(
    case_id: &str,
    overlay: Option<&serde_json::Value>,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let observed = observe_project_sources(Path::new("."), usize::try_from(MAX_REQUEST_BYTES)?)?;
    with_linked_program(|program| Ok(drive_scheme_protocol(&program, observed, case_id, overlay)))?
}

fn drive_scheme_protocol(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&serde_json::Value>,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let (cut, project_sources) = observed;
    let (_, projection) =
        program.resolve_project_config(&cli::recorded_configuration_input(&project_sources)?)?;
    let cfg = cli::decode_configuration_projection(&projection)?;
    let policy = cfg
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile"))?;
    let project = policy["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("No commit project"))?;
    let mut state = serde_json::json!({
        "caseId": case_id, "project": project,
        "directory": cut.workspace_root().to_string_lossy().into_owned(),
        "requestedPaths": cli::review_source_paths(policy)?,
        "modelCheckEnabled": cfg.model_check_enabled(),
        "naming": policy["naming"], "receipts": {},
        "proposals": [], "observations": [], "approvalLive": false, "reconcile": true,
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
