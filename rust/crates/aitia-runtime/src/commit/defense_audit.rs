// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Ultra-thin Rust `gix` + `jj-lib` transport adapter for the Scheme-driven POO Subdomain
//! Rule-Pack, DE G2 Anti-Defensive-Programming, and Temporal Causality engine
//! (`modules/gitops/diff-governance.ss`).
//!
//! Rust provides the native VCS ecosystem (`gix` repository/worktree/ref/OID resolution,
//! `jj-lib` workspace-cut observation, and SM32-neutralized diff capture) while Scheme POO +
//! ASCENT owns 100% of governance rules, subdomain rule packs, causal trajectories, and
//! temporal causality. Never grants execution authority (`actionAuthorized: false`).

#![forbid(unsafe_code)]

use super::{Result, err};
use crate::AitiaSession;
use serde_json::{Value, json};
use std::path::Path;

/// Read-only `gix` + `jj-lib` repository observation and unified diff capture across all active
/// surfaces, routed straight to the Scheme POO rule-pack & temporal causality engine.
///
/// Always audits `staged` (`git diff --cached`), `unstaged` (`git diff`), and — whenever
/// `base_ref != "HEAD"` and `!staged_only` — `base-ref` (`git diff <gix_base_commit>..HEAD`)
/// without silently skipping `base_ref` on dirty working trees.
pub(crate) fn audit_git_repo_defense_with_packs(
    repo_dir: &Path,
    base_ref: &str,
    staged_only: bool,
    rule_packs: &[Value],
    funflow_receipts: &[Value],
    session_opt: Option<&AitiaSession>,
) -> Result<Value> {
    let vcs = aitia_jj::observe_vcs_sidecar_state(repo_dir, base_ref)
        .map_err(|e| err(format!("gix/jj-lib VCS observation failed: {e}")))?;

    let staged_diff =
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--cached", "--unified=3"])
            .map_err(|e| err(e.to_string()))?;
    let unstaged_diff = if staged_only {
        String::new()
    } else {
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--unified=3"])
            .map_err(|e| err(e.to_string()))?
    };
    let base_ref_diff = if !staged_only && vcs.base_commit != vcs.head_commit {
        let range = format!("{}..{}", vcs.base_commit, vcs.head_commit);
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--unified=3", &range])
            .map_err(|e| err(e.to_string()))?
    } else {
        String::new()
    };

    let request = json!({
        "baseRef": base_ref,
        "stagedOnly": staged_only,
        "stagedDiff": staged_diff,
        "unstagedDiff": unstaged_diff,
        "baseRefDiff": base_ref_diff,
        "rulePacks": rule_packs,
        "funflowReceipts": funflow_receipts,
    });
    let req_str = serde_json::to_string(&request)?;
    let raw_response = match session_opt {
        Some(session) => session
            .diff_defense_audit(req_str)
            .map_err(|e| err(format!("Scheme diff-defense audit failed: {e}")))?,
        None => {
            let session = AitiaSession::start()
                .map_err(|e| err(format!("Failed to attach to AITIA Scheme session: {e}")))?;
            session
                .diff_defense_audit(req_str)
                .map_err(|e| err(format!("Scheme diff-defense audit failed: {e}")))?
        }
    };

    let mut report: Value = serde_json::from_str(&raw_response)?;
    let digest =
        crate::source_tree::sha256(serde_json::to_string(&report["repairPacket"])?.as_bytes());
    if let Some(obj) = report.as_object_mut() {
        obj.insert("vcsObservation".to_owned(), serde_json::to_value(&vcs)?);
        obj.insert("reportDigest".to_owned(), json!(digest));
        obj.insert("actionAuthorized".to_owned(), json!(false));
    }
    Ok(report)
}

/// Built-in default NASA NPR 7150.2D + DE sidecar profile for zero-config LLM interaction.
pub(crate) fn default_sidecar_profile_json(repo_dir: &Path) -> String {
    let target_repo = repo_dir
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("external-repo");
    json!({
        "schema": "lambda-aitia.sidecar-profile.v1",
        "targetRepo": target_repo,
        "nasaProfile": "nasa/sdlc/npr-7150.2d",
        "requiredAuditLenses": ["correctness", "security", "api-regression", "nasa-swe146"],
        "forbiddenUpstreamPrefixes": [".agents/aita/", ".aitia/"],
        "commitConvention": "conventional-commits",
        "allowAuditTrailer": false,
        "epoch": 1,
    })
    .to_string()
}

/// Convenience entry point using core DE G2 rules with no extra subdomain rule packs.
pub(crate) fn audit_git_repo_defense(
    repo_dir: &Path,
    base_ref: &str,
    staged_only: bool,
) -> Result<Value> {
    audit_git_repo_defense_with_packs(repo_dir, base_ref, staged_only, &[], &[], None)
}

/// Single-entry progressive FunFlow Choice review step (`aitia review` / gRPC `StepReview`).
///
/// Observes the repository natively via `gix` + `jj-lib`, reads sanitized diff surfaces and
/// changed paths, binds a deterministic `contextDigest`, and delegates progressive FunFlow
/// Choice frontier derivation + self-healing feedback to Scheme (`gitops-review-flow-step`).
pub(crate) fn run_review_flow_step_json(
    req: &Value,
    session_opt: Option<&AitiaSession>,
) -> Result<Value> {
    let repo_hint = req["repo"].as_str().unwrap_or(".");
    let repo_dir = Path::new(repo_hint);
    let base_ref = req["baseRef"].as_str().unwrap_or("HEAD");
    let staged_only = req["stagedOnly"].as_bool().unwrap_or(false);

    let vcs = aitia_jj::observe_vcs_sidecar_state(repo_dir, base_ref)
        .map_err(|e| err(format!("gix/jj-lib VCS observation failed: {e}")))?;
    let target_repo = req["targetRepo"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| {
            Path::new(&vcs.workdir)
                .file_name()
                .and_then(|n| n.to_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("external-repo")
                .to_owned()
        });

    let staged_diff =
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--cached", "--unified=3"])
            .map_err(|e| err(e.to_string()))?;
    let unstaged_diff = if staged_only {
        String::new()
    } else {
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--unified=3"])
            .map_err(|e| err(e.to_string()))?
    };
    let base_ref_diff = if !staged_only && vcs.base_commit != vcs.head_commit {
        let range = format!("{}..{}", vcs.base_commit, vcs.head_commit);
        aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--unified=3", &range])
            .map_err(|e| err(e.to_string()))?
    } else {
        String::new()
    };

    let status_out =
        aitia_jj::read_sanitized_git_diff(repo_dir, &["status", "--porcelain=v1", "-uall"])
            .map_err(|e| err(e.to_string()))?;
    let mut changed_paths: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
    for line in status_out.lines() {
        if line.len() >= 4 {
            let raw = line[3..].trim();
            let clean = raw
                .rsplit_once(" -> ")
                .map_or(raw, |(_, dst)| dst)
                .trim_matches('"');
            if !clean.is_empty() {
                changed_paths.insert(clean.to_owned());
            }
        }
    }
    if vcs.base_commit != vcs.head_commit {
        let range = format!("{}..{}", vcs.base_commit, vcs.head_commit);
        let names = aitia_jj::read_sanitized_git_diff(repo_dir, &["diff", "--name-only", &range])
            .map_err(|e| err(e.to_string()))?;
        for line in names.lines() {
            let p = line.trim();
            if !p.is_empty() {
                changed_paths.insert(p.to_owned());
            }
        }
    }
    let files_vec: Vec<String> = changed_paths.into_iter().collect();
    let context_core = json!({
        "targetRepo": target_repo,
        "baseCommit": vcs.base_commit,
        "headCommit": vcs.head_commit,
        "changedPaths": files_vec,
        "stagedDigest": crate::source_tree::sha256(staged_diff.as_bytes()),
        "unstagedDigest": crate::source_tree::sha256(unstaged_diff.as_bytes()),
        "baseRefDigest": crate::source_tree::sha256(base_ref_diff.as_bytes()),
    });
    let context_digest =
        crate::source_tree::sha256(serde_json::to_string(&context_core)?.as_bytes());

    let mut payload = req.as_object().cloned().unwrap_or_default();
    payload.insert("repo".to_owned(), json!(repo_hint));
    payload.insert("targetRepo".to_owned(), json!(target_repo));
    payload.insert("baseRef".to_owned(), json!(base_ref));
    payload.insert("contextDigest".to_owned(), json!(context_digest));
    payload.insert("changedPaths".to_owned(), json!(files_vec));
    payload.insert("stagedDiff".to_owned(), json!(staged_diff));
    payload.insert("unstagedDiff".to_owned(), json!(unstaged_diff));
    payload.insert("baseRefDiff".to_owned(), json!(base_ref_diff));

    let req_str = serde_json::to_string(&Value::Object(payload))?;
    let raw_response = match session_opt {
        Some(session) => session
            .review_flow_step(req_str)
            .map_err(|e| err(format!("Scheme review-flow step failed: {e}")))?,
        None => {
            let session = AitiaSession::start()
                .map_err(|e| err(format!("Failed to attach to AITIA Scheme session: {e}")))?;
            session
                .review_flow_step(req_str)
                .map_err(|e| err(format!("Scheme review-flow step failed: {e}")))?
        }
    };
    let mut out: Value = serde_json::from_str(&raw_response)?;
    if let Some(obj) = out.as_object_mut() {
        obj.insert("vcsObservation".to_owned(), serde_json::to_value(&vcs)?);
        obj.insert("actionAuthorized".to_owned(), json!(false));
    }
    Ok(out)
}
