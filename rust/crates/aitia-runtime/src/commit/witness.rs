// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Witness-Cosigned Signed Tree Heads (STH) & Cross-Auditor Gossip Equivocation Detection (RFC 0017).
//!
//! Implements C2SP-style canonical checkpoint notes (`<origin>\n<treeSize>\n<rootHash>\n`),
//! domain-separated Ed25519 log-operator signatures, timestamp-bound `k-of-n` distinct
//! non-revoked witness cosignature quorums, RFC 6962 cosigned checkpoint transitions, and
//! non-repudiable split-view equivocation evidence receipts.
//! Never grants execution authority (`actionAuthorized: false`).

use super::transparency::{compute_log_root, verify_consistency_proof};
use super::{Result, err};
use ring::signature::{ED25519, Ed25519KeyPair, KeyPair, UnparsedPublicKey};
use serde_json::{Value, json};
use std::collections::BTreeSet;

const CHECKPOINT_SCHEMA: &str = "lambda-aitia.signed-checkpoint.v1";
const POLICY_SCHEMA: &str = "lambda-aitia.witness-policy.v1";
const ORIGIN_DOMAIN: &str = "lambda-aitia.checkpoint.origin.v1\n";
const COSIG_DOMAIN: &str = "lambda-aitia.checkpoint.cosignature.v1\n";

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode<const N: usize>(value: &str) -> Result<[u8; N]> {
    if value.len() != N * 2 {
        return Err(err("Invalid checkpoint hex encoding length"));
    }
    let mut out = [0u8; N];
    for (slot, pair) in out.iter_mut().zip(value.as_bytes().chunks_exact(2)) {
        let pair_str = std::str::from_utf8(pair).map_err(|_| err("Invalid UTF-8 in hex"))?;
        *slot =
            u8::from_str_radix(pair_str, 16).map_err(|_| err("Invalid hex digit in checkpoint"))?;
    }
    Ok(out)
}

fn validate_origin(origin: &str) -> Result<()> {
    if origin.is_empty() || origin.contains('\n') || origin.contains('\r') {
        return Err(err(
            "Checkpoint origin must be a non-empty single-line identifier",
        ));
    }
    Ok(())
}

fn canonical_checkpoint_note(origin: &str, tree_size: usize, root_hash: &str) -> String {
    format!("{origin}\n{tree_size}\n{root_hash}\n")
}

fn origin_signing_payload(note: &str) -> Vec<u8> {
    let mut msg = Vec::with_capacity(ORIGIN_DOMAIN.len() + note.len());
    msg.extend_from_slice(ORIGIN_DOMAIN.as_bytes());
    msg.extend_from_slice(note.as_bytes());
    msg
}

fn cosignature_payload(timestamp: u64, note: &str) -> Vec<u8> {
    let prefix = format!("{COSIG_DOMAIN}time {timestamp}\n");
    let mut msg = Vec::with_capacity(prefix.len() + note.len());
    msg.extend_from_slice(prefix.as_bytes());
    msg.extend_from_slice(note.as_bytes());
    msg
}

fn verify_ed25519(public_key_hex: &str, signature_hex: &str, message: &[u8]) -> Result<()> {
    let pk = hex_decode::<32>(public_key_hex)?;
    let sig = hex_decode::<64>(signature_hex)?;
    UnparsedPublicKey::new(&ED25519, &pk)
        .verify(message, &sig)
        .map_err(|_| err("Ed25519 signature verification failed"))
}

struct ParsedPolicy {
    origin: String,
    origin_public_key: String,
    witness_threshold: usize,
    allowed_witness_keys: BTreeSet<String>,
    revoked_witness_keys: BTreeSet<String>,
}

fn parse_key_set(value: &Value, field: &str, required: bool) -> Result<BTreeSet<String>> {
    let Some(arr) = value.get(field) else {
        if required {
            return Err(err(format!("Witness policy missing {field}")));
        }
        return Ok(BTreeSet::new());
    };
    let list = arr
        .as_array()
        .ok_or_else(|| err(format!("Witness policy {field} must be an array")))?;
    let mut keys = BTreeSet::new();
    for item in list {
        let key = item
            .as_str()
            .ok_or_else(|| err(format!("Witness policy {field} entry must be a string")))?;
        let _ = hex_decode::<32>(key)?;
        keys.insert(key.to_owned());
    }
    Ok(keys)
}

fn parse_policy(policy: &Value) -> Result<ParsedPolicy> {
    if policy["schema"].as_str() != Some(POLICY_SCHEMA) {
        return Err(err("Unsupported witness policy schema"));
    }
    let origin = policy["origin"]
        .as_str()
        .ok_or_else(|| err("Witness policy missing origin"))?;
    validate_origin(origin)?;
    let origin_pk = policy["originPublicKey"]
        .as_str()
        .ok_or_else(|| err("Witness policy missing originPublicKey"))?;
    let _ = hex_decode::<32>(origin_pk)?;
    let threshold = usize::try_from(
        policy["witnessThreshold"]
            .as_u64()
            .ok_or_else(|| err("Witness policy missing witnessThreshold"))?,
    )
    .map_err(|_| err("Invalid witnessThreshold"))?;
    if threshold == 0 {
        return Err(err("Witness policy witnessThreshold must be >= 1"));
    }
    let allowed = parse_key_set(policy, "allowedWitnessKeys", true)?;
    let revoked = parse_key_set(policy, "revokedWitnessKeys", false)?;
    Ok(ParsedPolicy {
        origin: origin.to_owned(),
        origin_public_key: origin_pk.to_owned(),
        witness_threshold: threshold,
        allowed_witness_keys: allowed,
        revoked_witness_keys: revoked,
    })
}

struct VerifiedOriginCheckpoint {
    origin: String,
    tree_size: usize,
    root_hash: String,
    valid_witness_keys: BTreeSet<String>,
}

fn verify_origin_and_collect_witnesses(
    checkpoint: &Value,
    policy: &ParsedPolicy,
) -> Result<VerifiedOriginCheckpoint> {
    if checkpoint["schema"].as_str() != Some(CHECKPOINT_SCHEMA) {
        return Err(err("Unsupported signed checkpoint schema"));
    }
    if checkpoint["actionAuthorized"].as_bool() != Some(false) {
        return Err(err("Signed checkpoint must declare actionAuthorized=false"));
    }
    let origin = checkpoint["origin"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing origin"))?;
    validate_origin(origin)?;
    if origin != policy.origin {
        return Err(err(
            "Signed checkpoint origin mismatch (cross-log replay rejected)",
        ));
    }
    let tree_size = usize::try_from(
        checkpoint["treeSize"]
            .as_u64()
            .ok_or_else(|| err("Signed checkpoint missing treeSize"))?,
    )
    .map_err(|_| err("Invalid checkpoint treeSize"))?;
    if tree_size == 0 {
        return Err(err("Signed checkpoint treeSize must be >= 1"));
    }
    let root_hash = checkpoint["rootHash"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing rootHash"))?;
    if !root_hash.starts_with("sha256:") {
        return Err(err("Signed checkpoint rootHash must be a sha256 digest"));
    }
    let note = checkpoint["checkpointNote"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing checkpointNote"))?;
    let expected_note = canonical_checkpoint_note(origin, tree_size, root_hash);
    if note != expected_note {
        return Err(err(
            "Signed checkpoint note does not match canonical header",
        ));
    }
    let origin_pk = checkpoint["originPublicKey"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing originPublicKey"))?;
    if origin_pk != policy.origin_public_key {
        return Err(err("Signed checkpoint originPublicKey mismatch"));
    }
    let origin_sig = checkpoint["originSignature"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing originSignature"))?;
    verify_ed25519(origin_pk, origin_sig, &origin_signing_payload(note))?;

    let cosigs = checkpoint["cosignatures"]
        .as_array()
        .ok_or_else(|| err("Signed checkpoint missing cosignatures array"))?;
    let mut valid_witness_keys = BTreeSet::new();
    for entry in cosigs {
        let pk = entry["publicKey"]
            .as_str()
            .ok_or_else(|| err("Cosignature missing publicKey"))?;
        let sig = entry["signature"]
            .as_str()
            .ok_or_else(|| err("Cosignature missing signature"))?;
        let timestamp = entry["timestamp"]
            .as_u64()
            .ok_or_else(|| err("Cosignature missing timestamp"))?;
        verify_ed25519(pk, sig, &cosignature_payload(timestamp, note))?;
        if policy.allowed_witness_keys.contains(pk) && !policy.revoked_witness_keys.contains(pk) {
            valid_witness_keys.insert(pk.to_owned());
        }
    }
    Ok(VerifiedOriginCheckpoint {
        origin: origin.to_owned(),
        tree_size,
        root_hash: root_hash.to_owned(),
        valid_witness_keys,
    })
}

fn require_witness_quorum(
    verified: &VerifiedOriginCheckpoint,
    policy: &ParsedPolicy,
) -> Result<()> {
    if verified.valid_witness_keys.len() < policy.witness_threshold {
        return Err(err(format!(
            "Witness cosignature quorum not met: {} distinct non-revoked trusted witnesses < threshold {}",
            verified.valid_witness_keys.len(),
            policy.witness_threshold
        )));
    }
    Ok(())
}

/// Sign an RFC 6962 transparency log Signed Tree Head (STH) with the log operator Ed25519 key
/// and a set of timestamp-bound witness Ed25519 cosignatures (RFC 0017).
///
/// # Errors
/// Fails closed if `origin` is invalid, `entries_json` is empty or malformed, or any Ed25519
/// seed hex is invalid.
pub fn sign_checkpoint_json(
    origin: &str,
    entries_json: &str,
    origin_seed_hex: &str,
    witness_specs_json: &str,
) -> Result<String> {
    validate_origin(origin)?;
    let entries: Vec<Value> = serde_json::from_str(entries_json)?;
    let root_hash = compute_log_root(&entries)?;
    let tree_size = entries.len();
    let note = canonical_checkpoint_note(origin, tree_size, &root_hash);

    let origin_seed = hex_decode::<32>(origin_seed_hex)?;
    let origin_kp = Ed25519KeyPair::from_seed_unchecked(&origin_seed)
        .map_err(|_| err("Failed to construct origin Ed25519 keypair"))?;
    let origin_sig = origin_kp.sign(&origin_signing_payload(&note));

    let witness_specs: Vec<Value> = serde_json::from_str(witness_specs_json)?;
    let mut cosignatures: Vec<(String, u64, String, String)> =
        Vec::with_capacity(witness_specs.len());
    for (idx, spec) in witness_specs.iter().enumerate() {
        let seed_hex = spec["seedHex"]
            .as_str()
            .ok_or_else(|| err("Witness spec missing seedHex"))?;
        let timestamp = spec["timestamp"]
            .as_u64()
            .ok_or_else(|| err("Witness spec missing timestamp"))?;
        let witness_id = spec["witnessId"]
            .as_str()
            .map_or_else(|| format!("witness-{idx}"), str::to_owned);
        let seed = hex_decode::<32>(seed_hex)?;
        let kp = Ed25519KeyPair::from_seed_unchecked(&seed)
            .map_err(|_| err("Failed to construct witness Ed25519 keypair"))?;
        let sig = kp.sign(&cosignature_payload(timestamp, &note));
        cosignatures.push((
            hex_encode(kp.public_key().as_ref()),
            timestamp,
            witness_id,
            hex_encode(sig.as_ref()),
        ));
    }
    cosignatures.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));
    let cosig_json: Vec<Value> = cosignatures
        .into_iter()
        .map(|(pk, ts, wid, sig)| {
            json!({
                "witnessId": wid,
                "publicKey": pk,
                "timestamp": ts,
                "signature": sig,
            })
        })
        .collect();

    Ok(serde_json::to_string(&json!({
        "schema": CHECKPOINT_SCHEMA,
        "origin": origin,
        "treeSize": tree_size,
        "rootHash": root_hash,
        "checkpointNote": note,
        "originPublicKey": hex_encode(origin_kp.public_key().as_ref()),
        "originSignature": hex_encode(origin_sig.as_ref()),
        "cosignatures": cosig_json,
        "actionAuthorized": false,
    }))?)
}

/// Offline verifier for a witness-cosigned checkpoint note against a verifier-pinned
/// `WitnessPolicy` (`lambda-aitia.witness-policy.v1`).
///
/// # Errors
/// Fails closed on origin mismatch, forged origin/witness signatures, duplicate-key quorum
/// inflation, revoked witnesses dropping quorum below threshold, or unauthorized flags.
pub fn verify_signed_checkpoint_json(checkpoint_json: &str, policy_json: &str) -> Result<String> {
    let checkpoint: Value = serde_json::from_str(checkpoint_json)?;
    let policy_val: Value = serde_json::from_str(policy_json)?;
    let policy = parse_policy(&policy_val)?;
    let verified = verify_origin_and_collect_witnesses(&checkpoint, &policy)?;
    require_witness_quorum(&verified, &policy)?;
    let keys: Vec<String> = verified.valid_witness_keys.into_iter().collect();
    Ok(serde_json::to_string(&json!({
        "schema": "lambda-aitia.checkpoint-verdict.v1",
        "verified": true,
        "origin": verified.origin,
        "treeSize": verified.tree_size,
        "rootHash": verified.root_hash,
        "validWitnessCount": keys.len(),
        "witnessThreshold": policy.witness_threshold,
        "validWitnessKeys": keys,
        "actionAuthorized": false,
    }))?)
}

/// Verify a witness-cosigned append-only transition `STH_1 -> STH_2` by composing
/// `WitnessPolicy` quorum verification on both checkpoints with RFC 6962 §2.1.2 consistency
/// proof verification (RFC 0016 + RFC 0017).
///
/// # Errors
/// Fails closed if either checkpoint fails origin/witness verification, `first.treeSize > second.treeSize`,
/// proof sizes disagree with checkpoints, or the RFC 6962 consistency proof fails.
pub fn verify_checkpoint_transition_json(
    first_checkpoint_json: &str,
    second_checkpoint_json: &str,
    proof_json: &str,
    policy_json: &str,
) -> Result<String> {
    let first_val: Value = serde_json::from_str(first_checkpoint_json)?;
    let second_val: Value = serde_json::from_str(second_checkpoint_json)?;
    let proof_val: Value = serde_json::from_str(proof_json)?;
    let policy_val: Value = serde_json::from_str(policy_json)?;
    let policy = parse_policy(&policy_val)?;

    let first = verify_origin_and_collect_witnesses(&first_val, &policy)?;
    require_witness_quorum(&first, &policy)?;
    let second = verify_origin_and_collect_witnesses(&second_val, &policy)?;
    require_witness_quorum(&second, &policy)?;

    if first.tree_size > second.tree_size {
        return Err(err(
            "Checkpoint transition rejected: treeSize rollback / truncation detected",
        ));
    }
    let proof_first = usize::try_from(
        proof_val["firstSize"]
            .as_u64()
            .ok_or_else(|| err("Consistency proof missing firstSize"))?,
    )
    .map_err(|_| err("Invalid consistency proof firstSize"))?;
    let proof_second = usize::try_from(
        proof_val["secondSize"]
            .as_u64()
            .ok_or_else(|| err("Consistency proof missing secondSize"))?,
    )
    .map_err(|_| err("Invalid consistency proof secondSize"))?;
    if proof_first != first.tree_size || proof_second != second.tree_size {
        return Err(err(
            "Consistency proof sizes do not match signed checkpoint tree sizes",
        ));
    }
    let verdict = verify_consistency_proof(&proof_val, &first.root_hash, &second.root_hash)?;
    Ok(serde_json::to_string(&json!({
        "schema": "lambda-aitia.checkpoint-transition-verdict.v1",
        "verified": true,
        "origin": first.origin,
        "firstSize": first.tree_size,
        "secondSize": second.tree_size,
        "firstRoot": first.root_hash,
        "secondRoot": second.root_hash,
        "firstWitnessCount": first.valid_witness_keys.len(),
        "secondWitnessCount": second.valid_witness_keys.len(),
        "proofHashCount": verdict["proofHashCount"],
        "actionAuthorized": false,
    }))?)
}

fn build_equivocation_receipt(
    origin: &str,
    conflict_kind: &str,
    failure_detail: Option<&str>,
    left: &Value,
    right: &Value,
    left_quorum: bool,
    right_quorum: bool,
) -> Result<Value> {
    let payload = json!({
        "origin": origin,
        "conflictKind": conflict_kind,
        "failureDetail": failure_detail,
        "left": left,
        "right": right,
        "leftWitnessQuorumMet": left_quorum,
        "rightWitnessQuorumMet": right_quorum,
        "actionAuthorized": false,
    });
    let digest = crate::source_tree::sha256(serde_json::to_string(&payload)?.as_bytes());
    Ok(json!({
        "schema": "lambda-aitia.checkpoint-equivocation-evidence.v1",
        "status": "equivocation-detected",
        "equivocationDetected": true,
        "conflictKind": conflict_kind,
        "failureDetail": failure_detail,
        "evidenceDigest": digest,
        "origin": origin,
        "left": left,
        "right": right,
        "leftWitnessQuorumMet": left_quorum,
        "rightWitnessQuorumMet": right_quorum,
        "actionAuthorized": false,
    }))
}

/// Cross-auditor gossip detector comparing two independently observed checkpoints `(left, right)`
/// under a verifier-pinned `WitnessPolicy` (RFC 0017).
///
/// Preserves competing observations and explicit epistemic `unknown` (`consistency-proof-required`)
/// when comparing distinct tree sizes without a consistency proof. Emits a non-repudiable
/// `lambda-aitia.checkpoint-equivocation-evidence.v1` receipt whenever authentic origin-signed
/// checkpoints exhibit same-size root mismatch or fail RFC 6962 consistency verification.
///
/// # Errors
/// Fails closed if either checkpoint lacks an authentic pinned `origin` Ed25519 signature,
/// violates canonical formatting, or fails JSON parsing.
pub fn detect_checkpoint_equivocation_json(
    left_checkpoint_json: &str,
    right_checkpoint_json: &str,
    policy_json: &str,
    proof_json: Option<&str>,
) -> Result<String> {
    let left_val: Value = serde_json::from_str(left_checkpoint_json)?;
    let right_val: Value = serde_json::from_str(right_checkpoint_json)?;
    let policy_val: Value = serde_json::from_str(policy_json)?;
    let policy = parse_policy(&policy_val)?;

    let left = verify_origin_and_collect_witnesses(&left_val, &policy)?;
    let right = verify_origin_and_collect_witnesses(&right_val, &policy)?;
    let left_quorum = left.valid_witness_keys.len() >= policy.witness_threshold;
    let right_quorum = right.valid_witness_keys.len() >= policy.witness_threshold;

    if left.tree_size == right.tree_size {
        if left.root_hash == right.root_hash {
            return Ok(serde_json::to_string(&json!({
                "schema": "lambda-aitia.checkpoint-gossip-verdict.v1",
                "status": "consistent",
                "equivocationDetected": false,
                "conflictKind": "none",
                "origin": policy.origin,
                "smallerSize": left.tree_size,
                "largerSize": right.tree_size,
                "leftWitnessQuorumMet": left_quorum,
                "rightWitnessQuorumMet": right_quorum,
                "actionAuthorized": false,
            }))?);
        }
        return Ok(serde_json::to_string(&build_equivocation_receipt(
            &policy.origin,
            "same-size-root-mismatch",
            None,
            &left_val,
            &right_val,
            left_quorum,
            right_quorum,
        )?)?);
    }

    let (smaller, larger) = if left.tree_size < right.tree_size {
        (&left, &right)
    } else {
        (&right, &left)
    };
    let Some(proof_str) = proof_json else {
        return Ok(serde_json::to_string(&json!({
            "schema": "lambda-aitia.checkpoint-gossip-verdict.v1",
            "status": "consistency-proof-required",
            "equivocationDetected": false,
            "conflictKind": "unverified-extension",
            "origin": policy.origin,
            "smallerSize": smaller.tree_size,
            "largerSize": larger.tree_size,
            "leftWitnessQuorumMet": left_quorum,
            "rightWitnessQuorumMet": right_quorum,
            "actionAuthorized": false,
        }))?);
    };
    let proof_val: Value = serde_json::from_str(proof_str)?;
    let size_mismatch = proof_val["firstSize"].as_u64() != Some(smaller.tree_size as u64)
        || proof_val["secondSize"].as_u64() != Some(larger.tree_size as u64);
    if size_mismatch {
        return Ok(serde_json::to_string(&build_equivocation_receipt(
            &policy.origin,
            "inconsistent-history-proof",
            Some("Consistency proof sizes do not match observed checkpoint pair"),
            &left_val,
            &right_val,
            left_quorum,
            right_quorum,
        )?)?);
    }
    match verify_consistency_proof(&proof_val, &smaller.root_hash, &larger.root_hash) {
        Ok(_) => Ok(serde_json::to_string(&json!({
            "schema": "lambda-aitia.checkpoint-gossip-verdict.v1",
            "status": "consistent",
            "equivocationDetected": false,
            "conflictKind": "none",
            "origin": policy.origin,
            "smallerSize": smaller.tree_size,
            "largerSize": larger.tree_size,
            "leftWitnessQuorumMet": left_quorum,
            "rightWitnessQuorumMet": right_quorum,
            "actionAuthorized": false,
        }))?),
        Err(reason) => Ok(serde_json::to_string(&build_equivocation_receipt(
            &policy.origin,
            "inconsistent-history-proof",
            Some(&reason.to_string()),
            &left_val,
            &right_val,
            left_quorum,
            right_quorum,
        )?)?),
    }
}
