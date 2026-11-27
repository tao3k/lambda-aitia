// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Air-gapped offline attestation and supply-chain auditor (RFC 0014).
//!
//! Verifies a self-contained portable audit bundle (`lambda-aitia.portable-audit-bundle.v1`)
//! against an optional verifier-pinned `workspace.sysml` without source checkouts, JJ/Git
//! invocations, network access, or Scheme runtime boot. Never grants execution authority.

use super::{
    Result,
    attestation::{
        enforce_sysml_tuf_policy, verify_attestation_lineage_chain, verify_tuf_root_rotation_chain,
    },
    err,
    merkle::verify_repo_merkle_proof,
    transparency::compute_log_root,
    witness::{
        detect_checkpoint_equivocation_json, verify_checkpoint_transition_json,
        verify_signed_checkpoint_json,
    },
};
use serde_json::{Value, json};
use std::{collections::BTreeSet, io, path::Path};

#[derive(Default)]
struct TransparencyAuditSummary {
    verified: bool,
    origin: Option<String>,
    tree_size: Option<usize>,
    root_hash: Option<String>,
    witness_count: Option<usize>,
    consistency_verified: bool,
    gossip_peers_verified: usize,
    repo_inclusion_proofs_verified: usize,
    head_log_entry_bound: bool,
}

fn verify_transparency_log_section(
    tlog: &Value,
    head_digest: &str,
    head_merkle_root: Option<&str>,
) -> Result<TransparencyAuditSummary> {
    let policy = tlog
        .get("witnessPolicy")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("transparencyLog missing witnessPolicy"))?;
    let checkpoint = tlog
        .get("checkpoint")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("transparencyLog missing checkpoint"))?;
    let policy_str = serde_json::to_string(policy)?;
    let cp_str = serde_json::to_string(checkpoint)?;
    let cp_verdict: Value =
        serde_json::from_str(&verify_signed_checkpoint_json(&cp_str, &policy_str)?)?;
    let origin = cp_verdict["origin"].as_str().map(str::to_owned);
    let tree_size = usize::try_from(
        cp_verdict["treeSize"]
            .as_u64()
            .ok_or_else(|| err("Checkpoint verdict missing treeSize"))?,
    )
    .map_err(|_| err("Invalid checkpoint verdict treeSize"))?;
    let root_hash = cp_verdict["rootHash"]
        .as_str()
        .ok_or_else(|| err("Checkpoint verdict missing rootHash"))?
        .to_owned();
    let witness_count = usize::try_from(
        cp_verdict["validWitnessCount"]
            .as_u64()
            .ok_or_else(|| err("Checkpoint verdict missing validWitnessCount"))?,
    )
    .map_err(|_| err("Invalid checkpoint validWitnessCount"))?;

    let prior = tlog.get("priorCheckpoint").filter(|v| !v.is_null());
    let proof = tlog.get("consistencyProof").filter(|v| !v.is_null());
    let consistency_verified = match (prior, proof) {
        (Some(prior_cp), Some(cons_proof)) => {
            let prior_str = serde_json::to_string(prior_cp)?;
            let proof_str = serde_json::to_string(cons_proof)?;
            let _ =
                verify_checkpoint_transition_json(&prior_str, &cp_str, &proof_str, &policy_str)?;
            true
        }
        (None, None) => false,
        _ => {
            return Err(err(
                "transparencyLog requires both priorCheckpoint and consistencyProof together",
            ));
        }
    };

    let head_log_entry_bound = if let Some(entries_val) =
        tlog.get("entries").filter(|v| !v.is_null())
    {
        let entries = entries_val
            .as_array()
            .ok_or_else(|| err("transparencyLog.entries must be an array"))?;
        if entries.len() != tree_size {
            return Err(err(
                "transparencyLog.entries length does not match checkpoint treeSize",
            ));
        }
        let recomputed_root = compute_log_root(entries)?;
        if recomputed_root != root_hash {
            return Err(err(
                "transparencyLog.entries Merkle root does not match signed checkpoint rootHash",
            ));
        }
        let bound = entries.iter().any(|entry| {
            entry["bundleDigest"].as_str() == Some(head_digest)
                && head_merkle_root.is_none_or(|mr| entry["merkleRoot"].as_str() == Some(mr))
        });
        if !bound {
            return Err(err(
                "transparencyLog.entries does not commit to the verified attestation chain head",
            ));
        }
        true
    } else {
        false
    };

    let mut repo_inclusion_proofs_verified = 0usize;
    if let Some(proofs_val) = tlog.get("repoInclusionProofs").filter(|v| !v.is_null()) {
        let proofs = proofs_val
            .as_array()
            .ok_or_else(|| err("transparencyLog.repoInclusionProofs must be an array"))?;
        if !proofs.is_empty() {
            let expected_mr = head_merkle_root.ok_or_else(|| {
                err("Attestation head lacks merkleRoot required to verify repoInclusionProofs")
            })?;
            for inclusion_proof in proofs {
                if inclusion_proof["bundleDigest"].as_str() != Some(head_digest) {
                    return Err(err(
                        "Repo Merkle inclusion proof bundleDigest does not match attestation head",
                    ));
                }
                let _ = verify_repo_merkle_proof(inclusion_proof, expected_mr)?;
                repo_inclusion_proofs_verified += 1;
            }
        }
    }

    let mut gossip_peers_verified = 0usize;
    if let Some(peers_val) = tlog.get("peerCheckpoints").filter(|v| !v.is_null()) {
        let peers = peers_val
            .as_array()
            .ok_or_else(|| err("transparencyLog.peerCheckpoints must be an array"))?;
        for peer in peers {
            let (peer_cp, peer_proof) = if let Some(inner) = peer.get("checkpoint") {
                (inner, peer.get("consistencyProof").filter(|v| !v.is_null()))
            } else {
                (peer, None)
            };
            let peer_cp_str = serde_json::to_string(peer_cp)?;
            let peer_proof_str = peer_proof.map(serde_json::to_string).transpose()?;
            let gossip: Value = serde_json::from_str(&detect_checkpoint_equivocation_json(
                &cp_str,
                &peer_cp_str,
                &policy_str,
                peer_proof_str.as_deref(),
            )?)?;
            match gossip["status"].as_str() {
                Some("consistent") => gossip_peers_verified += 1,
                Some("equivocation-detected") => {
                    return Err(err(format!(
                        "Air-gapped audit blocked by peer gossip equivocation ({}, digest={})",
                        gossip["conflictKind"].as_str().unwrap_or("unknown"),
                        gossip["evidenceDigest"].as_str().unwrap_or("none")
                    )));
                }
                Some("consistency-proof-required") => {
                    return Err(err(
                        "Air-gapped audit blocked: cross-size peer checkpoint lacks consistency proof",
                    ));
                }
                _ => return Err(err("Unexpected peer gossip verdict status")),
            }
        }
    }

    Ok(TransparencyAuditSummary {
        verified: true,
        origin,
        tree_size: Some(tree_size),
        root_hash: Some(root_hash),
        witness_count: Some(witness_count),
        consistency_verified,
        gossip_peers_verified,
        repo_inclusion_proofs_verified,
        head_log_entry_bound,
    })
}

fn load_verifier_pinned_sysml(path: &Path) -> Result<(Option<Value>, BTreeSet<String>)> {
    #[cfg(feature = "sysml")]
    {
        let manifest = crate::sysml::project_workspace_manifest_from_sysml(path)?;
        let policy = manifest
            .get("sysmlTufPolicy")
            .cloned()
            .filter(|v| !v.is_null());
        let repos = manifest["repos"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|r| r["repoId"].as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();
        Ok((policy, repos))
    }
    #[cfg(not(feature = "sysml"))]
    {
        let _ = path;
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "SysML workspace verification requires the `sysml` feature",
        )
        .into())
    }
}

/// Offline air-gapped verification of a portable multi-repo audit bundle (RFC 0014).
///
/// When `workspace_sysml` is provided, its OpenSysML-parsed `TufPolicy` and declared
/// repository inventory take strict precedence over untrusted fields inside `bundle`.
///
/// # Errors
/// Fails closed on schema mismatch, `actionAuthorized != false`, invalid root rotation
/// chain, SysML `TufPolicy` floor violation, broken parent hash or epoch order, invalid
/// Ed25519 signature, missing evidence reports, or incomplete repo coverage.
pub fn verify_portable_audit_bundle(
    bundle: &Value,
    workspace_sysml: Option<&Path>,
) -> Result<Value> {
    if bundle["schema"].as_str() != Some("lambda-aitia.portable-audit-bundle.v1") {
        return Err(err("Unsupported portable audit bundle schema"));
    }
    if bundle["actionAuthorized"].as_bool() != Some(false) {
        return Err(err(
            "Portable audit bundle must have actionAuthorized: false",
        ));
    }

    let (pinned_policy, pinned_repos) = match workspace_sysml {
        Some(path) => load_verifier_pinned_sysml(path)?,
        None => (None, BTreeSet::new()),
    };
    let effective_policy = pinned_policy.or_else(|| {
        bundle
            .get("sysmlTufPolicy")
            .cloned()
            .filter(|v| !v.is_null())
    });
    let mut expected_repos = pinned_repos;
    if expected_repos.is_empty()
        && let Some(arr) = bundle.get("expectedRepoIds").and_then(Value::as_array)
    {
        expected_repos.extend(arr.iter().filter_map(Value::as_str).map(str::to_owned));
    }

    let genesis_root = bundle
        .get("pinnedGenesisRoot")
        .filter(|v| !v.is_null())
        .ok_or_else(|| err("Portable audit bundle missing pinnedGenesisRoot"))?;
    let rotations: Vec<Value> = bundle
        .get("rootRotations")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let chain: Vec<Value> = if let Some(arr) = bundle
        .get("attestationChain")
        .and_then(Value::as_array)
        .cloned()
    {
        arr
    } else if let Some(single) = bundle
        .get("releaseAttestation")
        .filter(|v| !v.is_null())
        .cloned()
    {
        vec![single]
    } else {
        return Err(err(
            "Portable audit bundle requires `attestationChain` or `releaseAttestation`",
        ));
    };

    let roots = verify_tuf_root_rotation_chain(genesis_root, &rotations)?;
    let latest_root = roots
        .last()
        .ok_or_else(|| err("Verified TUF root timeline is empty"))?;
    let policy_enforced = if let Some(policy) = effective_policy.as_ref() {
        enforce_sysml_tuf_policy(policy, latest_root)?;
        true
    } else {
        false
    };

    let (verified_keys, lineage) =
        verify_attestation_lineage_chain(&chain, genesis_root, &rotations)?;
    for expected in &expected_repos {
        if !verified_keys.contains_key(expected) {
            return Err(err(&format!(
                "Air-gapped audit bundle missing expected repository `{expected}`"
            )));
        }
    }

    let head_merkle_root = chain
        .last()
        .and_then(|b| b["payload"]["merkleRoot"].as_str())
        .map(str::to_owned);
    let head_digest = lineage["headDigest"]
        .as_str()
        .ok_or_else(|| err("Verified attestation lineage missing headDigest"))?;
    let transparency = if let Some(tlog) = bundle.get("transparencyLog").filter(|v| !v.is_null()) {
        verify_transparency_log_section(tlog, head_digest, head_merkle_root.as_deref())?
    } else {
        TransparencyAuditSummary::default()
    };

    Ok(json!({
        "schema": "lambda-aitia.offline-audit-verdict.v1",
        "verified": true,
        "airGapped": true,
        "sysmlPolicyEnforced": policy_enforced,
        "rootVersion": lineage["rootVersion"],
        "chainLength": lineage["chainLength"],
        "epochs": lineage["epochs"],
        "genesisDigest": lineage["genesisDigest"],
        "headDigest": lineage["headDigest"],
        "headMerkleRoot": head_merkle_root,
        "verifiedRepoCount": verified_keys.len(),
        "verifiedRepoKeys": verified_keys,
        "transparencyVerified": transparency.verified,
        "checkpointOrigin": transparency.origin,
        "checkpointTreeSize": transparency.tree_size,
        "checkpointRootHash": transparency.root_hash,
        "checkpointWitnessCount": transparency.witness_count,
        "consistencyTransitionVerified": transparency.consistency_verified,
        "gossipPeersVerified": transparency.gossip_peers_verified,
        "repoInclusionProofsVerified": transparency.repo_inclusion_proofs_verified,
        "headLogEntryBound": transparency.head_log_entry_bound,
        "actionAuthorized": false,
    }))
}

/// JSON string wrapper for FFI/PyO3 callers: verify a portable air-gapped audit bundle.
///
/// # Errors
/// Fails closed on malformed JSON or any air-gapped verification failure.
pub fn verify_portable_audit_bundle_json(
    bundle_json: &str,
    workspace_sysml: Option<&Path>,
) -> Result<String> {
    let bundle: Value = serde_json::from_str(bundle_json)?;
    Ok(serde_json::to_string(&verify_portable_audit_bundle(
        &bundle,
        workspace_sysml,
    )?)?)
}

pub(crate) fn run_verify_attestation_cli(
    rest: &[&str],
    bundle: &Value,
    usage: &str,
) -> Result<Value> {
    let workspace = match rest {
        [] => None,
        ["--workspace", path] => Some(Path::new(*path)),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into()),
    };
    verify_portable_audit_bundle(bundle, workspace)
}
