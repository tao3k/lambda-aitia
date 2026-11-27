// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Deterministic Engineering formal library reuse (`upstream-library-reuse`),
//! project-specific ephemeral AI overlays (`ephemeral-ai-overlay` with mandatory
//! MR05 `@countermodel` & sidecar vault isolation), G2 mechanical diff-delta
//! defects, F3 Quint `guard-probe`, and explicit `PendingMethod` verification
//! (RFC 0023). Never grants execution authority (`actionAuthorized: false`).

use super::{Result, err};
use serde_json::{Value, json};
use std::fmt::Write as _;

const FORMAL_EVIDENCE_SCHEMA: &str = "lambda-aitia.de-formal-evidence.v1";

fn require_sha256(value: &str, label: &str) -> Result<()> {
    let hex = value
        .strip_prefix("sha256:")
        .ok_or_else(|| err(format!("{label} must be a sha256:-prefixed digest")))?;
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(err(format!("{label} must be a 64-hex-char sha256 digest")));
    }
    Ok(())
}

pub(crate) fn verify_formal_evidence(
    formal: &Value,
    expected_context_digest: &str,
) -> Result<Value> {
    if formal["schema"].as_str() != Some(FORMAL_EVIDENCE_SCHEMA)
        || formal["actionAuthorized"].as_bool() != Some(false)
    {
        return Err(err("Invalid DE formal evidence schema or flags"));
    }
    if let Some(pending) = formal.get("pendingOracles").and_then(Value::as_array) {
        let pending_names: Vec<&str> = pending
            .iter()
            .filter_map(Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .collect();
        if !pending_names.is_empty() {
            return Err(err(format!(
                "PendingMethod: mechanical oracles unavailable ({}) — never silently passes",
                pending_names.join(", ")
            )));
        }
    }
    if let Some(g2_findings) = formal.get("g2Findings").and_then(Value::as_array)
        && !g2_findings.is_empty()
    {
        let first_id = g2_findings[0]["id"]
            .as_str()
            .or_else(|| g2_findings[0]["rule"].as_str())
            .unwrap_or("g2-defect");
        return Err(err(format!(
            "DE G2 diff-delta defect `{first_id}` blocks admission ({} findings)",
            g2_findings.len()
        )));
    }
    let mut essential_probes = 0usize;
    if let Some(probes) = formal.get("guardProbes").and_then(Value::as_array) {
        for probe in probes {
            let pid = probe["probeId"]
                .as_str()
                .filter(|s| !s.trim().is_empty())
                .ok_or_else(|| err("Guard probe missing probeId"))?;
            if probe["verdict"].as_str() != Some("essential") {
                return Err(err(format!(
                    "F3 Quint guard-probe `{pid}` rejected: non-essential or redundant-or-under-modeled"
                )));
            }
            essential_probes += 1;
        }
    }
    let models = formal
        .get("formalModels")
        .and_then(Value::as_array)
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| err("DE formal evidence requires at least one formalModels entry"))?;
    let mut admitted_models: Vec<Value> = Vec::with_capacity(models.len());
    let mut upstream_reuse_count = 0usize;
    let mut ephemeral_overlay_count = 0usize;
    for model in models {
        let model_id = model["modelId"]
            .as_str()
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| err("Formal model entry missing modelId"))?;
        let mode = model["mode"]
            .as_str()
            .filter(|m| matches!(*m, "upstream-library-reuse" | "ephemeral-ai-overlay"))
            .ok_or_else(|| {
                err(format!(
                    "Formal model `{model_id}` has invalid mode (expected upstream-library-reuse or ephemeral-ai-overlay)"
                ))
            })?;
        let lib_pkg = model["libraryPackage"]
            .as_str()
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| {
                err(format!(
                    "Formal model `{model_id}` missing pinned libraryPackage"
                ))
            })?;
        let resolver_digest = model["resolverDigest"]
            .as_str()
            .ok_or_else(|| err(format!("Formal model `{model_id}` missing resolverDigest")))?;
        require_sha256(resolver_digest, "formalModel.resolverDigest")?;
        if model["contextDigest"].as_str() != Some(expected_context_digest) {
            return Err(err(format!(
                "Stale formal model `{model_id}` rejected: contextDigest does not match current snapshot"
            )));
        }
        if model["proofClean"].as_bool() != Some(true) {
            return Err(err(format!(
                "Formal model `{model_id}` rejected: proofClean must be true (zero sorryAx/synthetic flags)"
            )));
        }
        if model["passed"].as_bool() != Some(true) {
            return Err(err(format!(
                "Formal model `{model_id}` rejected: mechanical verification did not pass"
            )));
        }
        if mode == "ephemeral-ai-overlay" {
            if model["countermodelVerified"].as_bool() != Some(true) {
                return Err(err(format!(
                    "Vacuous ephemeral-ai-overlay `{model_id}` rejected: MR05 @countermodel witness required"
                )));
            }
            if model["storedInSidecarVault"].as_bool() != Some(true) {
                return Err(err(format!(
                    "Ephemeral overlay `{model_id}` must stay in sidecar vault (zero upstream pollution)"
                )));
            }
            ephemeral_overlay_count += 1;
        } else {
            upstream_reuse_count += 1;
        }
        admitted_models.push(json!({
            "modelId": model_id,
            "mode": mode,
            "libraryPackage": lib_pkg,
            "resolverDigest": resolver_digest,
        }));
    }
    let formal_digest = crate::source_tree::sha256(serde_json::to_string(formal)?.as_bytes());
    Ok(json!({
        "schema": "lambda-aitia.de-formal-evidence-verdict.v1",
        "verified": true,
        "epistemicStatus": "Proven",
        "formalEvidenceDigest": formal_digest,
        "admittedFormalModels": admitted_models,
        "upstreamReuseCount": upstream_reuse_count,
        "ephemeralOverlayCount": ephemeral_overlay_count,
        "essentialGuardProbeCount": essential_probes,
        "actionAuthorized": false,
    }))
}

pub(crate) fn append_formal_org_section(report: &mut String, fv: &Value) {
    let _ = write!(
        report,
        "\n** Deterministic Engineering Formal Verification (RFC 0023)\n\
         :PROPERTIES:\n\
         :AITIA_SUPPORT: SWE-083 SWE-084 SWE-146\n\
         :END:\n\
         - Formal Evidence Digest: {}\n\
         - Upstream Library Reuse Count: {}\n\
         - Ephemeral AI Overlay Count: {}\n\
         - Essential Guard-Probes: {}\n",
        fv["formalEvidenceDigest"].as_str().unwrap_or("unknown"),
        fv["upstreamReuseCount"].as_u64().unwrap_or(0),
        fv["ephemeralOverlayCount"].as_u64().unwrap_or(0),
        fv["essentialGuardProbeCount"].as_u64().unwrap_or(0),
    );
}

/// Verify Deterministic Engineering formal library reuse (`upstream-library-reuse`),
/// project-specific ephemeral AI overlays (`ephemeral-ai-overlay` with mandatory MR05
/// `@countermodel` & sidecar vault isolation), G2 mechanical diff-delta defects, F3
/// Quint `guard-probe` verdicts, and explicit `PendingMethod` non-degradation (RFC 0023).
///
/// # Errors
/// Fails closed on vacuous ephemeral overlays, unresolved DE package resolvers, G2 defects,
/// redundant guard-probes, stale `contextDigest`, or unavailable `PendingMethod` oracles.
pub fn verify_de_formal_evidence_json(
    formal_evidence_json: &str,
    expected_context_digest: &str,
) -> Result<String> {
    require_sha256(expected_context_digest, "expectedContextDigest")?;
    let formal: Value = serde_json::from_str(formal_evidence_json)?;
    Ok(serde_json::to_string(&verify_formal_evidence(
        &formal,
        expected_context_digest,
    )?)?)
}
