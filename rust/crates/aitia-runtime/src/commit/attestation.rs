// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Offline in-toto/SLSA/TUF Proof-Carrying Release Attestation Bundles (RFC 0010 / RFC 0011).
//!
//! Supports single-signer and `k-of-n` distinct Ed25519 threshold quorum minting and
//! fail-closed verification with explicit TUF key revocation and monotonic epoch
//! anti-rollback enforcement. Never grants execution authority (`actionAuthorized: false`).

use super::{Result, err};
use ring::signature::KeyPair;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode<const N: usize>(value: &str) -> Result<[u8; N]> {
    if value.len() != N * 2 {
        return Err(err("Invalid attestation hex encoding length"));
    }
    let mut out = [0u8; N];
    for (slot, pair) in out.iter_mut().zip(value.as_bytes().chunks_exact(2)) {
        let pair_str = std::str::from_utf8(pair).map_err(|_| err("Invalid UTF-8 in hex"))?;
        *slot = u8::from_str_radix(pair_str, 16)
            .map_err(|_| err("Invalid hex digit in attestation"))?;
    }
    Ok(out)
}

/// Mint a single-signer Proof-Carrying Release Attestation Bundle (RFC 0010).
///
/// Delegates to [`mint_release_attestation_bundle_with_quorum`] at `epoch = 1`.
///
/// # Errors
/// Fails closed if `step` is not `quiescent`, any repo lineage has `missingReports`,
/// or the Ed25519 signing seed is malformed.
pub fn mint_release_attestation_bundle(
    step: &Value,
    signing_seed_hex: Option<&str>,
) -> Result<Value> {
    let default_seed = "42".repeat(32);
    let seed_ref = signing_seed_hex.unwrap_or(default_seed.as_str());
    mint_release_attestation_bundle_with_quorum(step, &[seed_ref], 1)
}

/// Mint a TUF `k-of-n` threshold Proof-Carrying Release Attestation Bundle (RFC 0011).
///
/// Signs the canonical SHA-256 `bundleDigest` (covering `waves`, `links`, `earlyCutoffs`,
/// `epoch`, and `actionAuthorized: false`) with every supplied Ed25519 32-byte hex seed.
/// Emits canonical sorted `signatures` plus top-level `publicKey`/`signature` for RFC 0010
/// backward compatibility. Never grants execution authority (`actionAuthorized: false`).
///
/// # Errors
/// Fails closed if `step` is not `quiescent`, `signing_seeds` is empty, `epoch == 0`,
/// any repo evidence lineage has `missingReports`, or any Ed25519 seed is malformed.
pub fn mint_release_attestation_bundle_with_quorum(
    step: &Value,
    signing_seeds: &[&str],
    epoch: u64,
) -> Result<Value> {
    mint_release_attestation_bundle_with_lineage(step, signing_seeds, epoch, None)
}

/// Mint a TUF `k-of-n` threshold Proof-Carrying Release Attestation Bundle linked to an
/// optional prior `parent_bundle_digest` (RFC 0012 multi-epoch provenance chain).
///
/// # Errors
/// Fails closed if `step` is not `quiescent`, `signing_seeds` is empty, `epoch == 0`,
/// `parent_bundle_digest` is not a `sha256:` digest, any repo lineage has `missingReports`,
/// or any Ed25519 seed is malformed.
pub fn mint_release_attestation_bundle_with_lineage(
    step: &Value,
    signing_seeds: &[&str],
    epoch: u64,
    parent_bundle_digest: Option<&str>,
) -> Result<Value> {
    if step["state"].as_str() != Some("quiescent") {
        return Err(err(
            "Release attestation bundle requires a quiescent protocol step",
        ));
    }
    if signing_seeds.is_empty() {
        return Err(err(
            "Release attestation requires at least one Ed25519 signing seed",
        ));
    }
    if epoch == 0 {
        return Err(err("Release attestation epoch must be >= 1"));
    }
    if let Some(parent) = parent_bundle_digest
        && !parent.starts_with("sha256:")
    {
        return Err(err("parentBundleDigest must be a sha256 digest"));
    }
    let repos = step["repos"]
        .as_array()
        .ok_or_else(|| err("Release attestation requires non-empty `repos` summary array"))?;
    let lineages = step.get("repoEvidenceLineages").and_then(Value::as_object);
    let mut links = Vec::with_capacity(repos.len());
    for repo in repos {
        let rid = repo["repoId"]
            .as_str()
            .ok_or_else(|| err("Repo summary missing repoId"))?;
        let missing = lineages
            .and_then(|map| map.get(rid))
            .and_then(|ev| ev["missingReports"].as_array())
            .map_or(0usize, Vec::len);
        if missing != 0 {
            return Err(err(
                "Cannot mint release attestation with missing evidence reports",
            ));
        }
        links.push(json!({
            "repoId": rid,
            "effectiveCommit": repo["effectiveCommit"],
            "interfaceDigest": repo["interfaceDigest"],
            "verificationKey": repo["verificationKey"],
            "earlyCutoff": repo["earlyCutoff"],
            "missingReports": missing,
            "actionAuthorized": false,
        }));
    }
    let mut payload = json!({
        "schema": "lambda-aitia.release-attestation-payload.v1",
        "epoch": epoch,
        "waves": step["waves"],
        "links": links,
        "earlyCutoffs": step.get("earlyCutoffs").cloned().unwrap_or_else(|| json!([])),
        "actionAuthorized": false,
    });
    if let Some(parent) = parent_bundle_digest
        && let Some(obj) = payload.as_object_mut()
    {
        obj.insert("parentBundleDigest".to_owned(), json!(parent));
    }
    let canonical = serde_json::to_string(&payload)?;
    let bundle_digest = crate::source_tree::sha256(canonical.as_bytes());
    let signatures = sign_digest_with_seeds(&bundle_digest, signing_seeds)?;
    let (primary_pk, primary_sig) = signatures
        .first()
        .cloned()
        .ok_or_else(|| err("Release attestation generated zero signatures"))?;
    let sig_entries: Vec<Value> = signatures
        .into_iter()
        .map(|(pk, sig)| json!({ "publicKey": pk, "signature": sig }))
        .collect();
    Ok(json!({
        "schema": "lambda-aitia.release-attestation-bundle.v1",
        "payload": payload,
        "bundleDigest": bundle_digest,
        "publicKey": primary_pk,
        "signature": primary_sig,
        "signatures": sig_entries,
        "actionAuthorized": false,
    }))
}

fn sign_digest_with_seeds(digest: &str, seeds: &[&str]) -> Result<Vec<(String, String)>> {
    let mut signatures: Vec<(String, String)> = Vec::with_capacity(seeds.len());
    for seed_hex in seeds {
        let seed = hex_decode::<32>(seed_hex)?;
        let keypair = ring::signature::Ed25519KeyPair::from_seed_unchecked(&seed)
            .map_err(|_| err("Failed to construct Ed25519 signing key"))?;
        let sig = keypair.sign(digest.as_bytes());
        signatures.push((
            hex_encode(keypair.public_key().as_ref()),
            hex_encode(sig.as_ref()),
        ));
    }
    signatures.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(signatures)
}

/// Derive the hex-encoded Ed25519 public key for a 32-byte hex seed.
///
/// # Errors
/// Fails closed if `seed_hex` is not a valid 32-byte hex string.
pub fn ed25519_public_key_hex(seed_hex: &str) -> Result<String> {
    let seed = hex_decode::<32>(seed_hex)?;
    let keypair = ring::signature::Ed25519KeyPair::from_seed_unchecked(&seed)
        .map_err(|_| err("Failed to construct Ed25519 keypair"))?;
    Ok(hex_encode(keypair.public_key().as_ref()))
}

/// Mint a signed TUF dual-quorum root rotation envelope (`lambda-aitia.tuf-root-rotation.v1`).
///
/// Signs the canonical SHA-256 `rotationDigest` of `new_root` with both `old_signing_seeds`
/// (handover from previous root) and `new_signing_seeds` (self-attestation by new root).
///
/// # Errors
/// Fails closed if `new_root` has an invalid schema or either seed list is malformed.
pub fn mint_tuf_root_rotation(
    new_root: &Value,
    old_signing_seeds: &[&str],
    new_signing_seeds: &[&str],
) -> Result<Value> {
    if new_root["schema"].as_str() != Some("lambda-aitia.tuf-trust-root.v1") {
        return Err(err("Unsupported TUF trust root schema in rotation"));
    }
    let canonical = serde_json::to_string(new_root)?;
    let rotation_digest = crate::source_tree::sha256(canonical.as_bytes());
    let old_sigs: Vec<Value> = sign_digest_with_seeds(&rotation_digest, old_signing_seeds)?
        .into_iter()
        .map(|(pk, sig)| json!({ "publicKey": pk, "signature": sig }))
        .collect();
    let new_sigs: Vec<Value> = sign_digest_with_seeds(&rotation_digest, new_signing_seeds)?
        .into_iter()
        .map(|(pk, sig)| json!({ "publicKey": pk, "signature": sig }))
        .collect();
    Ok(json!({
        "schema": "lambda-aitia.tuf-root-rotation.v1",
        "newRoot": new_root,
        "rotationDigest": rotation_digest,
        "oldSignatures": old_sigs,
        "newSignatures": new_sigs,
        "actionAuthorized": false,
    }))
}

/// Offline cryptographic verifier for a Proof-Carrying Release Attestation Bundle (RFC 0010).
///
/// Delegates to [`verify_release_attestation_bundle_with_trust_root`] with no TUF `TrustRoot`.
///
/// # Errors
/// Fails closed on schema mismatch, tampered payload/digest, forged signature, missing
/// evidence reports, or any unauthorized action claim.
pub fn verify_release_attestation_bundle(bundle: &Value) -> Result<BTreeMap<String, String>> {
    verify_release_attestation_bundle_with_trust_root(bundle, None)
}

/// Offline cryptographic verifier with optional TUF `k-of-n` `TrustRoot` enforcement (RFC 0011).
///
/// Recomputes `bundleDigest` from canonical `payload`, verifies Ed25519 signatures,
/// enforces `actionAuthorized == false` and `missingReports == 0` across every repo link.
/// When `trust_root` (`lambda-aitia.tuf-trust-root.v1`) is supplied, additionally enforces:
/// 1. Monotonic anti-rollback floor (`payload.epoch >= trustRoot.minEpoch`),
/// 2. Immediate fail-closed rejection if ANY presented signature comes from `revokedKeys`,
/// 3. At least `threshold` distinct authorized non-revoked signers (rejecting duplicate-key
///    quorum inflation).
///
/// # Errors
/// Fails closed on any schema, digest, signature, revocation, rollback, threshold, or
/// evidence-completeness violation.
pub fn verify_release_attestation_bundle_with_trust_root(
    bundle: &Value,
    trust_root: Option<&Value>,
) -> Result<BTreeMap<String, String>> {
    if bundle["schema"].as_str() != Some("lambda-aitia.release-attestation-bundle.v1") {
        return Err(err("Unsupported release attestation bundle schema"));
    }
    if bundle["actionAuthorized"].as_bool() != Some(false) {
        return Err(err("Release attestation must have actionAuthorized: false"));
    }
    let payload = bundle
        .get("payload")
        .ok_or_else(|| err("Release attestation missing payload"))?;
    if payload["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "Release attestation payload must have actionAuthorized: false",
        ));
    }
    let canonical = serde_json::to_string(payload)?;
    let recomputed = crate::source_tree::sha256(canonical.as_bytes());
    let claimed = bundle["bundleDigest"]
        .as_str()
        .ok_or_else(|| err("Release attestation missing bundleDigest"))?;
    if recomputed != claimed {
        return Err(err(
            "Release attestation bundleDigest mismatch (tampering detected)",
        ));
    }

    let sig_pairs = collect_bundle_signatures(bundle)?;
    let mut verified_pks: Vec<String> = Vec::with_capacity(sig_pairs.len());
    for (pk_hex, sig_hex) in sig_pairs {
        let pubkey = hex_decode::<32>(&pk_hex)?;
        let sig = hex_decode::<64>(&sig_hex)?;
        ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, pubkey)
            .verify(claimed.as_bytes(), &sig)
            .map_err(|_| err("Release attestation Ed25519 signature rejected"))?;
        verified_pks.push(pk_hex);
    }

    if let Some(root) = trust_root {
        verify_tuf_trust_root(root, payload, &verified_pks)?;
    }

    let links = payload["links"]
        .as_array()
        .ok_or_else(|| err("Release attestation missing links array"))?;
    if links.is_empty() {
        return Err(err("Release attestation contains zero repo links"));
    }
    let mut attested = BTreeMap::new();
    for link in links {
        if link["actionAuthorized"].as_bool() != Some(false) {
            return Err(err(
                "Release attestation link must have actionAuthorized: false",
            ));
        }
        if link["missingReports"].as_u64() != Some(0) {
            return Err(err("Release attestation link has missing evidence reports"));
        }
        let rid = link["repoId"]
            .as_str()
            .ok_or_else(|| err("Release attestation link missing repoId"))?;
        let vkey = link["verificationKey"]
            .as_str()
            .filter(|v| v.starts_with("sha256:"))
            .ok_or_else(|| err("Release attestation link missing valid verificationKey"))?;
        attested.insert(rid.to_owned(), vkey.to_owned());
    }
    Ok(attested)
}

fn collect_bundle_signatures(bundle: &Value) -> Result<Vec<(String, String)>> {
    if let Some(arr) = bundle.get("signatures").and_then(Value::as_array) {
        if arr.is_empty() {
            return Err(err("Release attestation signatures array is empty"));
        }
        let mut pairs = Vec::with_capacity(arr.len());
        for entry in arr {
            let pk = entry["publicKey"]
                .as_str()
                .ok_or_else(|| err("Signature entry missing publicKey"))?;
            let sig = entry["signature"]
                .as_str()
                .ok_or_else(|| err("Signature entry missing signature"))?;
            pairs.push((pk.to_owned(), sig.to_owned()));
        }
        return Ok(pairs);
    }
    let pk = bundle["publicKey"]
        .as_str()
        .ok_or_else(|| err("Release attestation missing publicKey"))?;
    let sig = bundle["signature"]
        .as_str()
        .ok_or_else(|| err("Release attestation missing signature"))?;
    Ok(vec![(pk.to_owned(), sig.to_owned())])
}

fn verify_tuf_trust_root(root: &Value, payload: &Value, verified_pks: &[String]) -> Result<()> {
    if root["schema"].as_str() != Some("lambda-aitia.tuf-trust-root.v1") {
        return Err(err("Unsupported TUF trust root schema"));
    }
    let threshold = usize::try_from(
        root["threshold"]
            .as_u64()
            .ok_or_else(|| err("TUF trust root missing threshold"))?,
    )
    .map_err(|_| err("Invalid TUF trust root threshold"))?;
    if threshold == 0 {
        return Err(err("TUF trust root threshold must be >= 1"));
    }
    let min_epoch = root["minEpoch"].as_u64().unwrap_or(1);
    let bundle_epoch = payload["epoch"].as_u64().unwrap_or(0);
    if bundle_epoch < min_epoch {
        return Err(err(
            "Release attestation epoch rollback rejected by TUF trust root",
        ));
    }
    let authorized: BTreeSet<&str> = root["authorizedKeys"]
        .as_array()
        .ok_or_else(|| err("TUF trust root missing authorizedKeys"))?
        .iter()
        .filter_map(Value::as_str)
        .collect();
    let revoked: BTreeSet<&str> = root
        .get("revokedKeys")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();

    let mut distinct_valid = BTreeSet::new();
    for pk in verified_pks {
        if revoked.contains(pk.as_str()) {
            return Err(err(
                "Release attestation signed by revoked key in TUF trust root",
            ));
        }
        if authorized.contains(pk.as_str()) {
            distinct_valid.insert(pk.as_str());
        }
    }
    if distinct_valid.len() < threshold {
        return Err(err(
            "Release attestation failed TUF k-of-n distinct authorized signer threshold",
        ));
    }
    Ok(())
}

fn verify_signature_entries(digest: &str, entries: &[Value]) -> Result<Vec<String>> {
    let mut verified_pks = Vec::with_capacity(entries.len());
    for entry in entries {
        let pk_hex = entry["publicKey"]
            .as_str()
            .ok_or_else(|| err("Rotation signature missing publicKey"))?;
        let sig_hex = entry["signature"]
            .as_str()
            .ok_or_else(|| err("Rotation signature missing signature"))?;
        let pubkey = hex_decode::<32>(pk_hex)?;
        let sig = hex_decode::<64>(sig_hex)?;
        ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, pubkey)
            .verify(digest.as_bytes(), &sig)
            .map_err(|_| err("TUF root rotation Ed25519 signature rejected"))?;
        verified_pks.push(pk_hex.to_owned());
    }
    Ok(verified_pks)
}

fn check_root_quorum_only(root: &Value, verified_pks: &[String], label: &str) -> Result<()> {
    let threshold = usize::try_from(
        root["threshold"]
            .as_u64()
            .ok_or_else(|| err("TUF trust root missing threshold"))?,
    )
    .map_err(|_| err("Invalid TUF trust root threshold"))?;
    if threshold == 0 {
        return Err(err("TUF trust root threshold must be >= 1"));
    }
    let authorized: BTreeSet<&str> = root["authorizedKeys"]
        .as_array()
        .ok_or_else(|| err("TUF trust root missing authorizedKeys"))?
        .iter()
        .filter_map(Value::as_str)
        .collect();
    let revoked: BTreeSet<&str> = root
        .get("revokedKeys")
        .and_then(Value::as_array)
        .map(|arr| arr.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();
    let mut distinct_valid = BTreeSet::new();
    for pk in verified_pks {
        if revoked.contains(pk.as_str()) {
            return Err(err(&format!(
                "TUF root rotation signed by revoked key in {label} root"
            )));
        }
        if authorized.contains(pk.as_str()) {
            distinct_valid.insert(pk.as_str());
        }
    }
    if distinct_valid.len() < threshold {
        return Err(err(&format!(
            "TUF root rotation failed {label} k-of-n distinct authorized signer threshold"
        )));
    }
    Ok(())
}

/// Offline verifier for a TUF dual-quorum root rotation chain (`R_1 -> R_2 -> ... -> R_m`).
///
/// Enforces strict `rootVersion == prev + 1`, monotonic `minEpoch >= prev.minEpoch`,
/// canonical `rotationDigest`, `actionAuthorized == false`, AND dual-quorum Ed25519
/// signatures from BOTH the previous root and the new root.
///
/// # Errors
/// Fails closed on version skip, epoch downgrade, digest tampering, revoked signer, or
/// missing old/new quorum.
pub fn verify_tuf_root_rotation_chain(
    genesis_root: &Value,
    rotations: &[Value],
) -> Result<Vec<Value>> {
    if genesis_root["schema"].as_str() != Some("lambda-aitia.tuf-trust-root.v1") {
        return Err(err("Unsupported genesis TUF trust root schema"));
    }
    let mut timeline = vec![genesis_root.clone()];
    for rot in rotations {
        if rot["schema"].as_str() != Some("lambda-aitia.tuf-root-rotation.v1") {
            return Err(err("Unsupported TUF root rotation envelope schema"));
        }
        if rot["actionAuthorized"].as_bool() != Some(false) {
            return Err(err("TUF root rotation must have actionAuthorized: false"));
        }
        let prev = timeline
            .last()
            .ok_or_else(|| err("Missing previous trust root"))?;
        let new_root = rot
            .get("newRoot")
            .ok_or_else(|| err("TUF root rotation missing newRoot"))?;
        if new_root["schema"].as_str() != Some("lambda-aitia.tuf-trust-root.v1") {
            return Err(err("Unsupported rotated TUF trust root schema"));
        }
        let prev_ver = prev["rootVersion"].as_u64().unwrap_or(0);
        let new_ver = new_root["rootVersion"].as_u64().unwrap_or(0);
        if new_ver != prev_ver.saturating_add(1) {
            return Err(err(
                "TUF root rotation must strictly increment rootVersion by 1",
            ));
        }
        let prev_min = prev["minEpoch"].as_u64().unwrap_or(1);
        let new_min = new_root["minEpoch"].as_u64().unwrap_or(0);
        if new_min < prev_min {
            return Err(err("TUF root rotation cannot downgrade minEpoch"));
        }
        let canonical = serde_json::to_string(new_root)?;
        let recomputed = crate::source_tree::sha256(canonical.as_bytes());
        let claimed = rot["rotationDigest"]
            .as_str()
            .ok_or_else(|| err("TUF root rotation missing rotationDigest"))?;
        if recomputed != claimed {
            return Err(err("TUF root rotationDigest mismatch (tampering detected)"));
        }
        let old_entries = rot["oldSignatures"]
            .as_array()
            .ok_or_else(|| err("TUF root rotation missing oldSignatures"))?;
        let new_entries = rot["newSignatures"]
            .as_array()
            .ok_or_else(|| err("TUF root rotation missing newSignatures"))?;
        let old_pks = verify_signature_entries(claimed, old_entries)?;
        let new_pks = verify_signature_entries(claimed, new_entries)?;
        check_root_quorum_only(prev, &old_pks, "previous")?;
        check_root_quorum_only(new_root, &new_pks, "new")?;
        timeline.push(new_root.clone());
    }
    Ok(timeline)
}

/// Offline verifier for a transitive multi-epoch release attestation chain (`B_0 -> ... -> B_k`)
/// rooted in a caller-pinned genesis `TrustRoot` and verified TUF dual-quorum `rotations`.
///
/// Enforces:
/// 1. Full TUF dual-quorum root rotation chain verification (`R_1 -> ... -> R_m`),
/// 2. Strictly increasing epochs across bundles (`B_i.epoch > B_{i-1}.epoch`),
/// 3. Exact cryptographic parent hash continuity (`B_i.payload.parentBundleDigest == B_{i-1}.bundleDigest`),
/// 4. Every bundle verified against the root active at its epoch, and the head bundle
///    verified against the latest active root `R_m`,
/// 5. `actionAuthorized: false` across every link and summary.
///
/// # Errors
/// Fails closed on any root rotation, parent-link, epoch-order, threshold, revocation,
/// or digest violation.
pub fn verify_attestation_lineage_chain(
    chain: &[Value],
    genesis_root: &Value,
    rotations: &[Value],
) -> Result<(BTreeMap<String, String>, Value)> {
    if chain.is_empty() {
        return Err(err("Attestation lineage chain must be non-empty"));
    }
    let roots = verify_tuf_root_rotation_chain(genesis_root, rotations)?;
    let latest_root = roots
        .last()
        .ok_or_else(|| err("Verified root timeline is empty"))?;

    let mut prev_digest: Option<String> = None;
    let mut prev_epoch: Option<u64> = None;
    let mut epochs: Vec<u64> = Vec::with_capacity(chain.len());
    let mut genesis_digest = String::new();
    let mut head_keys = BTreeMap::new();

    for (idx, bundle) in chain.iter().enumerate() {
        let ep = bundle["payload"]["epoch"].as_u64().unwrap_or(0);
        if let Some(pe) = prev_epoch
            && ep <= pe
        {
            return Err(err(
                "Attestation lineage chain epochs must be strictly increasing",
            ));
        }
        if let Some(ref pd) = prev_digest {
            let claimed_parent = bundle["payload"]["parentBundleDigest"]
                .as_str()
                .ok_or_else(|| err("Chained attestation bundle missing parentBundleDigest"))?;
            if claimed_parent != pd {
                return Err(err("Attestation lineage chain parentBundleDigest mismatch"));
            }
        }
        let is_head = idx + 1 == chain.len();
        let active_root = if is_head {
            latest_root
        } else {
            roots
                .iter()
                .rev()
                .find(|r| r["minEpoch"].as_u64().unwrap_or(1) <= ep)
                .unwrap_or(genesis_root)
        };
        let keys = verify_release_attestation_bundle_with_trust_root(bundle, Some(active_root))?;
        let digest = bundle["bundleDigest"]
            .as_str()
            .ok_or_else(|| err("Verified bundle missing bundleDigest"))?
            .to_owned();
        if idx == 0 {
            genesis_digest.clone_from(&digest);
        }
        prev_digest = Some(digest);
        prev_epoch = Some(ep);
        epochs.push(ep);
        if is_head {
            head_keys = keys;
        }
    }

    let summary = json!({
        "schema": "lambda-aitia.verified-attestation-lineage.v1",
        "chainLength": chain.len(),
        "rootVersion": latest_root["rootVersion"],
        "epochs": epochs,
        "genesisDigest": genesis_digest,
        "headDigest": prev_digest.unwrap_or_default(),
        "actionAuthorized": false,
    });
    Ok((head_keys, summary))
}
