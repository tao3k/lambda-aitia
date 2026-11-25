// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin `aitia flow` CLI adapter delegating host observations to
//! [`crate::HostCapabilityRegistry`] and passing raw receipts to Scheme.

use crate::{
    AitiaProgram, CapabilityFrame, CapabilityId, HostCapabilityRegistry, HostEffectClass,
    MAX_REQUEST_BYTES, cli, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use std::{
    io::{self, Write},
    path::Path,
};

pub(super) fn run_flow(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    const USAGE: &str = "usage: aitia flow capabilities\n       aitia flow reconcile < request.json\n       aitia flow gitops [--proposal-stdin]\n       aitia flow submit-patch < proposal.json";
    match operation {
        ["--help" | "-h"] => {
            writeln!(io::stdout().lock(), "{USAGE}")?;
            Ok(())
        }
        ["capabilities"] => {
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
            writeln!(
                io::stdout().lock(),
                "{}",
                serde_json::to_string(&serde_json::json!({
                    "schema": "lambda-aitia.host-capabilities.v1",
                    "capabilities": descriptors,
                    "actionAuthorized": false,
                }))?
            )?;
            Ok(())
        }
        ["reconcile"] => {
            let request = cli::read_request()?;
            let response = with_linked_program(|program| program.workflow_reconcile(&request))?;
            writeln!(io::stdout().lock(), "{response}")?;
            Ok(())
        }
        ["gitops"] | ["gitops", "--proposal-stdin"] => {
            let overlay: Option<serde_json::Value> = if operation.len() == 2 {
                Some(serde_json::from_str(&cli::read_request()?)?)
            } else {
                None
            };
            let observed =
                observe_project_sources(Path::new("."), usize::try_from(MAX_REQUEST_BYTES)?)?;
            let response = with_linked_program(|program| {
                Ok(reconcile_recorded_gitops_flow(
                    &program,
                    observed,
                    overlay.as_ref(),
                ))
            })??;
            writeln!(io::stdout().lock(), "{response}")?;
            Ok(())
        }
        ["submit-patch"] => {
            let proposal: serde_json::Value = serde_json::from_str(&cli::read_request()?)?;
            let overlay = serde_json::json!({ "proposal": proposal, "reconcile": false });
            let observed =
                observe_project_sources(Path::new("."), usize::try_from(MAX_REQUEST_BYTES)?)?;
            let response = with_linked_program(|program| {
                Ok(reconcile_recorded_gitops_flow(
                    &program,
                    observed,
                    Some(&overlay),
                ))
            })??;
            writeln!(io::stdout().lock(), "{response}")?;
            Ok(())
        }
        _ => Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    }
}

fn reconcile_recorded_gitops_flow(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    overlay: Option<&serde_json::Value>,
) -> Result<String, Box<dyn std::error::Error>> {
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
    let requested_paths = cli::review_source_paths(policy)?;
    let directory = cut.workspace_root().to_string_lossy().into_owned();
    let registry = HostCapabilityRegistry::default_linked();
    let receipts = registry.dispatch_batch(&[
        CapabilityFrame {
            capability: CapabilityId::new("gitops.jj.observe-cut"),
            effect_class: HostEffectClass::HostRead,
            payload: serde_json::json!({
                "directory": directory,
                "requestedPaths": requested_paths,
            })
            .to_string(),
            fence_token: None,
        },
        CapabilityFrame {
            capability: CapabilityId::new("sysml.project-scopes"),
            effect_class: HostEffectClass::HostRead,
            payload: serde_json::json!({
                "directory": directory,
                "enabled": configuration.model_check_enabled(),
            })
            .to_string(),
            fence_token: None,
        },
    ])?;
    let jj_obs: serde_json::Value = serde_json::from_str(&receipts[0].payload)?;
    let sysml_scopes: serde_json::Value = serde_json::from_str(&receipts[1].payload)?;
    let mut request = serde_json::json!({
        "project": project,
        "cut": jj_obs["cut"],
        "naming": policy["naming"],
        "sysmlScopes": sysml_scopes,
        "sources": jj_obs["sources"],
        "paths": jj_obs["paths"],
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
        ] {
            if let Some(value) = extra.get(field) {
                request[field] = value.clone();
            }
        }
    }
    let payload = serde_json::to_string(&request)?;
    Ok(program.workflow_reconcile(&payload)?)
}
