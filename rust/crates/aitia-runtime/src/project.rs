// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Project manifest validation, Scheme configuration projection, and project initialization.

use crate::{AitiaProgram, MAX_REQUEST_BYTES, with_linked_program};
use aitia_jj::{
    WorkspaceCut, git_project_root, observe_project_sources, observe_workspace,
    recorded_sysml_paths,
};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;

pub(crate) const CHECK_SYSML_PARSE: &str = "sysml.parse";
pub(crate) const CHECK_ASSURANCE_REPLAY: &str = "assurance.replay";

#[derive(serde::Deserialize)]
pub(crate) struct ProjectConfiguration {
    pub(crate) manifest: serde_json::Value,
    checks: Vec<String>,
    pub(crate) replay: Option<ReplayPlan>,
    pub(crate) commit: Option<serde_json::Value>,
}

impl ProjectConfiguration {
    pub(crate) fn has_check(&self, check_id: &str) -> bool {
        self.checks.iter().any(|check| check == check_id)
    }

    pub(crate) fn model_check_enabled(&self) -> bool {
        self.has_check(CHECK_SYSML_PARSE)
    }

    pub(crate) fn unsupported_checks(&self) -> Vec<&str> {
        self.checks
            .iter()
            .map(String::as_str)
            .filter(|check| !matches!(*check, CHECK_SYSML_PARSE | CHECK_ASSURANCE_REPLAY))
            .collect()
    }
}

#[derive(serde::Deserialize)]
pub(crate) struct ReplayPlan {
    pub(crate) project: String,
    pub(crate) profile: String,
    pub(crate) paths: Vec<String>,
    pub(crate) cases: Vec<ReplayCase>,
}

#[derive(serde::Deserialize)]
pub(crate) struct ReplayCase {
    pub(crate) obligation: String,
    pub(crate) selector: String,
    pub(crate) expected: String,
}

pub(crate) fn project_manifest_receipt(
    directory: &Path,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let (cut, configuration) = recorded_project(directory)?;
    let sysml = if configuration.has_check(CHECK_SYSML_PARSE) {
        recorded_sysml_paths(&cut)?
    } else {
        Vec::new()
    };
    Ok(serde_json::json!({
        "cut": cut,
        "manifest": configuration.manifest,
        "inputs": { "sysml": sysml },
    }))
}

pub(crate) fn recorded_project(
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    let (cut, sources) = observe_project_sources(directory, MAX_REQUEST_BYTES as usize)?;
    let config = with_linked_program(|program| Ok(validate_project_manifest(&program, &sources)))??;
    if observe_workspace(cut.workspace_root())? != cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    Ok((cut, config))
}

pub(crate) fn resolve_recorded_project(
    program: &AitiaProgram<'_>,
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    let (cut, source) = observe_project_sources(directory, MAX_REQUEST_BYTES as usize)?;
    Ok((cut, validate_project_manifest(program, &source)?))
}

pub(crate) fn validate_project_manifest(
    program: &AitiaProgram<'_>,
    sources: &aitia_jj::RecordedProjectSources,
) -> Result<ProjectConfiguration, Box<dyn std::error::Error>> {
    decode_configuration_projection(
        &program.project_config_validate(&recorded_configuration_input(sources)?)?,
    )
}

pub(crate) fn recorded_configuration_input(
    sources: &aitia_jj::RecordedProjectSources,
) -> Result<String, Box<dyn std::error::Error>> {
    let source = serde_json::to_string(sources)?;
    if source.len() > MAX_REQUEST_BYTES as usize {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "AITIA request exceeds 4 MiB").into(),
        );
    }
    Ok(source)
}

pub(crate) fn decode_configuration_projection(
    effective: &str,
) -> Result<ProjectConfiguration, Box<dyn std::error::Error>> {
    if effective == "false" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AITIA project manifest fails its envelope Contract",
        )
        .into());
    }
    Ok(serde_json::from_str(effective)?)
}

pub(crate) fn review_source_paths(policy: &serde_json::Value) -> Result<Vec<&str>, io::Error> {
    let references = policy["naming"]["references"]
        .as_array()
        .ok_or_else(|| io::Error::other("Invalid Scheme engineering reference projection"))?;
    let mut observed_paths = std::collections::BTreeSet::new();
    let language_sources = policy["naming"]["languageSources"]
        .as_array()
        .ok_or_else(|| io::Error::other("Invalid Scheme project language sources"))?;
    let paths = references
        .iter()
        .map(|reference| &reference["source"])
        .chain(language_sources.iter());
    let mut requested_paths = Vec::new();
    for source_path in paths {
        let path = source_path
            .as_str()
            .ok_or_else(|| io::Error::other("Invalid Scheme source path"))?;
        // JJ admits only regular files in this recorded tree. No workspace or
        // Agent-supplied document can replace a missing reference observation.
        if observed_paths.insert(path) {
            requested_paths.push(path);
        }
    }
    Ok(requested_paths)
}

pub(crate) fn commit_checks(policy: &serde_json::Value) -> Result<&[serde_json::Value], io::Error> {
    policy["checks"]
        .as_array()
        .map(Vec::as_slice)
        .ok_or_else(|| io::Error::other("Invalid Scheme commit policy projection"))
}

pub(crate) fn affected_sysml_paths(changes: &[aitia_jj::RecordedPathChange]) -> Vec<String> {
    changes
        .iter()
        .filter(|change| change.path.ends_with(".sysml"))
        .map(|change| change.path.clone())
        .collect()
}

pub(crate) fn init_project(directory: &Path) -> Result<&'static str, Box<dyn std::error::Error>> {
    let root = git_project_root(directory)?;
    let mut config = root;
    for component in [".agents", "aita"] {
        config.push(component);
        match fs::create_dir(&config) {
            Ok(()) => {}
            Err(error)
                if error.kind() == io::ErrorKind::AlreadyExists
                    && fs::symlink_metadata(&config)?.file_type().is_dir() => {}
            Err(error) => return Err(error.into()),
        }
    }
    let manifest = config.join("project.json");
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&manifest)
    {
        Ok(mut file) => file.write_all(b"{\"schemaVersion\":1}\n")?,
        Err(error)
            if error.kind() == io::ErrorKind::AlreadyExists
                && fs::symlink_metadata(&manifest)?.file_type().is_file() => {}
        Err(error) => return Err(error.into()),
    }
    Ok(".agents/aita/project.json")
}
