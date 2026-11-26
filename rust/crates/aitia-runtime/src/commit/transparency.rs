// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! RFC 6962 §2.1.2 Append-Only Transparency Log & Logarithmic Consistency Proofs (RFC 0016).
//!
//! Proves cryptographically in `O(log N)` hashes that a newer log checkpoint `(N, R_N)` is
//! a strict append-only extension of an earlier checkpoint `(M, R_M)` (`1 <= M <= N`),
//! defeating historical equivocation, split-view forks, and log truncation attacks.
//! Never grants execution authority (`actionAuthorized: false`).

use super::{Result, err};
use serde_json::{Value, json};

fn leaf_hash(entry: &Value) -> Result<String> {
    let canonical = serde_json::to_string(entry)?;
    let mut buf = Vec::with_capacity(1 + canonical.len());
    buf.push(0x00);
    buf.extend_from_slice(canonical.as_bytes());
    Ok(crate::source_tree::sha256(&buf))
}

fn node_hash(left: &str, right: &str) -> String {
    let mut buf = Vec::with_capacity(1 + left.len() + 1 + right.len());
    buf.push(0x01);
    buf.extend_from_slice(left.as_bytes());
    buf.push(b'|');
    buf.extend_from_slice(right.as_bytes());
    crate::source_tree::sha256(&buf)
}

const fn largest_power_of_two_less_than(n: usize) -> usize {
    debug_assert!(n > 1);
    let p = (n - 1).next_power_of_two();
    if p >= n { p >> 1 } else { p }
}

fn mth(leaves: &[String]) -> String {
    match leaves {
        [] => unreachable!("mth called on empty slice"),
        [only] => only.clone(),
        _ => {
            let k = largest_power_of_two_less_than(leaves.len());
            let left = mth(&leaves[..k]);
            let right = mth(&leaves[k..]);
            node_hash(&left, &right)
        }
    }
}

fn subproof(m: usize, leaves: &[String], complete_subtree: bool, out: &mut Vec<String>) {
    let n = leaves.len();
    if m == n {
        if !complete_subtree {
            out.push(mth(leaves));
        }
        return;
    }
    let k = largest_power_of_two_less_than(n);
    if m <= k {
        subproof(m, &leaves[..k], complete_subtree, out);
        out.push(mth(&leaves[k..]));
    } else {
        subproof(m - k, &leaves[k..], false, out);
        out.push(mth(&leaves[..k]));
    }
}

/// Compute the canonical RFC 6962 §2.1 Merkle Tree Hash (MTH) over a non-empty log of
/// release attestation entries.
///
/// # Errors
/// Fails closed if `entries` is empty or serialization fails.
pub fn compute_log_root(entries: &[Value]) -> Result<String> {
    if entries.is_empty() {
        return Err(err("Transparency log must contain at least one entry"));
    }
    let leaves: Vec<String> = entries
        .iter()
        .map(leaf_hash)
        .collect::<Result<Vec<String>>>()?;
    Ok(mth(&leaves))
}

/// Generate an RFC 6962 §2.1.2 `O(log N)` append-only consistency proof
/// (`lambda-aitia.transparency-consistency-proof.v1`) proving that `entries[0..first_size]`
/// is an exact prefix of `entries[0..entries.len()]`.
///
/// # Errors
/// Fails closed if `first_size == 0` or `first_size > entries.len()`.
pub fn generate_consistency_proof(entries: &[Value], first_size: usize) -> Result<Value> {
    let second_size = entries.len();
    if first_size == 0 || first_size > second_size {
        return Err(err(
            "Consistency proof requires 1 <= firstSize <= secondSize",
        ));
    }
    let leaves: Vec<String> = entries
        .iter()
        .map(leaf_hash)
        .collect::<Result<Vec<String>>>()?;
    let first_root = mth(&leaves[..first_size]);
    let second_root = mth(&leaves);
    let mut proof = Vec::new();
    if first_size < second_size {
        subproof(first_size, &leaves, true, &mut proof);
    }
    Ok(json!({
        "schema": "lambda-aitia.transparency-consistency-proof.v1",
        "firstSize": first_size,
        "secondSize": second_size,
        "firstRoot": first_root,
        "secondRoot": second_root,
        "proofHashes": proof,
        "actionAuthorized": false,
    }))
}

/// Verify an RFC 6962 §2.1.2 append-only consistency proof against caller-trusted
/// `expected_first_root` and `expected_second_root`.
///
/// Reconstructs BOTH roots simultaneously from `proofHashes`, failing closed on truncation
/// (`firstSize > secondSize`), zero-size logs, historical equivocation, split-view forks,
/// or malformed proof length. Never grants execution authority (`actionAuthorized: false`).
///
/// # Errors
/// Fails closed on any schema, size, root mismatch, or unauthorized action claim.
pub fn verify_consistency_proof(
    proof: &Value,
    expected_first_root: &str,
    expected_second_root: &str,
) -> Result<Value> {
    if proof["schema"].as_str() != Some("lambda-aitia.transparency-consistency-proof.v1") {
        return Err(err("Unsupported transparency consistency proof schema"));
    }
    if proof["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "Transparency consistency proof must have actionAuthorized: false",
        ));
    }
    let first = usize::try_from(
        proof["firstSize"]
            .as_u64()
            .ok_or_else(|| err("Consistency proof missing firstSize"))?,
    )
    .map_err(|_| err("Invalid firstSize"))?;
    let second = usize::try_from(
        proof["secondSize"]
            .as_u64()
            .ok_or_else(|| err("Consistency proof missing secondSize"))?,
    )
    .map_err(|_| err("Invalid secondSize"))?;
    if first == 0 || first > second {
        return Err(err(
            "Consistency proof rejected: requires 1 <= firstSize <= secondSize",
        ));
    }
    let hashes: Vec<&str> = proof["proofHashes"]
        .as_array()
        .ok_or_else(|| err("Consistency proof missing proofHashes array"))?
        .iter()
        .map(|v| {
            v.as_str()
                .ok_or_else(|| err("Consistency proof hash must be a string"))
        })
        .collect::<Result<Vec<&str>>>()?;

    if first == second {
        if !hashes.is_empty() || expected_first_root != expected_second_root {
            return Err(err(
                "Identical-size consistency proof requires empty proofHashes and matching roots",
            ));
        }
        return Ok(consistency_verdict(
            first,
            second,
            expected_first_root,
            expected_second_root,
            0,
        ));
    }

    let (recomputed_first, recomputed_second) =
        fold_rfc6962_consistency(first, second, expected_first_root, &hashes)?;
    if recomputed_first != expected_first_root {
        return Err(err(
            "Consistency proof failed: historical firstRoot mismatch (equivocation detected)",
        ));
    }
    if recomputed_second != expected_second_root {
        return Err(err(
            "Consistency proof failed: secondRoot mismatch (split-view fork detected)",
        ));
    }
    Ok(consistency_verdict(
        first,
        second,
        &recomputed_first,
        &recomputed_second,
        hashes.len(),
    ))
}

fn fold_rfc6962_consistency(
    first: usize,
    second: usize,
    expected_first_root: &str,
    hashes: &[&str],
) -> Result<(String, String)> {
    let mut fn_idx = first - 1;
    let mut sn_idx = second - 1;
    let mut iter = hashes.iter().copied();
    let mut fr = if first.is_power_of_two() {
        expected_first_root.to_owned()
    } else {
        iter.next()
            .ok_or_else(|| err("Consistency proof missing initial subtree hash"))?
            .to_owned()
    };
    let mut sr = fr.clone();
    while (fn_idx & 1) == 1 {
        fn_idx >>= 1;
        sn_idx >>= 1;
    }
    for c in iter {
        if sn_idx == 0 {
            return Err(err("Consistency proof has trailing unconsumed hashes"));
        }
        if (fn_idx & 1) == 1 || fn_idx == sn_idx {
            fr = node_hash(c, &fr);
            sr = node_hash(c, &sr);
            while fn_idx != 0 && (fn_idx & 1) == 0 {
                fn_idx >>= 1;
                sn_idx >>= 1;
            }
        } else {
            sr = node_hash(&sr, c);
        }
        fn_idx >>= 1;
        sn_idx >>= 1;
    }
    if sn_idx != 0 {
        return Err(err("Consistency proof truncated before reaching root"));
    }
    Ok((fr, sr))
}

fn consistency_verdict(
    first: usize,
    second: usize,
    first_root: &str,
    second_root: &str,
    proof_len: usize,
) -> Value {
    json!({
        "schema": "lambda-aitia.consistency-verdict.v1",
        "appendOnlyVerified": true,
        "firstSize": first,
        "secondSize": second,
        "firstRoot": first_root,
        "secondRoot": second_root,
        "proofHashCount": proof_len,
        "actionAuthorized": false,
    })
}

/// JSON string wrapper for FFI/PyO3 callers: generate an RFC 6962 consistency proof.
///
/// # Errors
/// Fails closed if `entries_json` is not a valid JSON array or proof generation fails.
pub fn generate_consistency_proof_json(entries_json: &str, first_size: usize) -> Result<String> {
    let entries: Vec<Value> = serde_json::from_str(entries_json)?;
    Ok(serde_json::to_string(&generate_consistency_proof(
        &entries, first_size,
    )?)?)
}

/// JSON string wrapper for FFI/PyO3 callers: verify an RFC 6962 consistency proof.
///
/// # Errors
/// Fails closed on malformed JSON or any consistency violation.
pub fn verify_consistency_proof_json(
    proof_json: &str,
    expected_first_root: &str,
    expected_second_root: &str,
) -> Result<String> {
    let proof: Value = serde_json::from_str(proof_json)?;
    Ok(serde_json::to_string(&verify_consistency_proof(
        &proof,
        expected_first_root,
        expected_second_root,
    )?)?)
}
