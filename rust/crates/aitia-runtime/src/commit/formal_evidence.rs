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
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

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

static QUINT_VAULT_COUNTER: AtomicU64 = AtomicU64::new(1);
const MAX_QUINT_OVERLAY_BYTES: usize = 128 * 1024;
const QUINT_TIMEOUT_SECS: u64 = 25;

struct EphemeralVaultDir(PathBuf);

impl Drop for EphemeralVaultDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn sanitize_quint_basename(raw: Option<&str>) -> String {
    let base = raw.unwrap_or("EphemeralOverlay.qnt").trim();
    let stem = base.strip_suffix(".qnt").unwrap_or(base);
    let cleaned: String = stem
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-'))
        .take(48)
        .collect();
    if cleaned.is_empty() {
        "EphemeralOverlay.qnt".to_owned()
    } else {
        format!("{cleaned}.qnt")
    }
}

fn extract_quint_extends(source: &str) -> Option<String> {
    for line in source.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("// @quint-extends") {
            let model = rest.trim().split_whitespace().next().unwrap_or("");
            if !model.is_empty() {
                return Some(model.to_owned());
            }
        }
    }
    None
}

fn resolve_quint_binary() -> Option<PathBuf> {
    if let Some(explicit) = std::env::var_os("AITIA_QUINT_BIN").filter(|v| !v.is_empty()) {
        let p = PathBuf::from(explicit);
        if p.is_file() {
            return Some(p);
        }
    }
    for candidate in [
        Path::new("/opt/homebrew/bin/quint"),
        Path::new("/usr/local/bin/quint"),
        Path::new("dev/proof/quint/node_modules/.bin/quint"),
    ] {
        if candidate.is_file() {
            return Some(candidate.to_path_buf());
        }
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in std::env::split_paths(&path_var) {
            let cand = dir.join("quint");
            if cand.is_file() {
                return Some(cand);
            }
        }
    }
    None
}

fn run_bounded_quint_cmd(
    quint_bin: &Path,
    args: &[&str],
    workdir: &Path,
) -> std::io::Result<(bool, String)> {
    let mut cmd = Command::new(quint_bin);
    cmd.args(args)
        .current_dir(workdir)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env_remove("NODE_OPTIONS")
        .env_remove("GIT_DIR")
        .env_remove("GIT_WORK_TREE")
        .env_remove("GIT_INDEX_FILE");
    let mut child = cmd.spawn()?;
    let deadline = Instant::now() + Duration::from_secs(QUINT_TIMEOUT_SECS);
    loop {
        if let Some(_status) = child.try_wait()? {
            let output = child.wait_with_output()?;
            let mut combined = String::from_utf8_lossy(&output.stdout).into_owned();
            if !output.stderr.is_empty() {
                if !combined.is_empty() {
                    combined.push('\n');
                }
                combined.push_str(&String::from_utf8_lossy(&output.stderr));
            }
            return Ok((output.status.success(), combined));
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Ok((
                false,
                format!("quint timed out after {QUINT_TIMEOUT_SECS}s"),
            ));
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn parse_quint_passed_tests(output: &str) -> (Vec<String>, bool) {
    let mut passed = Vec::new();
    let mut has_failing = false;
    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.contains("failing") {
            has_failing = true;
        }
        if let Some(rest) = trimmed.strip_prefix("ok ")
            && let Some((name, _)) = rest.split_once(" passed")
        {
            let clean = name.trim();
            if !clean.is_empty() {
                passed.push(clean.to_owned());
            }
        }
    }
    (passed, has_failing)
}

/// Machine-execute an LLM-authored Quint 0.33 ephemeral overlay strictly inside an isolated
/// temporary sidecar vault (never touching the upstream Git repo) and enforce MR05 non-vacuous
/// `@countermodel` verification. Never grants execution authority (`actionAuthorized: false`).
pub(crate) fn run_ephemeral_quint_overlay(
    source: &str,
    overlay_name: Option<&str>,
    context_digest: &str,
) -> Value {
    let model_id = sanitize_quint_basename(overlay_name);
    let extends_model = extract_quint_extends(source);
    let source_digest = crate::source_tree::sha256(source.as_bytes());
    let cm_annotation = source.contains("@countermodel");

    if source.len() > MAX_QUINT_OVERLAY_BYTES {
        return json!({
            "schema": "lambda-aitia.quint-overlay-execution.v1",
            "modelId": model_id,
            "extendsModel": extends_model,
            "mode": "ephemeral-ai-overlay",
            "libraryPackage": "@deterministic-engineering/quint-models",
            "storedInSidecarVault": true,
            "machineExecuted": false,
            "typecheckPassed": false,
            "testsPassed": false,
            "passingTestCount": 0,
            "countermodelAnnotationFound": cm_annotation,
            "countermodelTestFound": false,
            "countermodelVerified": false,
            "passed": false,
            "resolverDigest": source_digest,
            "contextDigest": context_digest,
            "diagnostics": ["Quint overlay source exceeds 128 KiB safety bound"],
            "actionAuthorized": false,
        });
    }

    let Some(quint_bin) = resolve_quint_binary() else {
        return json!({
            "schema": "lambda-aitia.quint-overlay-execution.v1",
            "modelId": model_id,
            "extendsModel": extends_model,
            "mode": "ephemeral-ai-overlay",
            "libraryPackage": "@deterministic-engineering/quint-models",
            "storedInSidecarVault": true,
            "machineExecuted": false,
            "pendingOracle": "quint",
            "typecheckPassed": false,
            "testsPassed": false,
            "passingTestCount": 0,
            "countermodelAnnotationFound": cm_annotation,
            "countermodelTestFound": false,
            "countermodelVerified": false,
            "passed": false,
            "resolverDigest": source_digest,
            "contextDigest": context_digest,
            "diagnostics": ["PendingMethod: local `quint` binary unavailable (set AITIA_QUINT_BIN or install quint)"],
            "actionAuthorized": false,
        });
    };

    let seq = QUINT_VAULT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let vault_dir =
        std::env::temp_dir().join(format!("aitia-quint-vault-{}-{seq}", std::process::id()));
    if let Err(e) = fs::create_dir_all(&vault_dir) {
        return json!({
            "schema": "lambda-aitia.quint-overlay-execution.v1",
            "modelId": model_id,
            "mode": "ephemeral-ai-overlay",
            "libraryPackage": "@deterministic-engineering/quint-models",
            "storedInSidecarVault": true,
            "machineExecuted": false,
            "passed": false,
            "countermodelVerified": false,
            "resolverDigest": source_digest,
            "contextDigest": context_digest,
            "diagnostics": [format!("Failed to create isolated sidecar vault: {e}")],
            "actionAuthorized": false,
        });
    }
    let _guard = EphemeralVaultDir(vault_dir.clone());
    let qnt_path = vault_dir.join(&model_id);
    if let Err(e) = fs::write(&qnt_path, source) {
        return json!({
            "schema": "lambda-aitia.quint-overlay-execution.v1",
            "modelId": model_id,
            "mode": "ephemeral-ai-overlay",
            "libraryPackage": "@deterministic-engineering/quint-models",
            "storedInSidecarVault": true,
            "machineExecuted": false,
            "passed": false,
            "countermodelVerified": false,
            "resolverDigest": source_digest,
            "contextDigest": context_digest,
            "diagnostics": [format!("Failed to write Quint overlay in sidecar vault: {e}")],
            "actionAuthorized": false,
        });
    }

    let qnt_str = qnt_path.to_string_lossy().into_owned();
    let (tc_ok, tc_out) = run_bounded_quint_cmd(&quint_bin, &["typecheck", &qnt_str], &vault_dir)
        .unwrap_or_else(|e| (false, format!("failed to spawn quint typecheck: {e}")));
    let mut diagnostics: Vec<String> = Vec::new();
    let (tests_ok, passed_tests) = if tc_ok {
        let (ok, out) = run_bounded_quint_cmd(
            &quint_bin,
            &["test", "--backend=typescript", &qnt_str],
            &vault_dir,
        )
        .unwrap_or_else(|e| (false, format!("failed to spawn quint test: {e}")));
        let (names, has_failing) = parse_quint_passed_tests(&out);
        if !ok || has_failing {
            diagnostics.push(out.chars().take(1200).collect());
        }
        (ok && !has_failing, names)
    } else {
        diagnostics.push(tc_out.chars().take(1200).collect());
        (false, Vec::new())
    };

    let cm_test_found = passed_tests
        .iter()
        .any(|name| name.to_ascii_lowercase().contains("countermodel"));
    let has_positive_and_cm = passed_tests.len() >= 2 && cm_test_found;
    if tc_ok && tests_ok && !cm_annotation {
        diagnostics.push(
            "MR05 fail-closed: add `// @countermodel` annotation to prove non-vacuous overlay"
                .to_owned(),
        );
    }
    if tc_ok && tests_ok && !has_positive_and_cm {
        diagnostics.push(
            "MR05 fail-closed: overlay must pass >= 2 Quint `run ...Test` traces including at least one `*Countermodel*Test` negative-control trace"
                .to_owned(),
        );
    }

    let cm_verified = tc_ok && tests_ok && cm_annotation && has_positive_and_cm;
    let passed = cm_verified;
    let resolver_digest = crate::source_tree::sha256(
        format!("quint-overlay-v1:{model_id}:{source_digest}").as_bytes(),
    );

    json!({
        "schema": "lambda-aitia.quint-overlay-execution.v1",
        "modelId": model_id,
        "extendsModel": extends_model,
        "mode": "ephemeral-ai-overlay",
        "libraryPackage": "@deterministic-engineering/quint-models",
        "storedInSidecarVault": true,
        "machineExecuted": true,
        "typecheckPassed": tc_ok,
        "testsPassed": tests_ok,
        "passingTestCount": passed_tests.len(),
        "passingTests": passed_tests,
        "countermodelAnnotationFound": cm_annotation,
        "countermodelTestFound": cm_test_found,
        "countermodelVerified": cm_verified,
        "passed": passed,
        "resolverDigest": resolver_digest,
        "contextDigest": context_digest,
        "diagnostics": diagnostics,
        "actionAuthorized": false,
    })
}
