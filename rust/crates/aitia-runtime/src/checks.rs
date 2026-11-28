// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Recorded project verification, assurance replay, and Quint verification runners.

use crate::project::{
    CHECK_ASSURANCE_REPLAY, CHECK_SYSML_PARSE, ReplayPlan, resolve_recorded_project,
};
use crate::{AitiaProgram, HostCapabilityRegistry, HostEffectClass};
use aitia_jj::WorkspaceCut;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::path::Path;
use std::process::{Command, Stdio};

pub(crate) fn check_recorded_project(
    program: &AitiaProgram<'_>,
) -> Result<(serde_json::Value, bool), Box<dyn std::error::Error>> {
    let (cut, configuration) = resolve_recorded_project(program, Path::new("."))?;
    let unsupported: Vec<String> = configuration
        .unsupported_checks()
        .into_iter()
        .map(str::to_owned)
        .collect();
    let sysml = if configuration.has_check(CHECK_SYSML_PARSE) {
        HostCapabilityRegistry::default_linked().dispatch_json(
            "sysml.parse-workspace",
            HostEffectClass::HostRead,
            &serde_json::json!({
                "directory": cut.workspace_root().to_string_lossy(),
                "mode": "check",
                "enabled": true,
            }),
            None,
        )?
    } else {
        serde_json::Value::Null
    };
    let mut checks = serde_json::json!({ "sysml": sysml });
    let mut matched = unsupported.is_empty();
    if !unsupported.is_empty() {
        checks["unsupported"] = serde_json::json!(unsupported);
    }
    if configuration.has_check(CHECK_ASSURANCE_REPLAY) {
        let plan = configuration
            .replay
            .ok_or_else(|| io::Error::other("Missing replay plan"))?;
        let (report, replay_matched) = check_assurance_replay(program, &cut, &plan)?;
        checks["assurance"] = report;
        matched &= replay_matched;
    }
    Ok((serde_json::json!({ "cut": cut, "checks": checks }), matched))
}

fn check_assurance_replay(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    plan: &ReplayPlan,
) -> Result<(serde_json::Value, bool), Box<dyn std::error::Error>> {
    let interpreter = std::env::var_os("AITIA_PYTEST_PYTHON").ok_or_else(|| {
        io::Error::other("Set AITIA_PYTEST_PYTHON to an absolute Python interpreter with pytest")
    })?;
    let paths: Vec<_> = plan.paths.iter().map(String::as_str).collect();
    let mut results = Vec::with_capacity(plan.cases.len());
    let mut matched = true;
    for case in &plan.cases {
        let run = crate::run_recorded_pytest(
            Path::new(&interpreter),
            &plan.project,
            cut.clone(),
            &paths,
            &[&case.selector],
        )?;
        let assessment = program.assess_pytest_replay(
            crate::ReplayAssessmentScope {
                project: &plan.project,
                workspace: cut.workspace_root(),
                obligation: &case.obligation,
                selector: &case.selector,
                deployment_profile: Some(&plan.profile),
            },
            None,
            &run,
        )?;
        let field = match case.expected.as_str() {
            "passed" => "supported",
            "failed" => "contradicted",
            _ => return Err(io::Error::other("Unknown expected replay outcome").into()),
        };
        let case_matched = assessment.as_ref().is_some_and(|value| {
            value["revision"] == cut.commit_id()
                && value[field].as_array().is_some_and(|rows| {
                    rows.iter().any(|row| {
                        row.get(1).and_then(serde_json::Value::as_str) == Some(&case.obligation)
                    })
                })
        });
        matched &= case_matched;
        results.push(serde_json::json!({
            "obligation": case.obligation,
            "expected": case.expected,
            "matched": case_matched,
            "assessment": assessment,
        }));
    }
    Ok((
        serde_json::json!({ "profile": plan.profile, "cases": results }),
        matched,
    ))
}

pub(crate) struct QuintCheckOutcome {
    pub(crate) observation: serde_json::Value,
    pub(crate) source_unchanged: bool,
    pub(crate) status: std::process::ExitStatus,
}

pub(crate) fn run_quint_check(
    driver: &OsStr,
    quint: &OsStr,
    model: &OsStr,
) -> Result<QuintCheckOutcome, Box<dyn std::error::Error>> {
    let driver = fs::canonicalize(driver)?;
    let quint = fs::canonicalize(quint)?;
    let model = fs::canonicalize(model)?;
    let driver_before = crate::source_tree::sha256(&fs::read(&driver)?);
    let model_before = crate::source_tree::sha256(&fs::read(&model)?);
    let status = Command::new("timeout")
        .args(["--signal=TERM", "--kill-after=3s", "60s", "node"])
        .arg(&driver)
        .arg(&quint)
        .arg(&model)
        .stdin(Stdio::null())
        .status()?;
    let driver_after = crate::source_tree::sha256(&fs::read(&driver)?);
    let model_after = crate::source_tree::sha256(&fs::read(&model)?);
    let source_unchanged = driver_before == driver_after && model_before == model_after;
    let verdict = if !source_unchanged {
        "source-mutated"
    } else if status.success() {
        "passed"
    } else {
        "failed"
    };
    let observation = serde_json::json!({
        "schema": "lambda-aitia.execution-observation.v1",
        "tool": "quint",
        "driverSha256": driver_before,
        "modelPath": model,
        "modelSha256": model_before,
        "sourceUnchanged": source_unchanged,
        "exitCode": status.code(),
        "verdict": verdict,
        "releaseAuthorized": false,
    });
    Ok(QuintCheckOutcome {
        observation,
        source_unchanged,
        status,
    })
}
