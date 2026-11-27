// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Detached Sidecar Governance for Uninitialized External Repositories, Multi-Lens AI Audit
//! Verification, and NASA NPR 7150.2D Commit / Conversation Provenance (RFC 0021).
//!
//! Enables contributing to any ordinary Git repository without initializing `.agents/aita/`
//! inside the upstream tree. Freezes read-only diff + deterministic check context, verifies
//! multi-lens LLM audit provenance (`SWE-146`) and conversation transcript digests, enforces
//! independent human disposition of critical/high findings, and renders clean upstream commit
//! messages alongside detached NASA Org reports and wire-compatible DSSEv1 PAE in-toto/SLSA
//! envelopes. Never grants execution authority (`actionAuthorized: false`).

use super::dsse::{INTOTO_PAYLOAD_TYPE, base64_encode};
use super::{Result, err};
use ring::signature::{Ed25519KeyPair, KeyPair};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt::Write as _;
use std::path::Path;
use std::process::Command;

const SIDECAR_PROFILE_SCHEMA: &str = "lambda-aitia.sidecar-profile.v1";
const CONTEXT_SCHEMA: &str = "lambda-aitia.detached-audit-context.v1";
const AI_REPORT_SCHEMA: &str = "lambda-aitia.ai-audit-report.v1";
const CONVERSATION_SCHEMA: &str = "lambda-aitia.conversation-transcript.v1";
const HUMAN_DECISION_SCHEMA: &str = "lambda-aitia.human-audit-decision.v1";
const INTOTO_STATEMENT_TYPE: &str = "https://in-toto.io/Statement/v1";
const SLSA_PREDICATE_TYPE: &str = "https://slsa.dev/provenance/v1";
const SIDECAR_BUILD_TYPE: &str = "https://lambda-aitia.org/detached-sidecar-audit/v1";
const BUILDER_ID: &str = "https://lambda-aitia.org/aitia-runtime/v1";

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode<const N: usize>(value: &str) -> Result<[u8; N]> {
    if value.len() != N * 2 {
        return Err(err("Invalid sidecar hex encoding length"));
    }
    let mut out = [0u8; N];
    for (slot, pair) in out.iter_mut().zip(value.as_bytes().chunks_exact(2)) {
        let pair_str = std::str::from_utf8(pair).map_err(|_| err("Invalid UTF-8 in hex"))?;
        *slot =
            u8::from_str_radix(pair_str, 16).map_err(|_| err("Invalid hex digit in sidecar"))?;
    }
    Ok(out)
}

fn require_sha256(value: &str, label: &str) -> Result<String> {
    let hex = value
        .strip_prefix("sha256:")
        .ok_or_else(|| err(format!("{label} must be a sha256:-prefixed digest")))?;
    let _ = hex_decode::<32>(hex)?;
    Ok(hex.to_owned())
}

fn run_git(repo_dir: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo_dir)
        .output()
        .map_err(|e| err(format!("Failed to execute read-only git command: {e}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(err(format!(
            "Read-only git {:?} failed: {}",
            args,
            stderr.trim()
        )));
    }
    String::from_utf8(output.stdout)
        .map_err(|_| err("Read-only git output contained non-UTF-8 bytes"))
}

struct ParsedSidecarProfile {
    target_repo: String,
    nasa_profile: String,
    required_lenses: BTreeSet<String>,
    forbidden_prefixes: Vec<String>,
    commit_convention: String,
    allow_audit_trailer: bool,
    epoch: u64,
}

fn parse_profile(profile: &Value) -> Result<ParsedSidecarProfile> {
    if profile["schema"].as_str() != Some(SIDECAR_PROFILE_SCHEMA) {
        return Err(err("Unsupported sidecar profile schema"));
    }
    let target_repo = profile["targetRepo"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| err("Sidecar profile missing targetRepo"))?
        .to_owned();
    let nasa_profile = profile["nasaProfile"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| err("Sidecar profile missing nasaProfile"))?
        .to_owned();
    let required_lenses: BTreeSet<String> = profile["requiredAuditLenses"]
        .as_array()
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| err("Sidecar profile missing non-empty requiredAuditLenses"))?
        .iter()
        .map(|v| {
            v.as_str()
                .filter(|s| !s.is_empty())
                .map(str::to_owned)
                .ok_or_else(|| err("Sidecar profile lens must be a non-empty string"))
        })
        .collect::<Result<BTreeSet<String>>>()?;
    let forbidden_prefixes: Vec<String> = profile
        .get("forbiddenUpstreamPrefixes")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .filter(|v: &Vec<String>| !v.is_empty())
        .unwrap_or_else(|| vec![".agents/aita/".to_owned(), ".aitia/".to_owned()]);
    let commit_convention = profile
        .get("commitConvention")
        .and_then(Value::as_str)
        .unwrap_or("conventional-commits")
        .to_owned();
    let allow_audit_trailer = profile
        .get("allowAuditTrailer")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let epoch = profile.get("epoch").and_then(Value::as_u64).unwrap_or(1);
    if epoch == 0 {
        return Err(err("Sidecar profile epoch must be >= 1"));
    }
    Ok(ParsedSidecarProfile {
        target_repo,
        nasa_profile,
        required_lenses,
        forbidden_prefixes,
        commit_convention,
        allow_audit_trailer,
        epoch,
    })
}

/// Capture an immutable, read-only `AuditContextPack` from ANY uninitialized external Git
/// repository, enforcing zero upstream pollution and binding deterministic check receipts
/// (RFC 0021).
///
/// # Errors
/// Fails closed if `repo_dir` is not a valid Git repo, any changed/untracked path matches
/// `forbiddenUpstreamPrefixes`, there are zero changed files, or any required deterministic
/// check failed.
pub fn capture_detached_audit_context_json(
    repo_dir: &Path,
    base_ref: &str,
    profile_json: &str,
    deterministic_checks_json: &str,
) -> Result<String> {
    let profile_val: Value = serde_json::from_str(profile_json)?;
    let profile = parse_profile(&profile_val)?;
    let checks: Vec<Value> = serde_json::from_str(deterministic_checks_json)?;
    for check in &checks {
        let name = check["name"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| err("Deterministic check missing name"))?;
        let passed = check["passed"]
            .as_bool()
            .ok_or_else(|| err(format!("Deterministic check `{name}` missing passed bool")))?;
        if !passed {
            return Err(err(format!(
                "Deterministic check `{name}` failed; resolve deterministic checks before audit admission"
            )));
        }
    }

    let base_commit = run_git(repo_dir, &["rev-parse", base_ref])?
        .trim()
        .to_owned();
    let status_out = run_git(repo_dir, &["status", "--porcelain=v1", "-uall"])?;
    let mut changed_files: BTreeSet<String> = BTreeSet::new();
    for line in status_out.lines() {
        if line.len() < 4 {
            continue;
        }
        let raw_path = line[3..].trim();
        let clean_path = raw_path
            .rsplit_once(" -> ")
            .map_or(raw_path, |(_, dst)| dst)
            .trim_matches('"');
        if !clean_path.is_empty() {
            changed_files.insert(clean_path.to_owned());
        }
    }
    let tracked_names = run_git(repo_dir, &["diff", "--name-only", base_ref])?;
    for line in tracked_names.lines() {
        let p = line.trim();
        if !p.is_empty() {
            changed_files.insert(p.to_owned());
        }
    }
    if changed_files.is_empty() {
        return Err(err(
            "Detached external repository has no changed files relative to baseRef",
        ));
    }
    for path in &changed_files {
        for forbidden in &profile.forbidden_prefixes {
            if path.starts_with(forbidden) {
                return Err(err(format!(
                    "Upstream repository pollution blocked: `{path}` matches forbidden prefix `{forbidden}`"
                )));
            }
        }
    }

    let diff_text = run_git(repo_dir, &["diff", "--unified=3", base_ref])?;
    let mut untracked_payload = String::new();
    for path in &changed_files {
        let full = repo_dir.join(path);
        if full.is_file() {
            let content = std::fs::read_to_string(&full).unwrap_or_default();
            let _ = writeln!(
                untracked_payload,
                "FILE:{path}:{}",
                crate::source_tree::sha256(content.as_bytes())
            );
        }
    }
    let diff_digest = crate::source_tree::sha256(
        format!("{diff_text}\n---FILES---\n{untracked_payload}").as_bytes(),
    );
    let profile_digest =
        crate::source_tree::sha256(serde_json::to_string(&profile_val)?.as_bytes());
    let checks_digest = crate::source_tree::sha256(serde_json::to_string(&checks)?.as_bytes());
    let files_vec: Vec<String> = changed_files.into_iter().collect();

    let canonical_context_core = json!({
        "targetRepo": profile.target_repo,
        "baseRef": base_ref,
        "baseCommit": base_commit,
        "changedFiles": files_vec,
        "diffDigest": diff_digest,
        "deterministicChecksDigest": checks_digest,
        "profileDigest": profile_digest,
    });
    let context_digest =
        crate::source_tree::sha256(serde_json::to_string(&canonical_context_core)?.as_bytes());
    let required_lenses_vec: Vec<String> = profile.required_lenses.into_iter().collect();
    let nasa_obligations = json!(["SWE-083", "SWE-084", "SWE-087", "SWE-146"]);
    let ascent_directives = json!({
        "schema": "lambda-aitia.ascent-audit-directive.v1",
        "targetRepo": profile.target_repo,
        "nasaProfile": profile.nasa_profile,
        "contextDigest": context_digest,
        "obligations": nasa_obligations,
        "requiredLenses": required_lenses_vec,
        "invariants": [
            "epistemicStatus MUST equal \"hypothesized\"",
            "actionAuthorized MUST equal false",
            "every finding MUST cite a file in changedFiles with non-empty competingHypotheses",
            "openQuestions and contradictions MUST be preserved without probability collapse",
            "SWE-146 provider, modelId, and promptTemplateDigest MUST be recorded"
        ],
    });
    let ai_engine_handoffs = json!({
        "nativeHostLlm": {
            "engineBinding": "native-ai-environment",
            "schema": "lambda-aitia.native-ai-audit-handoff.v1",
            "ascentDirective": ascent_directives,
            "actionAuthorized": false,
        },
        "marlinAgentCore": {
            "engineBinding": "marlin-agent-core",
            "schema": "lambda-aitia.marlin-audit-handoff.v1",
            "boundary": "marlin-agent-core",
            "capability": "marlin.agent.audit-detached-diff",
            "contextDigest": context_digest,
            "ascentDirective": ascent_directives,
            "actionAuthorized": false,
        },
    });

    Ok(serde_json::to_string(&json!({
        "schema": CONTEXT_SCHEMA,
        "targetRepo": profile.target_repo,
        "nasaProfile": profile.nasa_profile,
        "baseRef": base_ref,
        "baseCommit": base_commit,
        "changedFiles": files_vec,
        "diffDigest": diff_digest,
        "diffExcerpt": diff_text,
        "deterministicChecks": checks,
        "deterministicChecksDigest": checks_digest,
        "profileDigest": profile_digest,
        "contextDigest": context_digest,
        "aiEngineHandoffs": ai_engine_handoffs,
        "upstreamPollutionFree": true,
        "actionAuthorized": false,
    }))?)
}

fn verify_sidecar_audit_values(
    context: &Value,
    ai_reports: &[Value],
    conversation: &Value,
    human_decision: &Value,
    profile: &ParsedSidecarProfile,
) -> Result<Value> {
    if context["schema"].as_str() != Some(CONTEXT_SCHEMA)
        || context["actionAuthorized"].as_bool() != Some(false)
        || context["upstreamPollutionFree"].as_bool() != Some(true)
    {
        return Err(err("Invalid detached audit context pack"));
    }
    let context_digest = context["contextDigest"]
        .as_str()
        .ok_or_else(|| err("Audit context missing contextDigest"))?;
    let _ = require_sha256(context_digest, "contextDigest")?;
    let changed_files: BTreeSet<String> = context["changedFiles"]
        .as_array()
        .ok_or_else(|| err("Audit context missing changedFiles"))?
        .iter()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect();

    if ai_reports.is_empty() {
        return Err(err("At least one multi-lens AI audit report is required"));
    }
    let mut covered_lenses: BTreeSet<String> = BTreeSet::new();
    let mut engine_bindings: BTreeSet<String> = BTreeSet::new();
    let mut models_used: BTreeSet<String> = BTreeSet::new();
    let mut high_critical_ids: BTreeSet<String> = BTreeSet::new();
    let mut total_findings = 0usize;
    let mut total_hypotheses = 0usize;
    let mut preserved_open_questions: Vec<Value> = Vec::new();
    let mut preserved_contradictions: Vec<Value> = Vec::new();

    for report in ai_reports {
        if report["schema"].as_str() != Some(AI_REPORT_SCHEMA) {
            return Err(err("Unsupported AI audit report schema"));
        }
        if report["actionAuthorized"].as_bool() != Some(false) {
            return Err(err("AI audit report must declare actionAuthorized=false"));
        }
        if report["epistemicStatus"].as_str() != Some("hypothesized") {
            return Err(err(
                "AI audit report must declare epistemicStatus=\"hypothesized\" (AI cannot self-admit)",
            ));
        }
        let engine_binding = report["engineBinding"]
            .as_str()
            .filter(|b| matches!(*b, "native-ai-environment" | "marlin-agent-core"))
            .ok_or_else(|| {
                err(
                    "AI audit report must use sanctioned engineBinding (\"native-ai-environment\" or \"marlin-agent-core\")",
                )
            })?;
        engine_bindings.insert(engine_binding.to_owned());
        if report["contextDigest"].as_str() != Some(context_digest) {
            return Err(err(
                "Stale AI audit report rejected: contextDigest does not match current code snapshot",
            ));
        }
        let provider = report["provider"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| err("AI audit report missing SWE-146 provider"))?;
        let model_id = report["modelId"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| err("AI audit report missing SWE-146 modelId"))?;
        let prompt_digest = report["promptTemplateDigest"]
            .as_str()
            .ok_or_else(|| err("AI audit report missing SWE-146 promptTemplateDigest"))?;
        let _ = require_sha256(prompt_digest, "promptTemplateDigest")?;
        let lens = report["lens"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| err("AI audit report missing lens"))?;
        covered_lenses.insert(lens.to_owned());
        models_used.insert(format!("{provider}/{model_id}"));

        let findings = report["findings"]
            .as_array()
            .ok_or_else(|| err("AI audit report missing findings array"))?;
        for finding in findings {
            let fid = finding["id"]
                .as_str()
                .filter(|s| !s.is_empty())
                .ok_or_else(|| err("AI finding missing id"))?;
            let file = finding["file"]
                .as_str()
                .ok_or_else(|| err(format!("AI finding `{fid}` missing file")))?;
            if !changed_files.contains(file) {
                return Err(err(format!(
                    "AI finding `{fid}` cites `{file}` which is not in frozen changedFiles"
                )));
            }
            let _ = finding["evidenceExcerpt"]
                .as_str()
                .filter(|s| !s.is_empty())
                .ok_or_else(|| err(format!("AI finding `{fid}` missing evidenceExcerpt")))?;
            let severity = finding["severity"]
                .as_str()
                .ok_or_else(|| err(format!("AI finding `{fid}` missing severity")))?;
            if !matches!(severity, "critical" | "high" | "medium" | "low" | "info") {
                return Err(err(format!(
                    "AI finding `{fid}` has invalid severity `{severity}`"
                )));
            }
            let hyps = finding["competingHypotheses"]
                .as_array()
                .filter(|arr| !arr.is_empty())
                .ok_or_else(|| {
                    err(format!(
                        "AI finding `{fid}` must preserve non-empty competingHypotheses"
                    ))
                })?;
            total_hypotheses += hyps.len();
            total_findings += 1;
            if matches!(severity, "critical" | "high") {
                high_critical_ids.insert(fid.to_owned());
            }
        }
        if let Some(oq) = report.get("openQuestions").and_then(Value::as_array) {
            preserved_open_questions.extend(oq.iter().cloned());
        }
        if let Some(ct) = report.get("contradictions").and_then(Value::as_array) {
            preserved_contradictions.extend(ct.iter().cloned());
        }
    }

    for req_lens in &profile.required_lenses {
        if !covered_lenses.contains(req_lens) {
            return Err(err(format!(
                "Required AI audit lens `{req_lens}` is missing"
            )));
        }
    }

    if conversation["schema"].as_str() != Some(CONVERSATION_SCHEMA)
        || conversation["actionAuthorized"].as_bool() != Some(false)
    {
        return Err(err("Invalid conversation audit transcript schema or flags"));
    }
    if conversation["contextDigest"].as_str() != Some(context_digest) {
        return Err(err(
            "Conversation transcript contextDigest does not match current code snapshot",
        ));
    }
    let redaction_mode = conversation["redactionMode"]
        .as_str()
        .filter(|m| matches!(*m, "full" | "redacted-summary" | "digest-only"))
        .ok_or_else(|| err("Conversation transcript has invalid redactionMode"))?;
    let turns = conversation["turns"]
        .as_array()
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| err("Conversation transcript must contain at least one turn"))?;
    for turn in turns {
        let role = turn["role"]
            .as_str()
            .filter(|r| matches!(*r, "human" | "assistant" | "tool"))
            .ok_or_else(|| err("Conversation turn has invalid role"))?;
        let cd = turn["contentDigest"]
            .as_str()
            .ok_or_else(|| err("Conversation turn missing contentDigest"))?;
        let _ = require_sha256(cd, "turn.contentDigest")?;
        if role == "assistant" && turn["modelId"].as_str().is_none_or(|m| m.trim().is_empty()) {
            return Err(err(
                "Assistant conversation turn missing SWE-146 modelId provenance",
            ));
        }
    }
    let conversation_digest =
        crate::source_tree::sha256(serde_json::to_string(conversation)?.as_bytes());
    let ai_audit_digest = crate::source_tree::sha256(serde_json::to_string(ai_reports)?.as_bytes());

    if human_decision["schema"].as_str() != Some(HUMAN_DECISION_SCHEMA)
        || human_decision["actionAuthorized"].as_bool() != Some(false)
    {
        return Err(err("Invalid human audit decision schema or flags"));
    }
    if human_decision["contextDigest"].as_str() != Some(context_digest) {
        return Err(err(
            "Human audit decision contextDigest is stale (does not match current snapshot)",
        ));
    }
    if human_decision["conversationDigest"].as_str() != Some(conversation_digest.as_str()) {
        return Err(err(
            "Human audit decision does not bind the verified conversationDigest",
        ));
    }
    let reviewer_id = human_decision["reviewerId"]
        .as_str()
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| err("Human audit decision missing independent reviewerId (SWE-087)"))?;
    if human_decision["decision"].as_str() != Some("approve-commit") {
        return Err(err(
            "Human audit decision did not approve commit (AI cannot self-approve)",
        ));
    }
    let disp_map: BTreeMap<String, (&str, &str)> = human_decision
        .get("dispositions")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .map(|d| {
                    let fid = d["findingId"]
                        .as_str()
                        .ok_or_else(|| err("Human disposition missing findingId"))?;
                    let status = d["status"]
                        .as_str()
                        .filter(|s| matches!(*s, "fixed-verified" | "waived-with-rationale"))
                        .ok_or_else(|| {
                            err(format!("Human disposition for `{fid}` has invalid status"))
                        })?;
                    let rationale = d["rationale"]
                        .as_str()
                        .filter(|s| !s.trim().is_empty())
                        .ok_or_else(|| {
                            err(format!("Human disposition for `{fid}` missing rationale"))
                        })?;
                    Ok((fid.to_owned(), (status, rationale)))
                })
                .collect::<Result<BTreeMap<String, (&str, &str)>>>()
        })
        .transpose()?
        .unwrap_or_default();

    for fid in &high_critical_ids {
        if !disp_map.contains_key(fid) {
            return Err(err(format!(
                "Unaddressed critical/high AI finding `{fid}` blocks NASA commit admission"
            )));
        }
    }

    Ok(json!({
        "schema": "lambda-aitia.sidecar-audit-verdict.v1",
        "verified": true,
        "targetRepo": profile.target_repo,
        "nasaProfile": profile.nasa_profile,
        "contextDigest": context_digest,
        "aiAuditDigest": ai_audit_digest,
        "conversationDigest": conversation_digest,
        "conversationRedactionMode": redaction_mode,
        "conversationTurnCount": turns.len(),
        "reviewerId": reviewer_id,
        "engineBindingsUsed": engine_bindings.into_iter().collect::<Vec<String>>(),
        "lensesCovered": covered_lenses.into_iter().collect::<Vec<String>>(),
        "modelsUsed": models_used.into_iter().collect::<Vec<String>>(),
        "findingCount": total_findings,
        "addressedHighCriticalCount": high_critical_ids.len(),
        "preservedCompetingHypothesesCount": total_hypotheses,
        "preservedOpenQuestions": preserved_open_questions,
        "preservedContradictions": preserved_contradictions,
        "nasaObligationsSupported": ["SWE-083", "SWE-084", "SWE-087", "SWE-146"],
        "actionAuthorized": false,
    }))
}

/// Verify multi-lens AI audit reports, SWE-146 model/prompt provenance, conversation transcript
/// integrity, and independent human dispositions against a frozen detached `AuditContextPack`
/// (RFC 0021).
///
/// # Errors
/// Fails closed on stale `contextDigest`, missing required lenses, missing `SWE-146` provenance,
/// unaddressed critical/high findings, missing conversation binding, or missing human approval.
pub fn verify_ai_audit_and_conversation_json(
    context_json: &str,
    ai_reports_json: &str,
    conversation_json: &str,
    human_decision_json: &str,
    profile_json: &str,
) -> Result<String> {
    let context: Value = serde_json::from_str(context_json)?;
    let ai_reports: Vec<Value> = serde_json::from_str(ai_reports_json)?;
    let conversation: Value = serde_json::from_str(conversation_json)?;
    let human_decision: Value = serde_json::from_str(human_decision_json)?;
    let profile_val: Value = serde_json::from_str(profile_json)?;
    let profile = parse_profile(&profile_val)?;
    Ok(serde_json::to_string(&verify_sidecar_audit_values(
        &context,
        &ai_reports,
        &conversation,
        &human_decision,
        &profile,
    )?)?)
}

fn format_upstream_commit(
    proposal: &Value,
    profile: &ParsedSidecarProfile,
    receipt_digest: &str,
) -> Result<String> {
    let summary = proposal["summary"]
        .as_str()
        .filter(|s| !s.trim().is_empty() && !s.contains('\n'))
        .ok_or_else(|| err("Commit proposal missing single-line summary"))?;
    let headline = if profile.commit_convention == "conventional-commits" {
        let kind = proposal["type"]
            .as_str()
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| err("Conventional commit proposal missing type"))?;
        match proposal.get("scope").and_then(Value::as_str) {
            Some(scope) if !scope.trim().is_empty() => format!("{kind}({scope}): {summary}"),
            _ => format!("{kind}: {summary}"),
        }
    } else {
        summary.to_owned()
    };
    if headline.len() > 72 {
        return Err(err(format!(
            "Upstream commit headline exceeds 72 chars ({} chars)",
            headline.len()
        )));
    }
    let body = proposal
        .get("body")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    let mut message = headline;
    if !body.is_empty() {
        message.push_str("\n\n");
        message.push_str(body);
    }
    if profile.allow_audit_trailer {
        message.push_str("\n\nAudit-Receipt: ");
        message.push_str(receipt_digest);
    }
    message.push('\n');
    Ok(message)
}

fn render_nasa_org_report(
    context: &Value,
    verdict: &Value,
    receipt_digest: &str,
    upstream_headline: &str,
) -> String {
    let target = verdict["targetRepo"].as_str().unwrap_or("unknown");
    let nasa_profile = verdict["nasaProfile"].as_str().unwrap_or("npr-7150.2d");
    let base_commit = context["baseCommit"].as_str().unwrap_or("unknown");
    let diff_digest = context["diffDigest"].as_str().unwrap_or("unknown");
    let reviewer = verdict["reviewerId"].as_str().unwrap_or("unknown");
    let conv_digest = verdict["conversationDigest"].as_str().unwrap_or("unknown");
    let ai_digest = verdict["aiAuditDigest"].as_str().unwrap_or("unknown");
    let models = verdict["modelsUsed"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let lenses = verdict["lensesCovered"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    format!(
        "* Detached Sidecar NASA Audit Receipt: {target}\n\
         :PROPERTIES:\n\
         :AITIA_RECEIPT_DIGEST: {receipt_digest}\n\
         :AITIA_NASA_PROFILE: {nasa_profile}\n\
         :AITIA_ACTION_AUTHORIZED: false\n\
         :END:\n\n\
         ** Change Identification (SWE-083)\n\
         :PROPERTIES:\n\
         :AITIA_SUPPORT: SWE-083\n\
         :END:\n\
         - Upstream Headline: {upstream_headline}\n\
         - Base Commit: {base_commit}\n\
         - Frozen Diff Digest: {diff_digest}\n\n\
         ** Configuration & Zero-Pollution Audit (SWE-084)\n\
         :PROPERTIES:\n\
         :AITIA_SUPPORT: SWE-084\n\
         :END:\n\
         - Upstream Pollution Free: true\n\
         - Context Digest: {}\n\n\
         ** Independent Human Review (SWE-087)\n\
         :PROPERTIES:\n\
         :AITIA_SUPPORT: SWE-087\n\
         :END:\n\
         - Reviewer: {reviewer}\n\
         - High/Critical Findings Addressed: {}\n\
         - Competing Hypotheses Preserved: {}\n\n\
         ** AI-Assisted Source & Conversation Provenance (SWE-146)\n\
         :PROPERTIES:\n\
         :AITIA_SUPPORT: SWE-146\n\
         :END:\n\
         - Audit Lenses: {lenses}\n\
         - Models Used: {models}\n\
         - AI Audit Bundle Digest: {ai_digest}\n\
         - Conversation Transcript Digest: {conv_digest}\n",
        verdict["contextDigest"].as_str().unwrap_or("unknown"),
        verdict["addressedHighCriticalCount"].as_u64().unwrap_or(0),
        verdict["preservedCompetingHypothesesCount"]
            .as_u64()
            .unwrap_or(0),
    )
}

fn mint_sidecar_dsse(
    context: &Value,
    verdict: &Value,
    profile: &ParsedSidecarProfile,
    receipt_digest: &str,
    org_report: &str,
    signing_seeds: &[String],
) -> Result<Value> {
    if signing_seeds.is_empty() {
        return Err(err(
            "Sidecar DSSE signing requires at least one Ed25519 seed",
        ));
    }
    let receipt_hex = require_sha256(receipt_digest, "receiptDigest")?;
    let diff_hex = require_sha256(
        context["diffDigest"]
            .as_str()
            .ok_or_else(|| err("Context missing diffDigest"))?,
        "diffDigest",
    )?;
    let conv_hex = require_sha256(
        verdict["conversationDigest"]
            .as_str()
            .ok_or_else(|| err("Verdict missing conversationDigest"))?,
        "conversationDigest",
    )?;
    let ai_hex = require_sha256(
        verdict["aiAuditDigest"]
            .as_str()
            .ok_or_else(|| err("Verdict missing aiAuditDigest"))?,
        "aiAuditDigest",
    )?;
    let org_digest = crate::source_tree::sha256(org_report.as_bytes());
    let org_hex = require_sha256(&org_digest, "orgReportDigest")?;

    let statement = json!({
        "_type": INTOTO_STATEMENT_TYPE,
        "subject": [
            { "name": "lambda-aitia.sidecar-receipt", "digest": { "sha256": receipt_hex } },
            { "name": format!("{}:diff", profile.target_repo), "digest": { "sha256": diff_hex } },
            { "name": "lambda-aitia.conversation-transcript", "digest": { "sha256": conv_hex } },
            { "name": "lambda-aitia.ai-audit-bundle", "digest": { "sha256": ai_hex } },
            { "name": "lambda-aitia.nasa-org-report", "digest": { "sha256": org_hex } },
        ],
        "predicateType": SLSA_PREDICATE_TYPE,
        "predicate": {
            "buildDefinition": {
                "buildType": SIDECAR_BUILD_TYPE,
                "externalParameters": {
                    "targetRepo": profile.target_repo,
                    "nasaProfile": profile.nasa_profile,
                    "baseCommit": context["baseCommit"],
                    "epoch": profile.epoch,
                    "merkleRoot": Value::Null,
                    "lensesCovered": verdict["lensesCovered"],
                    "modelsUsed": verdict["modelsUsed"],
                    "nasaObligationsSupported": verdict["nasaObligationsSupported"],
                },
                "resolvedDependencies": context["changedFiles"],
            },
            "runDetails": {
                "builder": { "id": BUILDER_ID },
                "metadata": {
                    "schema": "lambda-aitia.nasa-sidecar-commit-bundle.v1",
                    "bundleDigest": receipt_digest,
                    "reviewerId": verdict["reviewerId"],
                    "actionAuthorized": false,
                },
            },
        },
    });
    let payload_bytes = serde_json::to_vec(&statement)?;
    let pae_header = format!(
        "DSSEv1 {} {} {} ",
        INTOTO_PAYLOAD_TYPE.len(),
        INTOTO_PAYLOAD_TYPE,
        payload_bytes.len()
    );
    let mut pae = Vec::with_capacity(pae_header.len() + payload_bytes.len());
    pae.extend_from_slice(pae_header.as_bytes());
    pae.extend_from_slice(&payload_bytes);

    let mut sigs: Vec<(String, String)> = Vec::with_capacity(signing_seeds.len());
    for seed_hex in signing_seeds {
        let seed = hex_decode::<32>(seed_hex)?;
        let kp = Ed25519KeyPair::from_seed_unchecked(&seed)
            .map_err(|_| err("Failed to construct Ed25519 keypair for sidecar DSSE"))?;
        let sig = kp.sign(&pae);
        sigs.push((
            format!("ed25519:{}", hex_encode(kp.public_key().as_ref())),
            base64_encode(sig.as_ref()),
        ));
    }
    sigs.sort_by(|a, b| a.0.cmp(&b.0));
    let sig_entries: Vec<Value> = sigs
        .into_iter()
        .map(|(keyid, sig)| json!({ "keyid": keyid, "sig": sig }))
        .collect();

    Ok(json!({
        "payloadType": INTOTO_PAYLOAD_TYPE,
        "payload": base64_encode(&payload_bytes),
        "signatures": sig_entries,
    }))
}

/// Build a verified dual-surface NASA Sidecar Commit Bundle (`upstreamCommitMessage` +
/// `nasaOrgReport` + optional RFC 0019 wire-compatible DSSEv1 PAE in-toto/SLSA envelope)
/// for an external uninitialized Git repository (RFC 0021).
///
/// # Errors
/// Fails closed if audit/conversation verification fails, the upstream commit headline violates
/// length/convention constraints, or Ed25519 signing seeds are malformed.
pub fn build_nasa_sidecar_receipt_json(spec_json: &str) -> Result<String> {
    let spec: Value = serde_json::from_str(spec_json)?;
    let context = spec
        .get("context")
        .ok_or_else(|| err("Sidecar receipt spec missing context"))?;
    let ai_reports: Vec<Value> = serde_json::from_value(
        spec.get("aiReports")
            .cloned()
            .ok_or_else(|| err("Sidecar receipt spec missing aiReports"))?,
    )?;
    let conversation = spec
        .get("conversation")
        .ok_or_else(|| err("Sidecar receipt spec missing conversation"))?;
    let human_decision = spec
        .get("humanDecision")
        .ok_or_else(|| err("Sidecar receipt spec missing humanDecision"))?;
    let profile_val = spec
        .get("profile")
        .ok_or_else(|| err("Sidecar receipt spec missing profile"))?;
    let proposal = spec
        .get("commitProposal")
        .ok_or_else(|| err("Sidecar receipt spec missing commitProposal"))?;
    let profile = parse_profile(profile_val)?;

    let verdict =
        verify_sidecar_audit_values(context, &ai_reports, conversation, human_decision, &profile)?;
    let receipt_core = json!({
        "contextDigest": verdict["contextDigest"],
        "aiAuditDigest": verdict["aiAuditDigest"],
        "conversationDigest": verdict["conversationDigest"],
        "reviewerId": verdict["reviewerId"],
        "commitProposal": proposal,
        "actionAuthorized": false,
    });
    let receipt_digest =
        crate::source_tree::sha256(serde_json::to_string(&receipt_core)?.as_bytes());
    let upstream_commit_message = format_upstream_commit(proposal, &profile, &receipt_digest)?;
    let upstream_headline = upstream_commit_message.lines().next().unwrap_or("");
    let nasa_org_report =
        render_nasa_org_report(context, &verdict, &receipt_digest, upstream_headline);

    let dsse_envelope = if let Some(seeds_val) = spec.get("signingSeeds").filter(|v| !v.is_null()) {
        let seeds: Vec<String> = serde_json::from_value(seeds_val.clone())?;
        Some(mint_sidecar_dsse(
            context,
            &verdict,
            &profile,
            &receipt_digest,
            &nasa_org_report,
            &seeds,
        )?)
    } else {
        None
    };

    Ok(serde_json::to_string(&json!({
        "schema": "lambda-aitia.nasa-sidecar-commit-bundle.v1",
        "receiptDigest": receipt_digest,
        "targetRepo": profile.target_repo,
        "baseCommit": context["baseCommit"],
        "upstreamCommitMessage": upstream_commit_message,
        "nasaOrgReport": nasa_org_report,
        "verdict": verdict,
        "dsseEnvelope": dsse_envelope,
        "actionAuthorized": false,
    }))?)
}
