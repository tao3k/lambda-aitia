// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Content-addressed public interface digest projection capability (`interface.project-digest`).
//!
//! Computes a deterministic SHA-256 digest over a repository's declared public interface
//! files (`interfacePaths`), reading recorded JJ cut bytes when available so Bazel Skyframe
//! two-level Early Cutoff operates on verified source contents rather than ad-hoc strings.

use super::{
    CapabilityError, CapabilityFrame, HostCapability, HostCapabilityRegistry, HostEffectClass,
    HostReceipt,
};
use serde_json::{Value, json};
use std::fs;
use std::path::{Component, Path};

pub(super) fn register(registry: &mut HostCapabilityRegistry) {
    registry.register(Box::new(InterfaceProjectDigestCapability));
}

struct InterfaceProjectDigestCapability;

impl HostCapability for InterfaceProjectDigestCapability {
    fn capability_id(&self) -> &'static str {
        "interface.project-digest"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let mut paths: Vec<String> = request["interfacePaths"]
            .as_array()
            .ok_or_else(|| {
                CapabilityError::Execution(
                    "interface.project-digest requires non-empty `interfacePaths` array".to_owned(),
                )
            })?
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_owned)
            .collect();
        paths.sort();
        paths.dedup();
        if paths.is_empty() {
            return Err(CapabilityError::Execution(
                "interface.project-digest requires at least one interface path".to_owned(),
            ));
        }
        for path in &paths {
            validate_relative_path(path)?;
        }
        let dir_path = Path::new(directory);
        let (commit_opt, digest) = compute_interface_digest(dir_path, &paths)?;
        let receipt = json!({
            "schema": "lambda-aitia.interface-digest.v1",
            "directory": directory,
            "commit": commit_opt,
            "interfacePaths": paths,
            "interfaceDigest": digest,
            "actionAuthorized": false,
        });
        let payload = serde_json::to_string(&receipt)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

fn validate_relative_path(rel: &str) -> Result<(), CapabilityError> {
    let path = Path::new(rel);
    if rel.is_empty() || path.is_absolute() || rel.contains('\0') {
        return Err(CapabilityError::Execution(format!(
            "invalid interface path `{rel}`"
        )));
    }
    for component in path.components() {
        match component {
            Component::Normal(_) => {}
            _ => {
                return Err(CapabilityError::Execution(format!(
                    "unsafe interface path component in `{rel}`"
                )));
            }
        }
    }
    Ok(())
}

fn compute_interface_digest(
    dir_path: &Path,
    paths: &[String],
) -> Result<(Option<String>, String), CapabilityError> {
    if dir_path.join(".jj").exists() {
        let cut = aitia_jj::observe_workspace(dir_path)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let path_refs: Vec<&str> = paths.iter().map(String::as_str).collect();
        let frozen = crate::source_tree::capture_recorded_source_tree(&cut, &path_refs)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let digest = crate::source_tree::sha256(&frozen);
        return Ok((Some(cut.commit_id().to_owned()), digest));
    }

    let root = dir_path
        .canonicalize()
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
    let mut encoded = Vec::new();
    encoded.extend_from_slice(b"lambda-aitia.source-tree.v1\0");
    encoded.extend_from_slice(&(paths.len() as u64).to_be_bytes());
    for rel in paths {
        let joined = root.join(rel);
        let meta = fs::symlink_metadata(&joined)
            .map_err(|error| CapabilityError::Execution(format!("{rel}: {error}")))?;
        if !meta.file_type().is_file() {
            return Err(CapabilityError::Execution(format!(
                "interface path `{rel}` must be a regular file"
            )));
        }
        let canonical = joined
            .canonicalize()
            .map_err(|error| CapabilityError::Execution(format!("{rel}: {error}")))?;
        if !canonical.starts_with(&root) {
            return Err(CapabilityError::Execution(format!(
                "interface path `{rel}` escapes repository root"
            )));
        }
        let bytes = fs::read(&canonical)
            .map_err(|error| CapabilityError::Execution(format!("{rel}: {error}")))?;
        let path_len = u32::try_from(rel.len())
            .map_err(|_| CapabilityError::Execution(format!("path too long: `{rel}`")))?;
        encoded.extend_from_slice(&path_len.to_be_bytes());
        encoded.extend_from_slice(rel.as_bytes());
        encoded.extend_from_slice(&(bytes.len() as u64).to_be_bytes());
        encoded.extend_from_slice(&bytes);
    }
    Ok((None, crate::source_tree::sha256(&encoded)))
}
