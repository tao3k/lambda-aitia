// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Content-addressed public interface digest projection capability (`interface.project-digest`).
//!
//! Computes a deterministic SHA-256 digest over a repository's declared public interface
//! files (`interfacePaths`), reading recorded JJ cut bytes when available so Bazel Skyframe
//! two-level Early Cutoff operates on verified source contents rather than ad-hoc strings.
//!
//! Supports `"normalization": "semantic"` (default: strips comments and insignificant whitespace
//! for C/Rust/SysML/Scheme/Python headers so comment-only edits preserve the ABI digest) and
//! `"normalization": "raw"` (exact frozen byte digest).

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum NormalizationMode {
    Semantic,
    Raw,
}

impl NormalizationMode {
    fn parse(raw: Option<&str>) -> Result<Self, CapabilityError> {
        match raw {
            None | Some("semantic") => Ok(Self::Semantic),
            Some("raw") => Ok(Self::Raw),
            Some(other) => Err(CapabilityError::Execution(format!(
                "unsupported interface normalization mode `{other}` (expected `semantic` or `raw`)"
            ))),
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Semantic => "semantic",
            Self::Raw => "raw",
        }
    }
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
        let mode = NormalizationMode::parse(request["normalization"].as_str())?;
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
        let (commit_opt, digest) = compute_interface_digest(dir_path, &paths, mode)?;
        let receipt = json!({
            "schema": "lambda-aitia.interface-digest.v1",
            "directory": directory,
            "commit": commit_opt,
            "interfacePaths": paths,
            "normalization": mode.as_str(),
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
    mode: NormalizationMode,
) -> Result<(Option<String>, String), CapabilityError> {
    let (commit_opt, raw_entries) = read_interface_entries(dir_path, paths)?;
    let mut encoded = Vec::new();
    encoded.extend_from_slice(b"lambda-aitia.interface-projection.v1\0");
    encoded.extend_from_slice(mode.as_str().as_bytes());
    encoded.push(0);
    encoded.extend_from_slice(&(raw_entries.len() as u64).to_be_bytes());
    for (rel, bytes) in raw_entries {
        let projected = match mode {
            NormalizationMode::Raw => bytes,
            NormalizationMode::Semantic => normalize_semantic_bytes(&rel, &bytes)?,
        };
        let path_len = u32::try_from(rel.len())
            .map_err(|_| CapabilityError::Execution(format!("path too long: `{rel}`")))?;
        encoded.extend_from_slice(&path_len.to_be_bytes());
        encoded.extend_from_slice(rel.as_bytes());
        encoded.extend_from_slice(&(projected.len() as u64).to_be_bytes());
        encoded.extend_from_slice(&projected);
    }
    Ok((commit_opt, crate::source_tree::sha256(&encoded)))
}

fn read_interface_entries(
    dir_path: &Path,
    paths: &[String],
) -> Result<(Option<String>, Vec<(String, Vec<u8>)>), CapabilityError> {
    if dir_path.join(".jj").exists() {
        let cut = aitia_jj::observe_workspace(dir_path)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let path_refs: Vec<&str> = paths.iter().map(String::as_str).collect();
        let frozen = crate::source_tree::capture_recorded_source_tree(&cut, &path_refs)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let files = crate::source_tree::decode_source_tree(&frozen)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let entries = files
            .into_iter()
            .map(|f| (f.path.to_owned(), f.bytes.to_vec()))
            .collect();
        return Ok((Some(cut.commit_id().to_owned()), entries));
    }

    let root = dir_path
        .canonicalize()
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
    let mut entries = Vec::with_capacity(paths.len());
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
        entries.push((rel.clone(), bytes));
    }
    Ok((None, entries))
}

/// Project public interface files semantically:
/// - `.sysml` files (when `sysml` feature is enabled): parse via OpenSysML and emit an
///   order-independent, doc-insensitive canonical AST signature (true AST-level Early Cutoff).
/// - C/C++/Rust/Scheme/Python/etc.: strip comments and insignificant whitespace while
///   preserving quoted string literals verbatim. Non-UTF8 bytes stay raw.
fn normalize_semantic_bytes(rel: &str, bytes: &[u8]) -> Result<Vec<u8>, CapabilityError> {
    let Ok(text) = std::str::from_utf8(bytes) else {
        return Ok(bytes.to_vec());
    };
    let ext = Path::new(rel)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    #[cfg(feature = "sysml")]
    if ext == "sysml" {
        let sig = crate::sysml::canonical_sysml_interface_signature(rel, text)
            .map_err(|error| CapabilityError::Execution(format!("{rel}: {error}")))?;
        return Ok(sig.into_bytes());
    }
    let stripped = match ext.as_str() {
        "h" | "hpp" | "c" | "cc" | "cpp" | "rs" | "sysml" | "ts" | "js" | "go" | "java" => {
            strip_c_style_comments(text)
        }
        "ss" | "scm" | "lisp" => strip_line_comment_char(text, ';'),
        "py" | "toml" | "yaml" | "yml" => strip_line_comment_char(text, '#'),
        _ => text.to_owned(),
    };
    Ok(canonicalize_lines(&stripped).into_bytes())
}

fn strip_c_style_comments(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    let mut in_string = false;
    let mut escaped = false;
    while i < chars.len() {
        let ch = chars[i];
        if in_string {
            out.push(ch);
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        if ch == '"' {
            in_string = true;
            out.push(ch);
            i += 1;
        } else if ch == '/' && i + 1 < chars.len() && chars[i + 1] == '/' {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
        } else if ch == '/' && i + 1 < chars.len() && chars[i + 1] == '*' {
            i += 2;
            while i + 1 < chars.len() && !(chars[i] == '*' && chars[i + 1] == '/') {
                if chars[i] == '\n' {
                    out.push('\n');
                }
                i += 1;
            }
            i = (i + 2).min(chars.len());
        } else {
            out.push(ch);
            i += 1;
        }
    }
    out
}

fn strip_line_comment_char(input: &str, marker: char) -> String {
    let mut out = String::with_capacity(input.len());
    let mut in_string = false;
    let mut escaped = false;
    let mut skipping = false;
    for ch in input.chars() {
        if skipping {
            if ch == '\n' {
                skipping = false;
                out.push('\n');
            }
            continue;
        }
        if in_string {
            out.push(ch);
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }
        if ch == '"' {
            in_string = true;
            out.push(ch);
        } else if ch == marker {
            skipping = true;
        } else {
            out.push(ch);
        }
    }
    out
}

fn canonicalize_lines(input: &str) -> String {
    let mut lines = Vec::new();
    for raw_line in input.lines() {
        let mut normalized = String::new();
        let mut in_string = false;
        let mut escaped = false;
        let mut pending_space = false;
        for ch in raw_line.trim().chars() {
            if in_string {
                normalized.push(ch);
                if escaped {
                    escaped = false;
                } else if ch == '\\' {
                    escaped = true;
                } else if ch == '"' {
                    in_string = false;
                }
                continue;
            }
            if ch == '"' {
                if pending_space && !normalized.is_empty() {
                    normalized.push(' ');
                }
                pending_space = false;
                in_string = true;
                normalized.push(ch);
            } else if ch.is_whitespace() {
                pending_space = true;
            } else {
                if pending_space && !normalized.is_empty() {
                    normalized.push(' ');
                }
                pending_space = false;
                normalized.push(ch);
            }
        }
        if !normalized.is_empty() {
            lines.push(normalized);
        }
    }
    lines.join("\n")
}
