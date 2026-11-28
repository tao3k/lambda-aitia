// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! SysML v2 parsing and architectural scope projection host capabilities.

use super::{
    CapabilityError, CapabilityFrame, HostCapability, HostCapabilityRegistry, HostEffectClass,
    HostReceipt,
};

pub(super) fn register(registry: &mut HostCapabilityRegistry) {
    registry.register(Box::new(SysmlProjectScopesCapability));
    registry.register(Box::new(SysmlRevisionScopesCapability));
    registry.register(Box::new(SysmlParseRevisionCapability));
    registry.register(Box::new(SysmlParseWorkspaceCapability));
}

struct SysmlProjectScopesCapability;

impl HostCapability for SysmlProjectScopesCapability {
    fn capability_id(&self) -> &'static str {
        "sysml.project-scopes"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let enabled = request["enabled"].as_bool().unwrap_or(true);
        let scopes = project_scopes_json(std::path::Path::new(directory), enabled)?;
        let payload = serde_json::to_string(&scopes)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct SysmlRevisionScopesCapability;

impl HostCapability for SysmlRevisionScopesCapability {
    fn capability_id(&self) -> &'static str {
        "sysml.revision-scopes"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let revision = request["revision"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing revision field".to_owned()))?;
        let enabled = request["enabled"].as_bool().unwrap_or(true);
        let scopes =
            project_revision_scopes_json(std::path::Path::new(directory), revision, enabled);
        let payload = serde_json::to_string(&scopes)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct SysmlParseRevisionCapability;

impl HostCapability for SysmlParseRevisionCapability {
    fn capability_id(&self) -> &'static str {
        "sysml.parse-revision"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let revision = request["revision"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing revision field".to_owned()))?;
        let paths = string_array(&request["paths"]);
        let report = parse_revision_sysml_json(std::path::Path::new(directory), revision, &paths)?;
        let payload = serde_json::to_string(&report)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct SysmlParseWorkspaceCapability;

impl HostCapability for SysmlParseWorkspaceCapability {
    fn capability_id(&self) -> &'static str {
        "sysml.parse-workspace"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let mode = request["mode"].as_str().unwrap_or("commit");
        let enabled = request["enabled"].as_bool().unwrap_or(true);
        let paths = string_array(&request["paths"]);
        let result =
            parse_workspace_sysml_json(std::path::Path::new(directory), mode, &paths, enabled)?;
        let payload = serde_json::to_string(&result)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

fn string_array(value: &serde_json::Value) -> Vec<String> {
    value
        .as_array()
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default()
}

#[cfg(feature = "sysml")]
fn scopes_to_json(scopes: Vec<crate::sysml::SysmlScopeProjection>) -> Vec<serde_json::Value> {
    scopes
        .into_iter()
        .map(|scope| {
            serde_json::json!({
                "name": scope.name,
                "paths": scope.paths,
                "elementId": scope.element_id,
            })
        })
        .collect()
}

#[cfg(feature = "sysml")]
fn project_scopes_json(
    directory: &std::path::Path,
    enabled: bool,
) -> Result<Vec<serde_json::Value>, CapabilityError> {
    if !enabled {
        return Ok(Vec::new());
    }
    let cut = aitia_jj::observe_workspace(directory)
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
    match crate::sysml::project_recorded_scopes(&cut) {
        Ok(scopes) => Ok(scopes_to_json(scopes)),
        // Fail closed: unparseable or oversized SysML models contribute zero scopes.
        Err(_) => Ok(Vec::new()),
    }
}

#[cfg(not(feature = "sysml"))]
fn project_scopes_json(
    _directory: &std::path::Path,
    _enabled: bool,
) -> Result<Vec<serde_json::Value>, CapabilityError> {
    Ok(Vec::new())
}

#[cfg(feature = "sysml")]
fn project_revision_scopes_json(
    directory: &std::path::Path,
    revision: &str,
    enabled: bool,
) -> Vec<serde_json::Value> {
    if !enabled {
        return Vec::new();
    }
    match crate::sysml::project_revision_scopes(directory, revision) {
        Ok(scopes) => scopes_to_json(scopes),
        Err(_) => Vec::new(),
    }
}

#[cfg(not(feature = "sysml"))]
fn project_revision_scopes_json(
    _directory: &std::path::Path,
    _revision: &str,
    _enabled: bool,
) -> Vec<serde_json::Value> {
    Vec::new()
}

#[cfg(feature = "sysml")]
fn parse_revision_sysml_json(
    directory: &std::path::Path,
    revision: &str,
    paths: &[String],
) -> Result<serde_json::Value, CapabilityError> {
    crate::sysml::parse_model_report(|| {
        crate::sysml::revision_documents(directory, revision, paths)
    })
    .map_err(|error| CapabilityError::Execution(format!("{error} ({error:?})")))
}

#[cfg(not(feature = "sysml"))]
fn parse_revision_sysml_json(
    _directory: &std::path::Path,
    _revision: &str,
    _paths: &[String],
) -> Result<serde_json::Value, CapabilityError> {
    Err(CapabilityError::Execution(
        "SysML evidence verification is unavailable in this build".to_owned(),
    ))
}

#[cfg(feature = "sysml")]
fn parse_workspace_sysml_json(
    directory: &std::path::Path,
    mode: &str,
    paths: &[String],
    enabled: bool,
) -> Result<serde_json::Value, CapabilityError> {
    if !enabled {
        return Ok(serde_json::json!({ "model": null, "scopes": [] }));
    }
    let cut = aitia_jj::observe_workspace(directory)
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
    if mode == "check" {
        let sources = aitia_jj::recorded_sysml_paths(&cut)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        if sources.is_empty() {
            return Err(CapabilityError::Execution(
                "no recorded SysML documents".to_owned(),
            ));
        }
        return crate::sysml::parse_model_report(|| {
            crate::sysml::recorded_documents(&cut, &sources)
        })
        .map_err(|error| CapabilityError::Execution(format!("{error} ({error:?})")));
    }
    let (model, scopes) = crate::sysml::observe_commit_sysml_and_scopes(&cut, paths);
    Ok(serde_json::json!({
        "model": model,
        "scopes": scopes_to_json(scopes),
    }))
}

#[cfg(not(feature = "sysml"))]
fn parse_workspace_sysml_json(
    _directory: &std::path::Path,
    mode: &str,
    paths: &[String],
    enabled: bool,
) -> Result<serde_json::Value, CapabilityError> {
    if !enabled {
        return Ok(serde_json::json!({ "model": null, "scopes": [] }));
    }
    let message = "SysML parsing is enabled in project configuration but unavailable in this build";
    if mode == "check" {
        return Err(CapabilityError::Execution(message.to_owned()));
    }
    let model = (!paths.is_empty())
        .then(|| serde_json::json!({ "paths": paths, "status": "open", "detail": message }));
    Ok(serde_json::json!({ "model": model, "scopes": [] }))
}
