// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin `aitia flow` CLI adapter delegating host observations to
//! [`crate::HostCapabilityRegistry`] and passing raw receipts to Scheme.

use crate::{
    AitiaProgram, CapabilityFrame, CapabilityId, HostCapabilityRegistry, HostEffectClass,
    MAX_REQUEST_BYTES, cli, cli_commit, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources, observe_recorded_sources, recorded_changes};
use std::{
    io::{self, Write},
    path::Path,
};

pub(super) fn run_flow(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    const USAGE: &str =
        "usage: aitia flow reconcile < request.json\n       aitia flow gitops [--proposal-stdin]";
    match operation {
        ["--help" | "-h"] => {
            writeln!(io::stdout().lock(), "{USAGE}")?;
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
    let changes = recorded_changes(&cut)?;
    let requested_paths = cli::review_source_paths(policy)?;
    let mut sources = Vec::new();
    for (path, result) in
        observe_recorded_sources(&cut, &requested_paths, usize::try_from(MAX_REQUEST_BYTES)?)?
    {
        if let Ok(text) = result {
            sources.push(serde_json::json!({"path": path, "text": text}));
        }
    }
    let paths: Vec<&str> = changes.iter().map(|change| change.path.as_str()).collect();
    let registry = HostCapabilityRegistry::default_linked();
    let scope_receipt = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("sysml.project-scopes"),
        effect_class: HostEffectClass::HostRead,
        payload: serde_json::json!({
            "directory": cut.workspace_root().to_string_lossy(),
            "enabled": configuration.model_check_enabled(),
        })
        .to_string(),
        fence_token: None,
    })?;
    let sysml_scopes: serde_json::Value = serde_json::from_str(&scope_receipt.payload)?;
    let mut request = serde_json::json!({
        "project": project,
        "cut": cli_commit::review_cut_value(&cut),
        "naming": policy["naming"],
        "sysmlScopes": sysml_scopes,
        "sources": sources,
        "paths": paths,
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

#[cfg(feature = "sysml")]
pub(super) fn observe_commit_sysml_and_scopes(
    cut: &WorkspaceCut,
    affected_paths: &[String],
    enabled: bool,
) -> (Option<serde_json::Value>, Vec<serde_json::Value>) {
    if !enabled {
        return (None, Vec::new());
    }
    let (model, scopes) = crate::sysml::observe_commit_sysml_and_scopes(cut, affected_paths);
    let projected = scopes
        .into_iter()
        .map(|scope| {
            serde_json::json!({
                "name": scope.name,
                "paths": scope.paths,
                "elementId": scope.element_id,
            })
        })
        .collect();
    (model, projected)
}

#[cfg(not(feature = "sysml"))]
pub(super) fn observe_commit_sysml_and_scopes(
    cut: &WorkspaceCut,
    affected_paths: &[String],
    enabled: bool,
) -> (Option<serde_json::Value>, Vec<serde_json::Value>) {
    if !enabled {
        return (None, Vec::new());
    }
    let model =
        (!affected_paths.is_empty()).then(|| cli::observe_commit_sysml(cut, affected_paths));
    (model, Vec::new())
}
