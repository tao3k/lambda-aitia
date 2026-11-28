// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! RFC 6962 domain-separated binary SHA-256 Merkle tree and logarithmic O(log N)
//! repository inclusion proofs for multi-repo release attestation bundles (RFC 0015).
//!
//! Domain separation follows Certificate Transparency (RFC 6962):
//! - Leaf hash: `sha256(0x00 || canonical_json(link))`
//! - Internal node hash: `sha256(0x01 || left_digest_bytes || right_digest_bytes)`
//!
//! Never grants execution authority (`actionAuthorized: false`).

use super::{Result, err};
use serde_json::{Value, json};

fn sha256_prefixed(bytes: &[u8]) -> String {
    crate::source_tree::sha256(bytes)
}

fn leaf_hash(link: &Value) -> Result<String> {
    let canonical = serde_json::to_string(link)?;
    let mut buf = Vec::with_capacity(1 + canonical.len());
    buf.push(0x00);
    buf.extend_from_slice(canonical.as_bytes());
    Ok(sha256_prefixed(&buf))
}

fn node_hash(left: &str, right: &str) -> String {
    let mut buf = Vec::with_capacity(1 + left.len() + 1 + right.len());
    buf.push(0x01);
    buf.extend_from_slice(left.as_bytes());
    buf.push(b'|');
    buf.extend_from_slice(right.as_bytes());
    sha256_prefixed(&buf)
}

/// Compute the canonical RFC 6962 domain-separated SHA-256 Merkle root over a slice of
/// attestation `links`.
///
/// # Errors
/// Fails closed if `links` is empty or JSON serialization fails.
pub fn compute_links_merkle_root(links: &[Value]) -> Result<String> {
    if links.is_empty() {
        return Err(err("Cannot compute Merkle root over zero repo links"));
    }
    let mut level: Vec<String> = links
        .iter()
        .map(leaf_hash)
        .collect::<Result<Vec<String>>>()?;
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        let mut iter = level.into_iter();
        while let Some(left) = iter.next() {
            if let Some(right) = iter.next() {
                next.push(node_hash(&left, &right));
            } else {
                next.push(left);
            }
        }
        level = next;
    }
    level
        .into_iter()
        .next()
        .ok_or_else(|| err("Merkle root reduction produced empty level"))
}

/// Generate a logarithmic `O(log N)` RFC 6962 Merkle inclusion proof
/// (`lambda-aitia.repo-merkle-proof.v1`) for a single `repo_id` from a signed release
/// attestation bundle.
///
/// # Errors
/// Fails closed if `bundle` lacks `payload.links`, `repo_id` is absent, or `bundle` has
/// a mismatched `merkleRoot`.
pub fn generate_repo_merkle_proof(bundle: &Value, repo_id: &str) -> Result<Value> {
    let payload = bundle
        .get("payload")
        .ok_or_else(|| err("Release attestation missing payload for Merkle proof"))?;
    let links = payload["links"]
        .as_array()
        .ok_or_else(|| err("Release attestation missing links array"))?;
    let target_idx = links
        .iter()
        .position(|l| l["repoId"].as_str() == Some(repo_id))
        .ok_or_else(|| {
            err(&format!(
                "Repository `{repo_id}` not found in attestation links"
            ))
        })?;
    let mut level: Vec<String> = links
        .iter()
        .map(leaf_hash)
        .collect::<Result<Vec<String>>>()?;
    let target_leaf = level[target_idx].clone();
    let mut idx = target_idx;
    let mut siblings: Vec<Value> = Vec::new();
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        let mut i = 0;
        while i < level.len() {
            if i + 1 < level.len() {
                if i == idx {
                    siblings.push(json!({ "side": "right", "digest": level[i + 1] }));
                } else if i + 1 == idx {
                    siblings.push(json!({ "side": "left", "digest": level[i] }));
                }
                next.push(node_hash(&level[i], &level[i + 1]));
            } else {
                next.push(level[i].clone());
            }
            i += 2;
        }
        idx /= 2;
        level = next;
    }
    let root = level
        .into_iter()
        .next()
        .ok_or_else(|| err("Merkle proof generation produced empty root"))?;
    if let Some(claimed) = payload.get("merkleRoot").and_then(Value::as_str)
        && claimed != root
    {
        return Err(err("Attestation payload merkleRoot mismatch"));
    }
    Ok(json!({
        "schema": "lambda-aitia.repo-merkle-proof.v1",
        "repoId": repo_id,
        "leafIndex": target_idx,
        "treeSize": links.len(),
        "leafHash": target_leaf,
        "merkleRoot": root,
        "bundleDigest": bundle["bundleDigest"],
        "siblings": siblings,
        "link": links[target_idx],
        "actionAuthorized": false,
    }))
}

/// Verify a single-repository RFC 6962 Merkle inclusion proof against a caller-trusted
/// `expected_merkle_root` in `O(log N)` time with zero access to other repositories.
///
/// # Errors
/// Fails closed on schema mismatch, `actionAuthorized != false`, missing reports,
/// tampered link, invalid sibling side, or computed root mismatch.
pub fn verify_repo_merkle_proof(proof: &Value, expected_merkle_root: &str) -> Result<Value> {
    if proof["schema"].as_str() != Some("lambda-aitia.repo-merkle-proof.v1") {
        return Err(err("Unsupported repo Merkle proof schema"));
    }
    if proof["actionAuthorized"].as_bool() != Some(false) {
        return Err(err("Repo Merkle proof must have actionAuthorized: false"));
    }
    let link = proof
        .get("link")
        .ok_or_else(|| err("Repo Merkle proof missing link"))?;
    if link["actionAuthorized"].as_bool() != Some(false) {
        return Err(err("Merkle proof link must have actionAuthorized: false"));
    }
    if link["missingReports"].as_u64() != Some(0) {
        return Err(err("Merkle proof link contains missingReports"));
    }
    let repo_id = proof["repoId"]
        .as_str()
        .ok_or_else(|| err("Repo Merkle proof missing repoId"))?;
    if link["repoId"].as_str() != Some(repo_id) {
        return Err(err("Repo Merkle proof repoId mismatch with link"));
    }
    let siblings = proof["siblings"]
        .as_array()
        .ok_or_else(|| err("Repo Merkle proof missing siblings array"))?;
    let mut current = leaf_hash(link)?;
    if let Some(claimed_leaf) = proof["leafHash"].as_str()
        && claimed_leaf != current
    {
        return Err(err("Repo Merkle proof leafHash mismatch (link tampered)"));
    }
    for sib in siblings {
        let side = sib["side"]
            .as_str()
            .ok_or_else(|| err("Merkle sibling missing side"))?;
        let digest = sib["digest"]
            .as_str()
            .ok_or_else(|| err("Merkle sibling missing digest"))?;
        current = match side {
            "left" => node_hash(digest, &current),
            "right" => node_hash(&current, digest),
            _ => return Err(err("Invalid Merkle sibling side (expected left or right)")),
        };
    }
    if current != expected_merkle_root {
        return Err(err(
            "Repo Merkle inclusion proof root mismatch (tampering or wrong sibling order)",
        ));
    }
    Ok(json!({
        "schema": "lambda-aitia.merkle-inclusion-verdict.v1",
        "verified": true,
        "repoId": repo_id,
        "merkleRoot": current,
        "verificationKey": link["verificationKey"],
        "siblingCount": siblings.len(),
        "actionAuthorized": false,
    }))
}

/// JSON string wrapper for FFI/PyO3 callers: generate a single-repo Merkle inclusion proof.
///
/// # Errors
/// Fails closed if `bundle_json` is invalid JSON or proof generation fails.
pub fn generate_repo_merkle_proof_json(bundle_json: &str, repo_id: &str) -> Result<String> {
    let bundle: Value = serde_json::from_str(bundle_json)?;
    Ok(serde_json::to_string(&generate_repo_merkle_proof(
        &bundle, repo_id,
    )?)?)
}

/// JSON string wrapper for FFI/PyO3 callers: verify a single-repo Merkle inclusion proof.
///
/// # Errors
/// Fails closed if `proof_json` is invalid JSON or verification fails.
pub fn verify_repo_merkle_proof_json(
    proof_json: &str,
    expected_merkle_root: &str,
) -> Result<String> {
    let proof: Value = serde_json::from_str(proof_json)?;
    Ok(serde_json::to_string(&verify_repo_merkle_proof(
        &proof,
        expected_merkle_root,
    )?)?)
}
