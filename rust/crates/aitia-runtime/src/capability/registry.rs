// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Core Host Capability traits, typed frames/receipts, and fail-closed registry dispatch.

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

    /// Project registered capability descriptors into the public JSON envelope.
    #[cfg(feature = "linked-program")]
    #[must_use]
    pub fn descriptors_json(&self) -> serde_json::Value {
        let descriptors: Vec<serde_json::Value> = self
            .descriptors()
            .into_iter()
            .map(|(capability, class)| {
                let effect = match class {
                    HostEffectClass::HostRead => "host-read",
                    HostEffectClass::FencedEffect => "fenced-effect",
                };
                serde_json::json!({ "capability": capability, "effectClass": effect })
            })
            .collect();
        serde_json::json!({
            "schema": "lambda-aitia.host-capabilities.v1",
            "capabilities": descriptors,
            "actionAuthorized": false,
        })
    }

    /// Dispatch a single capability frame after enforcing effect-class and fence invariants.
    ///
    /// # Errors
    /// Fails closed on unknown capabilities, effect-class mismatches, or missing fence tokens.
    pub fn dispatch(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let handler = self.validate_frame(frame)?;
        let mut receipt = handler.invoke(frame)?;
        receipt.action_authorized = false;
        Ok(receipt)
    }

    fn validate_frame(
        &self,
        frame: &CapabilityFrame,
    ) -> Result<&dyn HostCapability, CapabilityError> {
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
        Ok(handler.as_ref())
    }

    /// Dispatch a sequence of capability frames, failing closed before execution on any violation.
    ///
    /// Every frame is validated against its registered capability, effect class, and fence token
    /// before any capability in the batch is executed. Pure multi-frame `HostRead` batches fan out
    /// concurrently via `std::thread::scope` while preserving exact deterministic output order;
    /// any batch containing a `FencedEffect` executes strictly sequentially.
    ///
    /// # Errors
    /// Fails closed before executing any frame if any entry is unknown, mismatched, or unfenced,
    /// or returns the first execution error.
    pub fn dispatch_batch(
        &self,
        frames: &[CapabilityFrame],
    ) -> Result<Vec<HostReceipt>, CapabilityError> {
        frames
            .iter()
            .try_for_each(|frame| self.validate_frame(frame).map(|_| ()))?;
        let all_reads = frames.len() > 1
            && frames
                .iter()
                .all(|frame| frame.effect_class == HostEffectClass::HostRead);
        if all_reads {
            return std::thread::scope(|scope| {
                let handles: Vec<_> = frames
                    .iter()
                    .map(|frame| scope.spawn(move || self.dispatch(frame)))
                    .collect();
                handles
                    .into_iter()
                    .map(|handle| {
                        handle.join().unwrap_or_else(|_| {
                            Err(CapabilityError::Execution(
                                "host read capability worker panicked".to_owned(),
                            ))
                        })
                    })
                    .collect()
            });
        }
        frames.iter().map(|frame| self.dispatch(frame)).collect()
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

    /// Decode a Scheme-emitted JSON frame batch, validate and dispatch it via [`Self::dispatch_batch`],
    /// and return `(receipt_key, parsed_json_payload)` pairs.
    ///
    /// # Errors
    /// Fails closed on malformed frame descriptors, unknown capabilities, effect-class mismatches,
    /// missing fence tokens, or capability execution failures.
    #[cfg(feature = "linked-program")]
    pub fn dispatch_protocol_frames(
        &self,
        raw_frames: &[serde_json::Value],
    ) -> Result<Vec<(String, serde_json::Value)>, CapabilityError> {
        let mut frames = Vec::with_capacity(raw_frames.len());
        let mut keys = Vec::with_capacity(raw_frames.len());
        for raw in raw_frames {
            let cap = raw["capability"]
                .as_str()
                .ok_or_else(|| CapabilityError::Execution("frame missing capability".to_owned()))?;
            let effect_class = match raw["effectClass"].as_str() {
                Some("host-read") => HostEffectClass::HostRead,
                Some("fenced-effect") => HostEffectClass::FencedEffect,
                _ => {
                    return Err(CapabilityError::Execution(
                        "frame has invalid effectClass".to_owned(),
                    ));
                }
            };
            let payload = serde_json::to_string(&raw["payload"])
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
            frames.push(CapabilityFrame {
                capability: CapabilityId::new(cap),
                effect_class,
                payload,
                fence_token: raw["fenceToken"].as_str().map(str::to_owned),
            });
            keys.push(raw["receiptKey"].as_str().unwrap_or(cap).to_owned());
        }
        let receipts = self.dispatch_batch(&frames)?;
        keys.into_iter()
            .zip(receipts)
            .map(|(key, receipt)| {
                let parsed = serde_json::from_str(&receipt.payload)
                    .map_err(|error| CapabilityError::Execution(error.to_string()))?;
                Ok((key, parsed))
            })
            .collect()
    }

    /// Construct the default host capability registry (HostRead + FencedEffect) for the linked runtime.
    #[cfg(feature = "linked-program")]
    #[must_use]
    pub fn default_linked() -> Self {
        let mut registry = Self::new();
        super::review::register(&mut registry);
        super::jj::register(&mut registry);
        super::sysml::register(&mut registry);
        registry
    }
}
