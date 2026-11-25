// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin Rust Host Capability Frame Mapper boundary.
//!
//! Scheme (POO + ASCENT + FunFlow) owns higher-order workflow orchestration,
//! semantic merging, obligation reasoning, and effect authorization. Rust
//! implements only a flat capability table that executes concrete host
//! observations (`HostRead`) or Scheme-fenced mutations (`FencedEffect`) and
//! returns raw attributable receipts with `action_authorized == false`.

use std::{collections::BTreeMap, fmt};

/// Stable typed identifier of a host capability (for example `"sysml.project-scopes"`).
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct CapabilityId(String);

impl CapabilityId {
    /// Wrap a capability identifier string into a typed [`CapabilityId`].
    #[must_use]
    pub fn new(id: impl Into<String>) -> Self {
        Self(id.into())
    }

    /// Borrow the underlying capability identifier string.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for CapabilityId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

/// Effect class aligned with FunFlow's host handoff boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HostEffectClass {
    /// Side-effect-free host observation (JJ cut read, recorded file read, SysML parse/projection).
    HostRead,
    /// State-mutating host effect that requires an explicit Scheme-issued fence token.
    FencedEffect,
}

/// Typed failure returned by the Rust host capability frame mapper.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CapabilityError {
    /// The requested capability name is not registered in the host table.
    UnknownCapability(CapabilityId),
    /// A `FencedEffect` capability was invoked without a non-empty fence token.
    MissingFenceToken(CapabilityId),
    /// A frame declared a different effect class than the registered capability.
    EffectClassMismatch {
        capability: CapabilityId,
        expected: HostEffectClass,
        actual: HostEffectClass,
    },
    /// Capability execution failed at the underlying host boundary.
    Execution(String),
}

impl fmt::Display for CapabilityError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnknownCapability(capability) => {
                write!(formatter, "unknown host capability: {capability}")
            }
            Self::MissingFenceToken(capability) => {
                write!(
                    formatter,
                    "fenced host capability requires fence token: {capability}"
                )
            }
            Self::EffectClassMismatch {
                capability,
                expected,
                actual,
            } => write!(
                formatter,
                "capability {capability} effect class mismatch: expected {expected:?}, got {actual:?}"
            ),
            Self::Execution(message) => write!(formatter, "host capability failed: {message}"),
        }
    }
}

impl std::error::Error for CapabilityError {}

/// Single typed request frame dispatched from Scheme/CLI to a registered Rust capability.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CapabilityFrame {
    pub capability: CapabilityId,
    pub effect_class: HostEffectClass,
    pub payload: String,
    pub fence_token: Option<String>,
}

/// Raw attributable host observation returned to Scheme.
///
/// Rust never grants semantic, release, or effect authority; `action_authorized`
/// is structurally `false`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HostReceipt {
    pub capability: CapabilityId,
    pub effect_class: HostEffectClass,
    pub payload: String,
    pub action_authorized: bool,
}

impl HostReceipt {
    /// Construct a host receipt with `action_authorized` permanently pinned to `false`.
    #[must_use]
    pub fn observe(
        capability: impl Into<String>,
        effect_class: HostEffectClass,
        payload: String,
    ) -> Self {
        Self {
            capability: CapabilityId::new(capability),
            effect_class,
            payload,
            action_authorized: false,
        }
    }
}

/// Trait implemented by every concrete host capability exposed to Scheme FunFlow.
pub trait HostCapability: Send + Sync {
    /// Stable capability identifier (for example `"sysml.project-scopes"`).
    fn capability_id(&self) -> &'static str;

    /// Effect class enforced by the registry before dispatch.
    fn effect_class(&self) -> HostEffectClass;

    /// Execute the capability against a validated frame and return a raw receipt.
    ///
    /// # Errors
    /// Returns [`CapabilityError::Execution`] if the host call fails.
    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError>;
}

/// Flat registry mapping capability identifiers to concrete Rust host adapters.
#[derive(Default)]
pub struct HostCapabilityRegistry {
    handlers: BTreeMap<&'static str, Box<dyn HostCapability>>,
}

impl HostCapabilityRegistry {
    /// Create an empty capability registry.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Register one host capability handler by its static identifier.
    pub fn register(&mut self, handler: Box<dyn HostCapability>) {
        self.handlers.insert(handler.capability_id(), handler);
    }

    /// List registered capability identifiers and their declared effect classes in sorted order.
    #[must_use]
    pub fn descriptors(&self) -> Vec<(&'static str, HostEffectClass)> {
        self.handlers
            .values()
            .map(|handler| (handler.capability_id(), handler.effect_class()))
            .collect()
    }

    /// Dispatch a single capability frame after enforcing effect-class and fence invariants.
    ///
    /// # Errors
    /// Fails closed on unknown capabilities, effect-class mismatches, or missing fence tokens.
    pub fn dispatch(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let Some(handler) = self.handlers.get(frame.capability.as_str()) else {
            return Err(CapabilityError::UnknownCapability(frame.capability.clone()));
        };
        let expected = handler.effect_class();
        if frame.effect_class != expected {
            return Err(CapabilityError::EffectClassMismatch {
                capability: frame.capability.clone(),
                expected,
                actual: frame.effect_class,
            });
        }
        if expected == HostEffectClass::FencedEffect
            && frame
                .fence_token
                .as_deref()
                .is_none_or(|token| token.trim().is_empty())
        {
            return Err(CapabilityError::MissingFenceToken(frame.capability.clone()));
        }
        let mut receipt = handler.invoke(frame)?;
        receipt.action_authorized = false;
        Ok(receipt)
    }

    /// Dispatch a sequence of capability frames in order, failing closed on the first violation.
    ///
    /// Every frame is validated against its registered capability, effect class, and fence token
    /// before any capability in the batch is executed.
    ///
    /// # Errors
    /// Fails closed before executing any frame if any entry is unknown, mismatched, or unfenced,
    /// or returns the first execution error.
    pub fn dispatch_batch(
        &self,
        frames: &[CapabilityFrame],
    ) -> Result<Vec<HostReceipt>, CapabilityError> {
        for frame in frames {
            let Some(handler) = self.handlers.get(frame.capability.as_str()) else {
                return Err(CapabilityError::UnknownCapability(frame.capability.clone()));
            };
            let expected = handler.effect_class();
            if frame.effect_class != expected {
                return Err(CapabilityError::EffectClassMismatch {
                    capability: frame.capability.clone(),
                    expected,
                    actual: frame.effect_class,
                });
            }
            if expected == HostEffectClass::FencedEffect
                && frame
                    .fence_token
                    .as_deref()
                    .is_none_or(|token| token.trim().is_empty())
            {
                return Err(CapabilityError::MissingFenceToken(frame.capability.clone()));
            }
        }
        let mut receipts = Vec::with_capacity(frames.len());
        for frame in frames {
            receipts.push(self.dispatch(frame)?);
        }
        Ok(receipts)
    }

    /// Dispatch a JSON-encoded frame and decode its JSON receipt payload.
    ///
    /// # Errors
    /// Propagates [`CapabilityError`] from dispatch or JSON serialization/deserialization.
    #[cfg(feature = "linked-program")]
    pub fn dispatch_json(
        &self,
        capability: &str,
        effect_class: HostEffectClass,
        payload: &serde_json::Value,
        fence_token: Option<String>,
    ) -> Result<serde_json::Value, CapabilityError> {
        let encoded = serde_json::to_string(payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let receipt = self.dispatch(&CapabilityFrame {
            capability: CapabilityId::new(capability),
            effect_class,
            payload: encoded,
            fence_token,
        })?;
        serde_json::from_str(&receipt.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))
    }

    /// Construct the default read-only host capability registry for the linked CLI.
    #[cfg(feature = "linked-program")]
    #[must_use]
    pub fn default_linked() -> Self {
        let mut registry = Self::new();
        registry.register(Box::new(GitOpsGithubObservePrCapability));
        registry.register(Box::new(GitOpsJjObserveCutCapability));
        registry.register(Box::new(SysmlProjectScopesCapability));
        registry.register(Box::new(SysmlRevisionScopesCapability));
        registry.register(Box::new(SysmlParseRevisionCapability));
        registry.register(Box::new(SysmlParseWorkspaceCapability));
        registry
    }
}

#[cfg(feature = "linked-program")]
struct GitOpsGithubObservePrCapability;

#[cfg(feature = "linked-program")]
impl HostCapability for GitOpsGithubObservePrCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.github.observe-pr"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let cut = aitia_jj::observe_workspace(std::path::Path::new(directory))
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let bookmarks = aitia_jj::recorded_review_bookmarks(&cut)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let provider = crate::review_provider::observe(&bookmarks, cut.commit_id());
        let payload = serde_json::to_string(&serde_json::json!({
            "bookmarks": bookmarks,
            "providerReview": provider,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

#[cfg(feature = "linked-program")]
struct GitOpsJjObserveCutCapability;

#[cfg(feature = "linked-program")]
impl HostCapability for GitOpsJjObserveCutCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.observe-cut"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let requested_paths: Vec<String> = request["requestedPaths"]
            .as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();
        let cut = aitia_jj::observe_workspace(std::path::Path::new(directory))
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let changes = aitia_jj::recorded_changes(&cut)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let path_refs: Vec<&str> = requested_paths.iter().map(String::as_str).collect();
        let max_bytes = usize::try_from(crate::MAX_REQUEST_BYTES)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let observed = aitia_jj::observe_recorded_sources(&cut, &path_refs, max_bytes)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let mut sources = Vec::new();
        for (path, result) in observed {
            if let Ok(text) = result {
                sources.push(serde_json::json!({ "path": path, "text": text }));
            }
        }
        let paths: Vec<&str> = changes.iter().map(|change| change.path.as_str()).collect();
        let payload = serde_json::to_string(&serde_json::json!({
            "cut": crate::cli_commit::review_cut_value(&cut),
            "paths": paths,
            "sources": sources,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

#[cfg(feature = "linked-program")]
struct SysmlProjectScopesCapability;

#[cfg(feature = "linked-program")]
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

#[cfg(feature = "linked-program")]
struct SysmlRevisionScopesCapability;

#[cfg(feature = "linked-program")]
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

#[cfg(feature = "linked-program")]
struct SysmlParseRevisionCapability;

#[cfg(feature = "linked-program")]
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

#[cfg(feature = "linked-program")]
struct SysmlParseWorkspaceCapability;

#[cfg(feature = "linked-program")]
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

#[cfg(feature = "linked-program")]
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

#[cfg(all(feature = "linked-program", feature = "sysml"))]
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

#[cfg(all(feature = "linked-program", feature = "sysml"))]
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

#[cfg(all(feature = "linked-program", not(feature = "sysml")))]
fn project_scopes_json(
    _directory: &std::path::Path,
    _enabled: bool,
) -> Result<Vec<serde_json::Value>, CapabilityError> {
    Ok(Vec::new())
}

#[cfg(all(feature = "linked-program", feature = "sysml"))]
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

#[cfg(all(feature = "linked-program", not(feature = "sysml")))]
fn project_revision_scopes_json(
    _directory: &std::path::Path,
    _revision: &str,
    _enabled: bool,
) -> Vec<serde_json::Value> {
    Vec::new()
}

#[cfg(all(feature = "linked-program", feature = "sysml"))]
fn parse_revision_sysml_json(
    directory: &std::path::Path,
    revision: &str,
    paths: &[String],
) -> Result<serde_json::Value, CapabilityError> {
    crate::sysml::parse_model_report(|| {
        crate::sysml::revision_documents(directory, revision, paths)
    })
    .map_err(|error| CapabilityError::Execution(error.to_string()))
}

#[cfg(all(feature = "linked-program", not(feature = "sysml")))]
fn parse_revision_sysml_json(
    _directory: &std::path::Path,
    _revision: &str,
    _paths: &[String],
) -> Result<serde_json::Value, CapabilityError> {
    Err(CapabilityError::Execution(
        "SysML evidence verification is unavailable in this build".to_owned(),
    ))
}

#[cfg(all(feature = "linked-program", feature = "sysml"))]
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
        .map_err(|error| CapabilityError::Execution(error.to_string()));
    }
    let (model, scopes) = crate::sysml::observe_commit_sysml_and_scopes(&cut, paths);
    Ok(serde_json::json!({
        "model": model,
        "scopes": scopes_to_json(scopes),
    }))
}

#[cfg(all(feature = "linked-program", not(feature = "sysml")))]
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
