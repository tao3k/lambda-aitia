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
};
use serde_json::{Value, json};
use std::{collections::BTreeSet, io, path::Path};

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
