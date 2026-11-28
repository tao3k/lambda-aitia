// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Frozen-snapshot Python verification leaf host capability for Scheme FunFlow DAGs.

use super::{
    CapabilityError, CapabilityFrame, HostCapability, HostCapabilityRegistry, HostEffectClass,
    HostReceipt,
};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

pub(super) fn register(registry: &mut HostCapabilityRegistry) {
    registry.register(Box::new(PythonObservePytestCapability));
}

struct PythonObservePytestCapability;

impl HostCapability for PythonObservePytestCapability {
    fn capability_id(&self) -> &'static str {
        "python.observe-pytest"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        #[cfg(unix)]
        {
            let request: Value = serde_json::from_str(&frame.payload)
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
            let directory = request["directory"].as_str().unwrap_or(".");
            let interpreter = resolve_interpreter(request["interpreter"].as_str());
            let selectors = string_vec(&request["selectors"]);
            let paths = string_vec(&request["paths"]);
            let project = request["project"].as_str().unwrap_or("workspace");
            let receipt = observe_pytest_json(
                Path::new(directory),
                &interpreter,
                project,
                &paths,
                &selectors,
            )?;
            let payload = serde_json::to_string(&receipt)
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
            Ok(HostReceipt::observe(
                self.capability_id(),
                self.effect_class(),
                payload,
            ))
        }
        #[cfg(not(unix))]
        {
            let _ = frame;
            Err(CapabilityError::Execution(
                "python.observe-pytest requires a unix host".to_owned(),
            ))
        }
    }
}

#[cfg(unix)]
fn resolve_interpreter(explicit: Option<&str>) -> PathBuf {
    if let Some(path) = explicit.filter(|p| !p.trim().is_empty()) {
        return PathBuf::from(path);
    }
    if let Ok(env_py) = std::env::var("AITIA_PYTEST_PYTHON")
        && !env_py.trim().is_empty()
    {
        return PathBuf::from(env_py);
    }
    PathBuf::from("python3")
}

#[cfg(unix)]
fn string_vec(value: &Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(unix)]
fn observe_pytest_json(
    directory: &Path,
    interpreter: &Path,
    project: &str,
    paths: &[String],
    selectors: &[String],
) -> Result<Value, CapabilityError> {
    let selector_refs: Vec<&str> = selectors.iter().map(String::as_str).collect();
    let run = if !paths.is_empty() && directory.join(".jj").exists() {
        let cut = aitia_jj::observe_workspace(directory)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let path_refs: Vec<&str> = paths.iter().map(String::as_str).collect();
        let recorded =
            crate::run_recorded_pytest(interpreter, project, cut, &path_refs, &selector_refs)
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let obs = recorded.observation();
        format_pytest_run(obs)
    } else {
        let frozen = crate::capture_source_tree(directory)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let obs = crate::run_frozen_pytest(interpreter, &frozen, &selector_refs)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        format_pytest_run(&obs)
    };
    Ok(run)
}

#[cfg(unix)]
fn format_pytest_run(obs: &crate::PytestRun) -> Value {
    let report = obs.report.as_ref().map(|r| {
        json!({
            "sha256": r.sha256,
            "passed": r.passed,
            "failed": r.failed,
            "errors": r.errors,
            "skipped": r.skipped,
        })
    });
    json!({
        "verdict": obs.verdict().as_str(),
        "sourceUnchanged": obs.source_unchanged,
        "sourceSha256": obs.source_sha256,
        "observedSourceSha256": obs.observed_source_sha256,
        "selectors": obs.selectors,
        "report": report,
        "actionAuthorized": false,
    })
}
