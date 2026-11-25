// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin `aitia flow` CLI adapter implementing the generic Scheme-driven
//! 4-state inversion-of-control loop over [`crate::HostCapabilityRegistry`].

use crate::{
    AitiaProgram, HostCapabilityRegistry, HostEffectClass, MAX_REQUEST_BYTES, cli,
    with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use std::io::{self, Write};
use std::path::Path;

const MAX_PROTOCOL_ROUNDS: usize = 8;
const USAGE: &str = "usage: aitia flow capabilities\n       aitia flow reconcile < request.json\n       aitia flow run [--case <id>] [--proposal-stdin]\n       aitia flow gitops [--proposal-stdin]\n       aitia flow submit-patch < proposal.json";

pub(super) fn run_flow(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    match operation {
        ["--help" | "-h"] => writeln!(io::stdout().lock(), "{USAGE}").map_err(Into::into),
        ["capabilities"] => print_capabilities(),
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
            let step = execute_project_protocol("aitia/case/gitops-commit", overlay.as_ref())?;
            print_json(&step["reconciliation"])
        }
        ["submit-patch"] => {
            let overlay = serde_json::json!({ "proposal": read_json_stdin()?, "reconcile": false });
            let step = execute_project_protocol("aitia/case/gitops-commit", Some(&overlay))?;
            print_json(&step["reconciliation"])
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
        [] => ("aitia/case/gitops-commit", false),
        ["--proposal-stdin"] => ("aitia/case/gitops-commit", true),
        ["--case", id] => (*id, false),
        ["--case", id, "--proposal-stdin"] | ["--proposal-stdin", "--case", id] => (*id, true),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    Ok((case_id, read_stdin.then(read_json_stdin).transpose()?))
}

fn print_capabilities() -> Result<(), Box<dyn std::error::Error>> {
    let descriptors: Vec<serde_json::Value> = HostCapabilityRegistry::default_linked()
        .descriptors()
        .into_iter()
        .map(|(capability, effect_class)| {
            let effect = match effect_class {
                HostEffectClass::HostRead => "host-read",
                HostEffectClass::FencedEffect => "fenced-effect",
            };
            serde_json::json!({ "capability": capability, "effectClass": effect })
        })
        .collect();
    print_json(&serde_json::json!({
        "schema": "lambda-aitia.host-capabilities.v1",
        "capabilities": descriptors,
        "actionAuthorized": false,
    }))
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
    let source = cli::recorded_configuration_input(&project_sources)?;
    let (_, projection) = program.resolve_project_config(&source)?;
    let configuration = cli::decode_configuration_projection(&projection)?;
    let policy = configuration
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile in the recorded project"))?;
    let project = policy["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("No recorded commit project"))?;
    let mut state = serde_json::json!({
        "caseId": case_id,
        "project": project,
        "directory": cut.workspace_root().to_string_lossy().into_owned(),
        "requestedPaths": cli::review_source_paths(policy)?,
        "modelCheckEnabled": configuration.model_check_enabled(),
        "naming": policy["naming"],
        "receipts": {},
        "proposals": [],
        "observations": [],
        "approvalLive": false,
        "reconcile": true,
    });
    if let Some(extra) = overlay {
        for field in [
            "proposals",
            "proposal",
            "observations",
            "approvalLive",
            "reconcile",
            "includePrObservation",
        ] {
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
        let receipts = registry.dispatch_protocol_frames(raw_frames)?;
        let map = state["receipts"]
            .as_object_mut()
            .ok_or_else(|| io::Error::other("protocol receipts must be an object"))?;
        for (key, payload) in receipts {
            map.insert(key, payload);
        }
    }
    Err(io::Error::other("workflow protocol exceeded host frame round budget").into())
}
