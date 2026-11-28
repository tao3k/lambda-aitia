// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Sigstore Bundle v0.3 Wire Envelope, Federated Multi-Organization Witness Quorums,
//! Offline Timestamp Freshness/Skew Bounds, and RFC 6962 §2.1.1 Audit Inclusion Proofs (RFC 0020).
//!
//! Never grants execution authority (`actionAuthorized: false`).

use super::dsse::{base64_decode_strict, base64_encode, verify_dsse_envelope_value};
use super::transparency::{largest_power_of_two_less_than, leaf_hash, mth, node_hash};
use super::{Result, err};
use ring::signature::{ED25519, UnparsedPublicKey};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

const SIGSTORE_BUNDLE_MEDIA_TYPE: &str = "application/vnd.dev.sigstore.bundle.v0.3+json";
const FEDERATED_POLICY_SCHEMA: &str = "lambda-aitia.federated-witness-policy.v1";
const CHECKPOINT_SCHEMA: &str = "lambda-aitia.signed-checkpoint.v1";
const ORIGIN_DOMAIN: &str = "lambda-aitia.checkpoint.origin.v1\n";
const COSIG_DOMAIN: &str = "lambda-aitia.checkpoint.cosignature.v1\n";

fn hex_decode<const N: usize>(value: &str) -> Result<[u8; N]> {
    if value.len() != N * 2 {
        return Err(err("Invalid Sigstore hex encoding length"));
    }
    let mut out = [0u8; N];
    for (slot, pair) in out.iter_mut().zip(value.as_bytes().chunks_exact(2)) {
        let pair_str = std::str::from_utf8(pair).map_err(|_| err("Invalid UTF-8 in hex"))?;
        *slot =
            u8::from_str_radix(pair_str, 16).map_err(|_| err("Invalid hex digit in Sigstore"))?;
    }
    Ok(out)
}

fn verify_ed25519(public_key_hex: &str, signature_hex: &str, message: &[u8]) -> Result<()> {
    let pk = hex_decode::<32>(public_key_hex)?;
    let sig = hex_decode::<64>(signature_hex)?;
    UnparsedPublicKey::new(&ED25519, &pk)
        .verify(message, &sig)
        .map_err(|_| err("Ed25519 signature verification failed"))
}

fn audit_path(index: usize, leaves: &[String], out: &mut Vec<String>) {
    let n = leaves.len();
    if n <= 1 {
        return;
    }
    let k = largest_power_of_two_less_than(n);
    if index < k {
        audit_path(index, &leaves[..k], out);
        out.push(mth(&leaves[k..]));
    } else {
        audit_path(index - k, &leaves[k..], out);
        out.push(mth(&leaves[..k]));
    }
}

fn verify_rfc6962_audit_path(
    target_leaf_hash: &str,
    index: usize,
    tree_size: usize,
    proof_hashes: &[&str],
) -> Result<String> {
    if tree_size == 0 || index >= tree_size {
        return Err(err(
            "RFC 6962 audit inclusion proof requires 0 <= logIndex < treeSize",
        ));
    }
    let mut fn_idx = index;
    let mut sn_idx = tree_size - 1;
    let mut r = target_leaf_hash.to_owned();
    for sibling in proof_hashes {
        if sn_idx == 0 {
            return Err(err(
                "RFC 6962 audit inclusion proof has trailing unconsumed hashes",
            ));
        }
        if (fn_idx & 1) == 1 || fn_idx == sn_idx {
            r = node_hash(sibling, &r);
            while fn_idx != 0 && (fn_idx & 1) == 0 {
                fn_idx >>= 1;
                sn_idx >>= 1;
            }
        } else {
            r = node_hash(&r, sibling);
        }
        fn_idx >>= 1;
        sn_idx >>= 1;
    }
    if sn_idx != 0 {
        return Err(err(
            "RFC 6962 audit inclusion proof truncated before reaching tree root",
        ));
    }
    Ok(r)
}

struct FederatedPolicy {
    origin: String,
    origin_public_key: String,
    min_witnesses: usize,
    min_distinct_orgs: usize,
    not_before: u64,
    not_after: u64,
    max_skew_seconds: u64,
    witness_orgs: BTreeMap<String, String>,
    revoked_keys: BTreeSet<String>,
}

fn parse_federated_policy(policy: &Value) -> Result<FederatedPolicy> {
    if policy["schema"].as_str() != Some(FEDERATED_POLICY_SCHEMA) {
        return Err(err("Unsupported federated witness policy schema"));
    }
    let origin = policy["origin"]
        .as_str()
        .filter(|s| !s.is_empty() && !s.contains('\n') && !s.contains('\r'))
        .ok_or_else(|| err("Federated witness policy missing valid origin"))?;
    let origin_pk = policy["originPublicKey"]
        .as_str()
        .ok_or_else(|| err("Federated witness policy missing originPublicKey"))?;
    let _ = hex_decode::<32>(origin_pk)?;
    let min_witnesses = usize::try_from(
        policy["minWitnesses"]
            .as_u64()
            .ok_or_else(|| err("Federated witness policy missing minWitnesses"))?,
    )
    .map_err(|_| err("Invalid minWitnesses"))?;
    let min_distinct_orgs = usize::try_from(
        policy["minDistinctOrgs"]
            .as_u64()
            .ok_or_else(|| err("Federated witness policy missing minDistinctOrgs"))?,
    )
    .map_err(|_| err("Invalid minDistinctOrgs"))?;
    if min_witnesses == 0 || min_distinct_orgs == 0 {
        return Err(err(
            "Federated witness policy requires minWitnesses >= 1 and minDistinctOrgs >= 1",
        ));
    }
    let not_before = policy["notBefore"]
        .as_u64()
        .ok_or_else(|| err("Federated witness policy missing notBefore"))?;
    let not_after = policy["notAfter"]
        .as_u64()
        .ok_or_else(|| err("Federated witness policy missing notAfter"))?;
    if not_before > not_after {
        return Err(err(
            "Federated witness policy invalid window: notBefore > notAfter",
        ));
    }
    let max_skew_seconds = policy["maxSkewSeconds"]
        .as_u64()
        .ok_or_else(|| err("Federated witness policy missing maxSkewSeconds"))?;
    let org_map_obj = policy["witnessOrgs"]
        .as_object()
        .ok_or_else(|| err("Federated witness policy missing witnessOrgs map"))?;
    let mut witness_orgs = BTreeMap::new();
    for (pk, org_val) in org_map_obj {
        let _ = hex_decode::<32>(pk)?;
        let org = org_val
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| err("Federated witness policy org name must be non-empty"))?;
        witness_orgs.insert(pk.clone(), org.to_owned());
    }
    let mut revoked_keys = BTreeSet::new();
    if let Some(arr) = policy.get("revokedWitnessKeys").and_then(Value::as_array) {
        for item in arr {
            let pk = item
                .as_str()
                .ok_or_else(|| err("revokedWitnessKeys entry must be a string"))?;
            let _ = hex_decode::<32>(pk)?;
            revoked_keys.insert(pk.to_owned());
        }
    }
    Ok(FederatedPolicy {
        origin: origin.to_owned(),
        origin_public_key: origin_pk.to_owned(),
        min_witnesses,
        min_distinct_orgs,
        not_before,
        not_after,
        max_skew_seconds,
        witness_orgs,
        revoked_keys,
    })
}

struct FederatedCheckpointSummary {
    origin: String,
    origin_public_key: String,
    tree_size: usize,
    root_hash: String,
    note: String,
    valid_witness_count: usize,
    distinct_orgs: Vec<String>,
    median_timestamp: u64,
    observed_skew_seconds: u64,
    witness_records: Vec<Value>,
}

fn verify_federated_checkpoint(
    checkpoint: &Value,
    policy: &FederatedPolicy,
) -> Result<FederatedCheckpointSummary> {
    if checkpoint["schema"].as_str() != Some(CHECKPOINT_SCHEMA) {
        return Err(err(
            "Unsupported signed checkpoint schema in Sigstore bundle",
        ));
    }
    if checkpoint["actionAuthorized"].as_bool() != Some(false) {
        return Err(err("Signed checkpoint must declare actionAuthorized=false"));
    }
    let origin = checkpoint["origin"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing origin"))?;
    if origin != policy.origin {
        return Err(err("Signed checkpoint origin mismatch"));
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
        .filter(|s| s.starts_with("sha256:"))
        .ok_or_else(|| err("Signed checkpoint missing sha256 rootHash"))?;
    let note = checkpoint["checkpointNote"]
        .as_str()
        .ok_or_else(|| err("Signed checkpoint missing checkpointNote"))?;
    if note != format!("{origin}\n{tree_size}\n{root_hash}\n") {
        return Err(err("Signed checkpoint note mismatch"));
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
    let origin_msg = format!("{ORIGIN_DOMAIN}{note}");
    verify_ed25519(origin_pk, origin_sig, origin_msg.as_bytes())?;

    let cosigs = checkpoint["cosignatures"]
        .as_array()
        .ok_or_else(|| err("Signed checkpoint missing cosignatures"))?;
    let mut counted: BTreeMap<String, (String, String, u64)> = BTreeMap::new();
    for entry in cosigs {
        let pk = entry["publicKey"]
            .as_str()
            .ok_or_else(|| err("Cosignature missing publicKey"))?;
        let sig = entry["signature"]
            .as_str()
            .ok_or_else(|| err("Cosignature missing signature"))?;
        let ts = entry["timestamp"]
            .as_u64()
            .ok_or_else(|| err("Cosignature missing timestamp"))?;
        let wid = entry["witnessId"]
            .as_str()
            .unwrap_or("unknown-witness")
            .to_owned();
        let cosig_msg = format!("{COSIG_DOMAIN}time {ts}\n{note}");
        verify_ed25519(pk, sig, cosig_msg.as_bytes())?;

        if let Some(org) = policy.witness_orgs.get(pk)
            && !policy.revoked_keys.contains(pk)
        {
            if ts < policy.not_before || ts > policy.not_after {
                return Err(err(format!(
                    "Witness timestamp {ts} outside freshness window [{}, {}]",
                    policy.not_before, policy.not_after
                )));
            }
            counted
                .entry(pk.to_owned())
                .or_insert_with(|| (wid, org.clone(), ts));
        }
    }

    if counted.len() < policy.min_witnesses {
        return Err(err(format!(
            "Federated witness count {} < minWitnesses {}",
            counted.len(),
            policy.min_witnesses
        )));
    }
    let distinct_orgs: Vec<String> = counted
        .values()
        .map(|(_, org, _)| org.clone())
        .collect::<BTreeSet<String>>()
        .into_iter()
        .collect();
    if distinct_orgs.len() < policy.min_distinct_orgs {
        return Err(err(format!(
            "Federated witness org diversity {} < minDistinctOrgs {} (single-org collusion blocked)",
            distinct_orgs.len(),
            policy.min_distinct_orgs
        )));
    }

    let mut timestamps: Vec<u64> = counted.values().map(|(_, _, ts)| *ts).collect();
    timestamps.sort_unstable();
    let min_ts = *timestamps
        .first()
        .ok_or_else(|| err("No valid witness timestamps"))?;
    let max_ts = *timestamps
        .last()
        .ok_or_else(|| err("No valid witness timestamps"))?;
    let observed_skew = max_ts - min_ts;
    if observed_skew > policy.max_skew_seconds {
        return Err(err(format!(
            "Witness timestamp skew {observed_skew}s exceeds maxSkewSeconds {}s",
            policy.max_skew_seconds
        )));
    }
    let median_timestamp = timestamps[timestamps.len() / 2];
    let witness_records: Vec<Value> = counted
        .iter()
        .map(|(pk, (wid, org, ts))| {
            json!({
                "witnessId": wid,
                "org": org,
                "publicKey": pk,
                "timestamp": ts,
            })
        })
        .collect();

    Ok(FederatedCheckpointSummary {
        origin: origin.to_owned(),
        origin_public_key: origin_pk.to_owned(),
        tree_size,
        root_hash: root_hash.to_owned(),
        note: note.to_owned(),
        valid_witness_count: counted.len(),
        distinct_orgs,
        median_timestamp,
        observed_skew_seconds: observed_skew,
        witness_records,
    })
}

/// Assemble and self-verify a wire-compatible Sigstore Bundle v0.3
/// (`application/vnd.dev.sigstore.bundle.v0.3+json`) combining a DSSE in-toto v1 / SLSA v1.0
/// envelope, a genuine RFC 6962 §2.1.1 transparency log audit inclusion proof, and
/// federated multi-organization witness timestamp verification data (RFC 0020).
///
/// # Errors
/// Fails closed on invalid inputs, unbound attestation head entry, federated witness /
/// timestamp violation, or self-verification failure.
pub fn export_sigstore_bundle_v03_json(
    portable_bundle_json: &str,
    trust_root_json: &str,
    federated_policy_json: &str,
) -> Result<String> {
    let portable: Value = serde_json::from_str(portable_bundle_json)?;
    let trust_root: Value = serde_json::from_str(trust_root_json)?;
    let fed_policy_val: Value = serde_json::from_str(federated_policy_json)?;
    let fed_policy = parse_federated_policy(&fed_policy_val)?;

    let dsse = portable
        .get("dsseEnvelope")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("Portable bundle missing dsseEnvelope for Sigstore v0.3 export"))?;
    let dsse_verdict = verify_dsse_envelope_value(dsse, &trust_root)?;
    let head_digest = dsse_verdict["bundleDigest"]
        .as_str()
        .ok_or_else(|| err("DSSE verdict missing bundleDigest"))?;
    let head_merkle = dsse_verdict["merkleRoot"].as_str();

    let tlog = portable
        .get("transparencyLog")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("Portable bundle missing transparencyLog for Sigstore v0.3 export"))?;
    let checkpoint = tlog
        .get("checkpoint")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("transparencyLog missing checkpoint"))?;
    let cp_summary = verify_federated_checkpoint(checkpoint, &fed_policy)?;

    let entries = tlog["entries"]
        .as_array()
        .filter(|arr| arr.len() == cp_summary.tree_size)
        .ok_or_else(|| err("transparencyLog.entries must match checkpoint treeSize"))?;
    let leaves: Vec<String> = entries
        .iter()
        .map(leaf_hash)
        .collect::<Result<Vec<String>>>()?;
    if mth(&leaves) != cp_summary.root_hash {
        return Err(err(
            "transparencyLog.entries MTH does not match signed checkpoint rootHash",
        ));
    }
    let log_index = entries
        .iter()
        .position(|entry| {
            entry["bundleDigest"].as_str() == Some(head_digest)
                && head_merkle.is_none_or(|mr| entry["merkleRoot"].as_str() == Some(mr))
        })
        .ok_or_else(|| {
            err("transparencyLog.entries does not contain an entry matching DSSE head bundleDigest")
        })?;
    let mut hashes = Vec::new();
    audit_path(log_index, &leaves, &mut hashes);
    let canonical_body = serde_json::to_vec(&entries[log_index])?;
    let primary_hint = dsse["signatures"]
        .as_array()
        .and_then(|arr| arr.first())
        .and_then(|s| s["keyid"].as_str())
        .unwrap_or("ed25519:unknown");

    let bundle = json!({
        "mediaType": SIGSTORE_BUNDLE_MEDIA_TYPE,
        "verificationMaterial": {
            "publicKey": { "hint": primary_hint },
            "tlogEntries": [
                {
                    "logIndex": log_index.to_string(),
                    "logId": { "keyId": cp_summary.origin_public_key },
                    "integratedTime": cp_summary.median_timestamp.to_string(),
                    "inclusionProof": {
                        "logIndex": log_index.to_string(),
                        "rootHash": cp_summary.root_hash,
                        "treeSize": cp_summary.tree_size.to_string(),
                        "hashes": hashes,
                        "checkpoint": { "envelope": cp_summary.note },
                    },
                    "canonicalizedBody": base64_encode(&canonical_body),
                }
            ],
            "timestampVerificationData": {
                "witnessQuorumTimestamps": cp_summary.witness_records,
                "medianTimestamp": cp_summary.median_timestamp,
                "observedSkewSeconds": cp_summary.observed_skew_seconds,
            },
            "signedCheckpoint": checkpoint,
            "actionAuthorized": false,
        },
        "dsseEnvelope": dsse,
    });
    let bundle_str = serde_json::to_string(&bundle)?;
    let _ = verify_sigstore_bundle_v03_json(&bundle_str, trust_root_json, federated_policy_json)?;
    Ok(bundle_str)
}

/// Offline verifier for a wire-compatible Sigstore Bundle v0.3 against verifier-pinned
/// TUF `TrustRoot` and `FederatedWitnessPolicy` (RFC 0020).
///
/// # Errors
/// Fails closed on mediaType mismatch, DSSE PAE / TUF quorum failure, single-organization
/// witness collusion, stale or skewed witness timestamps, RFC 6962 §2.1.1 audit inclusion
/// proof mismatch, or leaf-to-DSSE head binding mismatch.
pub fn verify_sigstore_bundle_v03_json(
    sigstore_bundle_json: &str,
    trust_root_json: &str,
    federated_policy_json: &str,
) -> Result<String> {
    let bundle: Value = serde_json::from_str(sigstore_bundle_json)?;
    let trust_root: Value = serde_json::from_str(trust_root_json)?;
    let fed_policy_val: Value = serde_json::from_str(federated_policy_json)?;
    let fed_policy = parse_federated_policy(&fed_policy_val)?;

    if bundle["mediaType"].as_str() != Some(SIGSTORE_BUNDLE_MEDIA_TYPE) {
        return Err(err("Unsupported Sigstore bundle mediaType"));
    }
    let vm = bundle
        .get("verificationMaterial")
        .ok_or_else(|| err("Sigstore bundle missing verificationMaterial"))?;
    if vm["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "Sigstore bundle verificationMaterial must declare actionAuthorized=false",
        ));
    }
    let dsse = bundle
        .get("dsseEnvelope")
        .ok_or_else(|| err("Sigstore bundle missing dsseEnvelope"))?;
    let dsse_verdict = verify_dsse_envelope_value(dsse, &trust_root)?;
    let head_digest = dsse_verdict["bundleDigest"]
        .as_str()
        .ok_or_else(|| err("DSSE verdict missing bundleDigest"))?;
    let head_merkle = dsse_verdict["merkleRoot"].as_str();

    let checkpoint = vm
        .get("signedCheckpoint")
        .ok_or_else(|| err("Sigstore bundle verificationMaterial missing signedCheckpoint"))?;
    let cp_summary = verify_federated_checkpoint(checkpoint, &fed_policy)?;

    let tlog_entry = vm["tlogEntries"]
        .as_array()
        .and_then(|arr| arr.first())
        .ok_or_else(|| err("Sigstore bundle missing tlogEntries[0]"))?;
    if tlog_entry["logId"]["keyId"].as_str() != Some(cp_summary.origin_public_key.as_str()) {
        return Err(err(
            "Sigstore tlogEntry logId does not match originPublicKey",
        ));
    }
    let expected_time = cp_summary.median_timestamp.to_string();
    if tlog_entry["integratedTime"].as_str() != Some(expected_time.as_str()) {
        return Err(err(
            "Sigstore tlogEntry integratedTime does not match verified median witness timestamp",
        ));
    }
    let inc = tlog_entry
        .get("inclusionProof")
        .ok_or_else(|| err("Sigstore tlogEntry missing inclusionProof"))?;
    let log_index: usize = inc["logIndex"]
        .as_str()
        .ok_or_else(|| err("inclusionProof missing logIndex"))?
        .parse()
        .map_err(|_| err("Invalid inclusionProof logIndex"))?;
    let tree_size: usize = inc["treeSize"]
        .as_str()
        .ok_or_else(|| err("inclusionProof missing treeSize"))?
        .parse()
        .map_err(|_| err("Invalid inclusionProof treeSize"))?;
    if tree_size != cp_summary.tree_size {
        return Err(err(
            "Sigstore inclusionProof treeSize does not match signedCheckpoint treeSize",
        ));
    }
    if inc["rootHash"].as_str() != Some(cp_summary.root_hash.as_str()) {
        return Err(err(
            "Sigstore inclusionProof rootHash does not match signedCheckpoint rootHash",
        ));
    }
    if inc["checkpoint"]["envelope"].as_str() != Some(cp_summary.note.as_str()) {
        return Err(err(
            "Sigstore inclusionProof checkpoint envelope does not match signedCheckpoint note",
        ));
    }
    let body_b64 = tlog_entry["canonicalizedBody"]
        .as_str()
        .ok_or_else(|| err("Sigstore tlogEntry missing canonicalizedBody"))?;
    let body_bytes = base64_decode_strict(body_b64)?;
    let body_val: Value = serde_json::from_slice(&body_bytes)?;
    if body_val["bundleDigest"].as_str() != Some(head_digest) {
        return Err(err(
            "Sigstore tlogEntry canonicalizedBody bundleDigest does not match DSSE statement",
        ));
    }
    if let Some(expected_mr) = head_merkle
        && body_val["merkleRoot"].as_str() != Some(expected_mr)
    {
        return Err(err(
            "Sigstore tlogEntry canonicalizedBody merkleRoot does not match DSSE statement",
        ));
    }
    let proof_hashes: Vec<&str> = inc["hashes"]
        .as_array()
        .ok_or_else(|| err("Sigstore inclusionProof missing hashes array"))?
        .iter()
        .map(|v| {
            v.as_str()
                .ok_or_else(|| err("Sigstore inclusionProof hash must be a string"))
        })
        .collect::<Result<Vec<&str>>>()?;
    let target_leaf = leaf_hash(&body_val)?;
    let recomputed_root =
        verify_rfc6962_audit_path(&target_leaf, log_index, tree_size, &proof_hashes)?;
    if recomputed_root != cp_summary.root_hash {
        return Err(err(
            "Sigstore RFC 6962 §2.1.1 audit inclusion proof failed: rootHash mismatch",
        ));
    }

    Ok(serde_json::to_string(&json!({
        "schema": "lambda-aitia.sigstore-bundle-v03-verdict.v1",
        "verified": true,
        "mediaType": SIGSTORE_BUNDLE_MEDIA_TYPE,
        "bundleDigest": head_digest,
        "epoch": dsse_verdict["epoch"],
        "dssePaeDigest": dsse_verdict["paeDigest"],
        "checkpointOrigin": cp_summary.origin,
        "checkpointTreeSize": cp_summary.tree_size,
        "checkpointRootHash": cp_summary.root_hash,
        "validWitnessCount": cp_summary.valid_witness_count,
        "distinctOrgCount": cp_summary.distinct_orgs.len(),
        "distinctOrgs": cp_summary.distinct_orgs,
        "medianTimestamp": cp_summary.median_timestamp,
        "observedSkewSeconds": cp_summary.observed_skew_seconds,
        "tlogInclusionProofVerified": true,
        "tlogInclusionProofHashes": proof_hashes.len(),
        "actionAuthorized": false,
    }))?)
}
