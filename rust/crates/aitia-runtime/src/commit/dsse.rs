// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Standard in-toto v1 / SLSA v1.0 DSSE (Dead Simple Signing Envelope) PAE interoperability
//! and self-verifying portable audit bundle exporter (RFC 0019).
//!
//! Implements exact `DSSEv1` Pre-Authentication Encoding (PAE), strict RFC 4648 Base64,
//! in-toto Statement v1 + SLSA Provenance v1.0 projection, TUF `k-of-n` distinct non-revoked
//! Ed25519 verification, and fail-closed portable audit bundle export.
//! Never grants execution authority (`actionAuthorized: false`).

use super::audit::verify_portable_audit_bundle;
use super::{Result, err};
use ring::signature::{ED25519, Ed25519KeyPair, KeyPair, UnparsedPublicKey};
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::path::Path;

pub(crate) const INTOTO_PAYLOAD_TYPE: &str = "application/vnd.in-toto+json";
const INTOTO_STATEMENT_TYPE: &str = "https://in-toto.io/Statement/v1";
const SLSA_PREDICATE_TYPE: &str = "https://slsa.dev/provenance/v1";
const BUILD_TYPE: &str = "https://lambda-aitia.org/multi-repo-release-train/v1";
const BUILDER_ID: &str = "https://lambda-aitia.org/aitia-runtime/v1";
const KEYID_PREFIX: &str = "ed25519:";
const B64_TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn hex_decode<const N: usize>(value: &str) -> Result<[u8; N]> {
    if value.len() != N * 2 {
        return Err(err("Invalid DSSE hex encoding length"));
    }
    let mut out = [0u8; N];
    for (slot, pair) in out.iter_mut().zip(value.as_bytes().chunks_exact(2)) {
        let pair_str = std::str::from_utf8(pair).map_err(|_| err("Invalid UTF-8 in hex"))?;
        *slot = u8::from_str_radix(pair_str, 16).map_err(|_| err("Invalid hex digit in DSSE"))?;
    }
    Ok(out)
}

fn base64_encode(input: &[u8]) -> String {
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    let mut chunks = input.chunks_exact(3);
    for c in &mut chunks {
        let n = (u32::from(c[0]) << 16) | (u32::from(c[1]) << 8) | u32::from(c[2]);
        out.push(B64_TABLE[((n >> 18) & 0x3f) as usize] as char);
        out.push(B64_TABLE[((n >> 12) & 0x3f) as usize] as char);
        out.push(B64_TABLE[((n >> 6) & 0x3f) as usize] as char);
        out.push(B64_TABLE[(n & 0x3f) as usize] as char);
    }
    match chunks.remainder() {
        [] => {}
        [a] => {
            let n = u32::from(*a) << 16;
            out.push(B64_TABLE[((n >> 18) & 0x3f) as usize] as char);
            out.push(B64_TABLE[((n >> 12) & 0x3f) as usize] as char);
            out.push('=');
            out.push('=');
        }
        [a, b] => {
            let n = (u32::from(*a) << 16) | (u32::from(*b) << 8);
            out.push(B64_TABLE[((n >> 18) & 0x3f) as usize] as char);
            out.push(B64_TABLE[((n >> 12) & 0x3f) as usize] as char);
            out.push(B64_TABLE[((n >> 6) & 0x3f) as usize] as char);
            out.push('=');
        }
        _ => unreachable!(),
    }
    out
}

const fn b64_val(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte - b'A'),
        b'a'..=b'z' => Some(byte - b'a' + 26),
        b'0'..=b'9' => Some(byte - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

fn base64_decode_strict(input: &str) -> Result<Vec<u8>> {
    let bytes = input.as_bytes();
    if bytes.is_empty() || !bytes.len().is_multiple_of(4) {
        return Err(err("Invalid RFC 4648 Base64 length"));
    }
    let mut out = Vec::with_capacity((bytes.len() / 4) * 3);
    let total_chunks = bytes.len() / 4;
    for (idx, chunk) in bytes.chunks_exact(4).enumerate() {
        let is_last = idx + 1 == total_chunks;
        let a = b64_val(chunk[0]).ok_or_else(|| err("Invalid Base64 character"))?;
        let b = b64_val(chunk[1]).ok_or_else(|| err("Invalid Base64 character"))?;
        match (chunk[2], chunk[3]) {
            (b'=', b'=') if is_last => {
                if (b & 0x0f) != 0 {
                    return Err(err("Non-canonical Base64 padding bits"));
                }
                out.push((a << 2) | (b >> 4));
            }
            (c_byte, b'=') if is_last => {
                let c = b64_val(c_byte).ok_or_else(|| err("Invalid Base64 character"))?;
                if (c & 0x03) != 0 {
                    return Err(err("Non-canonical Base64 padding bits"));
                }
                out.push((a << 2) | (b >> 4));
                out.push((b << 4) | (c >> 2));
            }
            (c_byte, d_byte) => {
                let c = b64_val(c_byte).ok_or_else(|| err("Invalid Base64 character"))?;
                let d = b64_val(d_byte).ok_or_else(|| err("Invalid Base64 character"))?;
                out.push((a << 2) | (b >> 4));
                out.push((b << 4) | (c >> 2));
                out.push((c << 6) | d);
            }
        }
    }
    Ok(out)
}

fn dsse_pae(payload_type: &str, payload: &[u8]) -> Vec<u8> {
    let header = format!(
        "DSSEv1 {} {} {} ",
        payload_type.len(),
        payload_type,
        payload.len()
    );
    let mut out = Vec::with_capacity(header.len() + payload.len());
    out.extend_from_slice(header.as_bytes());
    out.extend_from_slice(payload);
    out
}

fn strip_sha256_prefix(digest: &str) -> Result<&str> {
    let hex = digest
        .strip_prefix("sha256:")
        .ok_or_else(|| err("Expected sha256:-prefixed digest for in-toto subject"))?;
    let _ = hex_decode::<32>(hex)?;
    Ok(hex)
}

fn build_intoto_statement(attestation: &Value) -> Result<Value> {
    if attestation["schema"].as_str() != Some("lambda-aitia.release-attestation-bundle.v1") {
        return Err(err(
            "Unsupported release attestation schema for DSSE export",
        ));
    }
    if attestation["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "Release attestation must declare actionAuthorized: false before DSSE export",
        ));
    }
    let payload = attestation
        .get("payload")
        .ok_or_else(|| err("Release attestation missing payload"))?;
    let bundle_digest = attestation["bundleDigest"]
        .as_str()
        .ok_or_else(|| err("Release attestation missing bundleDigest"))?;
    let bundle_hex = strip_sha256_prefix(bundle_digest)?;
    let epoch = payload["epoch"]
        .as_u64()
        .filter(|&e| e >= 1)
        .ok_or_else(|| err("Release attestation missing positive epoch"))?;
    let links = payload["links"]
        .as_array()
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| err("Release attestation missing non-empty links array"))?;

    let mut subjects: Vec<Value> = Vec::with_capacity(links.len() + 1);
    subjects.push(json!({
        "name": "lambda-aitia.release-attestation-bundle",
        "digest": { "sha256": bundle_hex },
    }));
    let mut repo_subjects: Vec<(String, Value)> = Vec::with_capacity(links.len());
    for link in links {
        let repo_id = link["repoId"]
            .as_str()
            .ok_or_else(|| err("Attestation link missing repoId"))?;
        let verification_key = link["verificationKey"]
            .as_str()
            .ok_or_else(|| err("Attestation link missing verificationKey"))?;
        let key_hex = strip_sha256_prefix(verification_key)?;
        repo_subjects.push((
            repo_id.to_owned(),
            json!({
                "name": repo_id,
                "digest": { "sha256": key_hex },
                "annotations": {
                    "commitHead": link["commitHead"],
                    "interfaceDigest": link["interfaceDigest"],
                },
            }),
        ));
    }
    repo_subjects.sort_by(|a, b| a.0.cmp(&b.0));
    for (_, sub) in repo_subjects {
        subjects.push(sub);
    }

    Ok(json!({
        "_type": INTOTO_STATEMENT_TYPE,
        "subject": subjects,
        "predicateType": SLSA_PREDICATE_TYPE,
        "predicate": {
            "buildDefinition": {
                "buildType": BUILD_TYPE,
                "externalParameters": {
                    "epoch": epoch,
                    "merkleRoot": payload["merkleRoot"],
                    "parentBundleDigest": payload.get("parentBundleDigest").cloned().unwrap_or(Value::Null),
                    "waves": payload["waves"],
                    "earlyCutoffs": payload["earlyCutoffs"],
                },
                "resolvedDependencies": links,
            },
            "runDetails": {
                "builder": { "id": BUILDER_ID },
                "metadata": {
                    "schema": "lambda-aitia.release-attestation-bundle.v1",
                    "bundleDigest": bundle_digest,
                    "actionAuthorized": false,
                },
            },
        },
    }))
}

pub(crate) fn mint_dsse_envelope_value(
    attestation: &Value,
    signing_seeds: &[String],
) -> Result<Value> {
    if signing_seeds.is_empty() {
        return Err(err(
            "DSSE export requires at least one Ed25519 signing seed",
        ));
    }
    let statement = build_intoto_statement(attestation)?;
    let statement_bytes = serde_json::to_vec(&statement)?;
    let pae = dsse_pae(INTOTO_PAYLOAD_TYPE, &statement_bytes);

    let mut sigs: Vec<(String, String)> = Vec::with_capacity(signing_seeds.len());
    for seed_hex in signing_seeds {
        let seed = hex_decode::<32>(seed_hex)?;
        let kp = Ed25519KeyPair::from_seed_unchecked(&seed)
            .map_err(|_| err("Failed to construct Ed25519 keypair for DSSE"))?;
        let sig = kp.sign(&pae);
        sigs.push((
            format!("{KEYID_PREFIX}{}", hex_encode(kp.public_key().as_ref())),
            base64_encode(sig.as_ref()),
        ));
    }
    sigs.sort_by(|a, b| a.0.cmp(&b.0));
    let sig_json: Vec<Value> = sigs
        .into_iter()
        .map(|(keyid, sig)| json!({ "keyid": keyid, "sig": sig }))
        .collect();

    Ok(json!({
        "payloadType": INTOTO_PAYLOAD_TYPE,
        "payload": base64_encode(&statement_bytes),
        "signatures": sig_json,
    }))
}

pub(crate) fn verify_dsse_envelope_value(envelope: &Value, trust_root: &Value) -> Result<Value> {
    if trust_root["schema"].as_str() != Some("lambda-aitia.tuf-trust-root.v1") {
        return Err(err(
            "Unsupported TUF trust root schema for DSSE verification",
        ));
    }
    let threshold = usize::try_from(
        trust_root["threshold"]
            .as_u64()
            .ok_or_else(|| err("TrustRoot missing threshold"))?,
    )
    .map_err(|_| err("Invalid TrustRoot threshold"))?;
    if threshold == 0 {
        return Err(err("TrustRoot threshold must be >= 1"));
    }
    let min_epoch = trust_root["minEpoch"]
        .as_u64()
        .ok_or_else(|| err("TrustRoot missing minEpoch"))?;
    let authorized: BTreeSet<String> = trust_root["authorizedKeys"]
        .as_array()
        .ok_or_else(|| err("TrustRoot missing authorizedKeys"))?
        .iter()
        .map(|v| {
            let k = v
                .as_str()
                .ok_or_else(|| err("TrustRoot authorizedKeys entry must be a string"))?;
            let _ = hex_decode::<32>(k)?;
            Ok(k.to_owned())
        })
        .collect::<Result<BTreeSet<String>>>()?;
    let revoked: BTreeSet<String> = trust_root
        .get("revokedKeys")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .map(|v| {
                    let k = v
                        .as_str()
                        .ok_or_else(|| err("TrustRoot revokedKeys entry must be a string"))?;
                    let _ = hex_decode::<32>(k)?;
                    Ok(k.to_owned())
                })
                .collect::<Result<BTreeSet<String>>>()
        })
        .transpose()?
        .unwrap_or_default();

    let payload_type = envelope["payloadType"]
        .as_str()
        .ok_or_else(|| err("DSSE envelope missing payloadType"))?;
    if payload_type != INTOTO_PAYLOAD_TYPE {
        return Err(err(
            "DSSE envelope payloadType mismatch (expected application/vnd.in-toto+json)",
        ));
    }
    let payload_b64 = envelope["payload"]
        .as_str()
        .ok_or_else(|| err("DSSE envelope missing base64 payload"))?;
    let payload_bytes = base64_decode_strict(payload_b64)?;
    let statement: Value = serde_json::from_slice(&payload_bytes)?;
    if statement["_type"].as_str() != Some(INTOTO_STATEMENT_TYPE) {
        return Err(err("DSSE payload is not an in-toto Statement v1"));
    }
    if statement["predicateType"].as_str() != Some(SLSA_PREDICATE_TYPE) {
        return Err(err(
            "DSSE statement predicateType is not SLSA Provenance v1.0",
        ));
    }
    let subjects = statement["subject"]
        .as_array()
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| err("DSSE in-toto statement missing non-empty subject list"))?;
    let metadata = &statement["predicate"]["runDetails"]["metadata"];
    if metadata["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "DSSE SLSA provenance must declare actionAuthorized: false",
        ));
    }
    let bundle_digest = metadata["bundleDigest"]
        .as_str()
        .ok_or_else(|| err("DSSE SLSA provenance missing bundleDigest"))?;
    let _ = strip_sha256_prefix(bundle_digest)?;
    let ext_params = &statement["predicate"]["buildDefinition"]["externalParameters"];
    let epoch = ext_params["epoch"]
        .as_u64()
        .ok_or_else(|| err("DSSE SLSA provenance missing epoch"))?;
    if epoch < min_epoch {
        return Err(err(
            "DSSE SLSA provenance rejected: epoch below TrustRoot minEpoch (rollback detected)",
        ));
    }
    let merkle_root = ext_params
        .get("merkleRoot")
        .and_then(Value::as_str)
        .map(str::to_owned);

    let pae = dsse_pae(payload_type, &payload_bytes);
    let pae_digest = crate::source_tree::sha256(&pae);
    let signatures = envelope["signatures"]
        .as_array()
        .ok_or_else(|| err("DSSE envelope missing signatures array"))?;
    let mut valid_signers = BTreeSet::new();
    for sig_entry in signatures {
        let keyid = sig_entry["keyid"]
            .as_str()
            .ok_or_else(|| err("DSSE signature missing keyid"))?;
        let pk_hex = keyid
            .strip_prefix(KEYID_PREFIX)
            .ok_or_else(|| err("DSSE signature keyid must start with ed25519:"))?;
        let pk_bytes = hex_decode::<32>(pk_hex)?;
        let sig_b64 = sig_entry["sig"]
            .as_str()
            .ok_or_else(|| err("DSSE signature missing base64 sig"))?;
        let sig_bytes = base64_decode_strict(sig_b64)?;
        if sig_bytes.len() != 64 {
            return Err(err("DSSE Ed25519 signature must decode to 64 bytes"));
        }
        UnparsedPublicKey::new(&ED25519, &pk_bytes)
            .verify(&pae, &sig_bytes)
            .map_err(|_| err("DSSE Ed25519 PAE signature verification failed"))?;
        if authorized.contains(pk_hex) && !revoked.contains(pk_hex) {
            valid_signers.insert(pk_hex.to_owned());
        }
    }
    if valid_signers.len() < threshold {
        return Err(err(format!(
            "DSSE TUF quorum not met: {} distinct non-revoked authorized signers < threshold {threshold}",
            valid_signers.len()
        )));
    }

    Ok(json!({
        "schema": "lambda-aitia.dsse-verdict.v1",
        "verified": true,
        "payloadType": payload_type,
        "statementType": INTOTO_STATEMENT_TYPE,
        "predicateType": SLSA_PREDICATE_TYPE,
        "subjectCount": subjects.len(),
        "bundleDigest": bundle_digest,
        "epoch": epoch,
        "merkleRoot": merkle_root,
        "validSignerCount": valid_signers.len(),
        "threshold": threshold,
        "paeDigest": pae_digest,
        "actionAuthorized": false,
    }))
}

/// Export a standard in-toto v1 / SLSA v1.0 DSSE PAE envelope from an Aitia release attestation
/// bundle signed with the supplied Ed25519 hex seeds (RFC 0019).
///
/// # Errors
/// Fails closed on invalid JSON, non-attestation schema, empty seed list, or invalid seed hex.
pub fn export_dsse_intoto_envelope_json(
    attestation_json: &str,
    signing_seeds_json: &str,
) -> Result<String> {
    let attestation: Value = serde_json::from_str(attestation_json)?;
    let seeds: Vec<String> = serde_json::from_str(signing_seeds_json)?;
    Ok(serde_json::to_string(&mint_dsse_envelope_value(
        &attestation,
        &seeds,
    )?)?)
}

/// Verify a standard in-toto v1 / SLSA v1.0 DSSE PAE envelope against a verifier-pinned TUF
/// `TrustRoot` (`lambda-aitia.tuf-trust-root.v1`) (RFC 0019).
///
/// # Errors
/// Fails closed on payloadType confusion, non-canonical Base64, forged PAE signatures,
/// duplicate-key inflation, revoked keys, epoch rollback, or unauthorized flags.
pub fn verify_dsse_intoto_envelope_json(
    envelope_json: &str,
    trust_root_json: &str,
) -> Result<String> {
    let envelope: Value = serde_json::from_str(envelope_json)?;
    let trust_root: Value = serde_json::from_str(trust_root_json)?;
    Ok(serde_json::to_string(&verify_dsse_envelope_value(
        &envelope,
        &trust_root,
    )?)?)
}

/// Assemble and self-verify a complete `lambda-aitia.portable-audit-bundle.v1` from an export
/// specification, optionally minting and embedding a standard in-toto v1 / SLSA v1.0 DSSE
/// envelope for the attestation chain head before verifying the resulting bundle fail-closed
/// against `workspace_sysml` (RFC 0019).
///
/// # Errors
/// Fails closed if required export inputs are missing, DSSE signing fails, or the exported
/// bundle fails offline air-gapped verification.
pub fn export_portable_audit_bundle_json(
    spec_json: &str,
    workspace_sysml: Option<&Path>,
) -> Result<String> {
    let spec: Value = serde_json::from_str(spec_json)?;
    let bundle = export_portable_audit_bundle_value(&spec, workspace_sysml)?;
    Ok(serde_json::to_string(&bundle)?)
}

pub(crate) fn export_portable_audit_bundle_value(
    spec: &Value,
    workspace_sysml: Option<&Path>,
) -> Result<Value> {
    let mut bundle = json!({
        "schema": "lambda-aitia.portable-audit-bundle.v1",
        "pinnedGenesisRoot": spec.get("pinnedGenesisRoot").cloned().unwrap_or(Value::Null),
        "rootRotations": spec.get("rootRotations").cloned().unwrap_or_else(|| json!([])),
        "attestationChain": spec.get("attestationChain").cloned().unwrap_or(Value::Null),
        "actionAuthorized": false,
    });
    if let Some(obj) = bundle.as_object_mut() {
        for opt_key in [
            "sysmlTufPolicy",
            "expectedRepoIds",
            "transparencyLog",
            "releaseAttestation",
            "dsseEnvelope",
        ] {
            if let Some(val) = spec.get(opt_key).filter(|v| !v.is_null()) {
                obj.insert(opt_key.to_owned(), val.clone());
            }
        }
        if let Some(seeds_val) = spec.get("dsseSigningSeeds").filter(|v| !v.is_null()) {
            let seeds: Vec<String> = serde_json::from_value(seeds_val.clone())?;
            let head_att = spec
                .get("attestationChain")
                .and_then(Value::as_array)
                .and_then(|arr| arr.last())
                .or_else(|| spec.get("releaseAttestation").filter(|v| !v.is_null()))
                .ok_or_else(|| err("Export spec missing attestation head for DSSE minting"))?;
            let dsse = mint_dsse_envelope_value(head_att, &seeds)?;
            obj.insert("dsseEnvelope".to_owned(), dsse);
        }
    }
    let _ = verify_portable_audit_bundle(&bundle, workspace_sysml)?;
    Ok(bundle)
}
