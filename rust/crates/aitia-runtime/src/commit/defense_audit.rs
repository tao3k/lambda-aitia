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
