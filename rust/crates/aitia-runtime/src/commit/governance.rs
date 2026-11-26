// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Signed commit governance, journal admission, description preparation, application, and recovery.

use super::{
    CommitNarration, CommitProposal, Result, description, dispatch_capability, err, project_id,
    proposal_binding, review_context,
};
use crate::{AitiaProgram, HostEffectClass};
use aitia_jj::{DescriptionRecovery, WorkspaceCut, reopen_reviewed_description};
use ring::signature::KeyPair;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{env, fs, io, path::PathBuf};

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Authority {
    project: String,
    workspace: PathBuf,
    public_key: String,
}

struct Governance {
    authority: Authority,
    policy: PathBuf,
    journal: PathBuf,
    revision: String,
}

impl Governance {
    fn load(cut: &WorkspaceCut, project: &str) -> Result<Self> {
        let policy = env::var_os("AITIA_GOVERNANCE_POLICY")
            .ok_or_else(|| io::Error::other("Set the operator-owned AITIA_GOVERNANCE_POLICY"))?;
        let policy = fs::canonicalize(policy)?;
        let workspace = fs::canonicalize(cut.workspace_root())?;
        if policy.starts_with(&workspace) {
            return Err(err("Governance policy must be outside the workspace"));
        }
        let bytes = fs::read(&policy)?;
        let authority: Authority = serde_json::from_slice(&bytes)?;
        if authority.project != project || authority.workspace != workspace {
            return Err(err("Governance policy does not own this project cut"));
        }
        let journal = policy.with_extension("sqlite");
        if fs::symlink_metadata(&journal).is_ok_and(|metadata| !metadata.is_file()) {
            return Err(err("Governance journal must be a regular file"));
        }
        let revision = policy_revision(&policy, &bytes)?;
        Ok(Self {
            authority,
            policy,
            journal,
            revision,
        })
    }

    fn transition(&self, program: &AitiaProgram<'_>, mut request: Value) -> Result<Value> {
        if policy_revision(&self.policy, &fs::read(&self.policy)?)? != self.revision {
            return Err(err("Governance policy changed"));
        }
        request["project"] = json!(self.authority.project);
        request["journal"] = serde_json::to_value(&self.journal)?;
        request["revision"] = json!(self.revision);
        journal(program, request)
    }
}

fn policy_revision(policy: &std::path::Path, bytes: &[u8]) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(&(
        policy, bytes,
    ))?))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SignedDecision {
    message: String,
    signature: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, tag = "kind", rename_all_fields = "camelCase")]
enum Decision {
    #[serde(rename = "aitia.commit.approve.v1")]
    Approve {
        project: String,
        revision: String,
        approval: String,
        intent: String,
        not_before: u64,
        expires_at: u64,
    },
    #[serde(rename = "aitia.commit.revoke.v1")]
    Revoke {
        project: String,
        revision: String,
        approval: String,
    },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Apply {
    pub(crate) draft: CommitNarration,
    pub(crate) attempt: DescriptionRecovery,
    pub(crate) approval: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
pub(crate) enum CommitRecovery {
    Attempt { attempt: DescriptionRecovery },
    Approval { approval: String },
}

fn hex<const N: usize>(input: &str) -> Result<[u8; N]> {
    let invalid = || io::Error::other("Invalid Governance hex encoding");
    if input.len() != N * 2 || !input.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(invalid().into());
    }
    let mut result = [0; N];
    for (index, byte) in result.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&input[index * 2..index * 2 + 2], 16)?;
    }
    Ok(result)
}

fn journal(program: &AitiaProgram<'_>, request: Value) -> Result<Value> {
    Ok(serde_json::from_str(
        &program.commit_journal(&request.to_string())?,
    )?)
}

fn reviewed_frame<'a>(
    cut: &WorkspaceCut,
    report: &'a Value,
) -> Result<(&'a str, &'a str, String, Value)> {
    let project = project_id(report)?;
    let context = review_context(report)?;
    let proposal = CommitProposal::deserialize(&report["proposal"])?;
    let binding = proposal_binding(&proposal)?;
    let payload = json!({
        "directory": cut.workspace_root().to_string_lossy(),
        "expectedCommit": cut.commit_id(),
        "expectedOperation": cut.operation_id(),
        "description": description(report)?,
        "reviewContext": context,
        "proposalBinding": binding,
    });
    Ok((project, context, binding, payload))
}

pub(crate) fn prepare(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    report: &mut Value,
) -> Result<()> {
    let (project, context, _, payload) = reviewed_frame(cut, report)?;
    let record: DescriptionRecovery = serde_json::from_value(dispatch_capability(
        "gitops.jj.prepare-description",
        HostEffectClass::FencedEffect,
        &payload,
        Some(context.to_owned()),
    )?)?;
    let intent = journal(
        program,
        json!({
            "operation": "intent",
            "project": project,
            "attempt": serde_json::to_string(&record)?,
            "reviewContext": report["review"]["context"],
        }),
    )?;
    attach_revision(cut, report)?;
    report["intent"] = intent;
    report["attempt"] = serde_json::to_value(&record)?;
    Ok(())
}

pub(crate) fn attach_revision(cut: &WorkspaceCut, report: &mut Value) -> Result<()> {
    if report["policy"]["governance"] == "signed" {
        report["governanceRevision"] = json!(Governance::load(cut, project_id(report)?)?.revision);
    }
    Ok(())
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WorkflowHumanDecisionEnvelope {
    message: String,
    public_key: String,
    signature: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WorkflowHumanDecisionPayload {
    kind: String,
    decision_id: String,
    approver: String,
    intent: String,
    resolution: Value,
    not_before: u64,
    expires_at: u64,
}

/// Cryptographically verify a signed Ed25519 human decision envelope for workflow escalation gates.
///
/// Enforces exact Ed25519 signature verification, schema tag `"aitia.workflow.human-decision.v1"`,
/// non-empty identity/approver/intent fields, and wall-clock validity window (`notBefore <= now <= expiresAt`).
/// Never grants execution authority (`actionAuthorized: false`).
pub(crate) fn verify_signed_human_decision(raw: &Value) -> Result<Value> {
    let envelope: WorkflowHumanDecisionEnvelope = serde_json::from_value(raw.clone())?;
    let pubkey = hex::<32>(&envelope.public_key)?;
    let sig = hex::<64>(&envelope.signature)?;
    ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, pubkey)
        .verify(envelope.message.as_bytes(), &sig)
        .map_err(|_| err("Signed human decision Ed25519 signature rejected"))?;
    let payload: WorkflowHumanDecisionPayload = serde_json::from_str(&envelope.message)?;
    if payload.kind != "aitia.workflow.human-decision.v1" {
        return Err(err("Unsupported signed human decision kind"));
    }
    if payload.decision_id.trim().is_empty()
        || payload.approver.trim().is_empty()
        || payload.intent.trim().is_empty()
    {
        return Err(err(
            "Signed human decision missing required identity fields",
        ));
    }
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| err("System clock before UNIX epoch"))?
        .as_secs();
    if now < payload.not_before || now > payload.expires_at {
        return Err(err("Signed human decision outside validity window"));
    }
    Ok(json!({
        "verified": true,
        "decisionId": payload.decision_id,
        "approver": payload.approver,
        "intent": payload.intent,
        "resolution": payload.resolution,
        "publicKey": envelope.public_key,
        "messageDigest": crate::source_tree::sha256(envelope.message.as_bytes()),
        "actionAuthorized": false,
    }))
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Mint an offline-verifiable in-toto/SLSA-inspired Proof-Carrying Release Attestation Bundle
/// (`lambda-aitia.release-attestation-bundle.v1`) over a quiescent multi-repo protocol step.
///
/// Signs the canonical SHA-256 `bundleDigest` with Ed25519 using the caller-supplied 32-byte
/// hex seed (or an ephemeral deterministic test seed when omitted in local qualification).
/// Never grants execution authority (`actionAuthorized: false`).
///
/// # Errors
/// Fails closed if `step` is not `quiescent`, any repo evidence lineage has `missingReports`,
/// or the Ed25519 signing seed is malformed.
pub fn mint_release_attestation_bundle(
    step: &Value,
    signing_seed_hex: Option<&str>,
) -> Result<Value> {
    if step["state"].as_str() != Some("quiescent") {
        return Err(err(
            "Release attestation bundle requires a quiescent protocol step",
        ));
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
    let payload = json!({
        "schema": "lambda-aitia.release-attestation-payload.v1",
        "waves": step["waves"],
        "links": links,
        "earlyCutoffs": step.get("earlyCutoffs").cloned().unwrap_or_else(|| json!([])),
        "actionAuthorized": false,
    });
    let canonical = serde_json::to_string(&payload)?;
    let bundle_digest = crate::source_tree::sha256(canonical.as_bytes());
    let seed = match signing_seed_hex {
        Some(hex_str) => hex::<32>(hex_str)?,
        None => [0x42u8; 32],
    };
    let keypair = ring::signature::Ed25519KeyPair::from_seed_unchecked(&seed)
        .map_err(|_| err("Failed to construct Ed25519 attestation signing key"))?;
    let sig = keypair.sign(bundle_digest.as_bytes());
    Ok(json!({
        "schema": "lambda-aitia.release-attestation-bundle.v1",
        "payload": payload,
        "bundleDigest": bundle_digest,
        "publicKey": hex_encode(keypair.public_key().as_ref()),
        "signature": hex_encode(sig.as_ref()),
        "actionAuthorized": false,
    }))
}

/// Offline cryptographic verifier for a Proof-Carrying Release Attestation Bundle (RFC 0010).
///
/// Recomputes `bundleDigest` from canonical `payload`, verifies the Ed25519 signature,
/// enforces `actionAuthorized == false` and `missingReports == 0` across every repo link,
/// and returns the verified `repoId -> verificationKey` map for sound Adapton/Salsa memo reuse.
///
/// # Errors
/// Fails closed on schema mismatch, tampered payload/digest, forged signature, missing
/// evidence reports, or any unauthorized action claim.
pub fn verify_release_attestation_bundle(
    bundle: &Value,
) -> Result<std::collections::BTreeMap<String, String>> {
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
    let pubkey = hex::<32>(
        bundle["publicKey"]
            .as_str()
            .ok_or_else(|| err("Release attestation missing publicKey"))?,
    )?;
    let sig = hex::<64>(
        bundle["signature"]
            .as_str()
            .ok_or_else(|| err("Release attestation missing signature"))?,
    )?;
    ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, pubkey)
        .verify(claimed.as_bytes(), &sig)
        .map_err(|_| err("Release attestation Ed25519 signature rejected"))?;
    let links = payload["links"]
        .as_array()
        .ok_or_else(|| err("Release attestation missing links array"))?;
    if links.is_empty() {
        return Err(err("Release attestation contains zero repo links"));
    }
    let mut attested = std::collections::BTreeMap::new();
    for link in links {
        if link["missingReports"].as_u64() != Some(0) {
            return Err(err("Release attestation link contains missingReports"));
        }
        let rid = link["repoId"]
            .as_str()
            .ok_or_else(|| err("Release attestation link missing repoId"))?;
        let vkey = link["verificationKey"]
            .as_str()
            .ok_or_else(|| err("Release attestation link missing verificationKey"))?;
        if !vkey.starts_with("sha256:") {
            return Err(err(
                "Release attestation link verificationKey must be sha256",
            ));
        }
        attested.insert(rid.to_owned(), vkey.to_owned());
    }
    Ok(attested)
}

pub(crate) fn record(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    project: &str,
    input: &str,
) -> Result<Value> {
    let governance = Governance::load(cut, project)?;
    let signed: SignedDecision = serde_json::from_str(input)?;
    let key = hex::<32>(&governance.authority.public_key)?;
    ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, key)
        .verify(signed.message.as_bytes(), &hex::<64>(&signed.signature)?)
        .map_err(|_| io::Error::other("Governance decision signature rejected"))?;
    let (scope, revision, request) = match serde_json::from_str::<Decision>(&signed.message)? {
        Decision::Approve {
            project,
            revision,
            approval,
            intent,
            not_before,
            expires_at,
        } => (
            project,
            revision,
            json!({"operation": "approve", "approval": approval,
                "intent": intent, "notBefore": not_before, "expiresAt": expires_at}),
        ),
        Decision::Revoke {
            project,
            revision,
            approval,
        } => (
            project,
            revision,
            json!({"operation": "revoke", "approval": approval}),
        ),
    };
    if scope != project || revision != governance.revision {
        return Err(err("Governance decision scope or revision rejected"));
    }
    if governance.transition(program, request)? != true {
        return Err(err("Governance decision already recorded or retired"));
    }
    Ok(json!({ "recorded": true }))
}

pub(crate) fn apply(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    report: &Value,
    apply: &Apply,
) -> Result<Value> {
    let (project, context, binding, mut payload) = reviewed_frame(cut, report)?;
    if report["policy"]["governance"] == "default" {
        if apply.approval.is_some() {
            return Err(err("This project does not use signed commit approvals"));
        }
        payload["attempt"] = serde_json::to_value(&apply.attempt)?;
        return dispatch_capability(
            "gitops.jj.apply-description",
            HostEffectClass::FencedEffect,
            &payload,
            Some(context.to_owned()),
        );
    }
    let prepared =
        reopen_reviewed_description(cut, description(report)?, &apply.attempt, context, &binding)?;
    let approval = apply
        .approval
        .as_deref()
        .ok_or_else(|| err("This project requires a signed commit approval"))?;
    let governance = Governance::load(cut, project)?;
    let attempt = serde_json::to_string(&prepared.proposed_receipt().recovery_record())?;
    let mut admission = Ok(Value::Null);
    let outcome = prepared.publish(|_| {
        admission = governance.transition(
            program,
            json!({
                "operation": "consume",
                "approval": approval,
                "attempt": attempt,
                "reviewContext": report["review"]["context"]
            }),
        );
        admission.as_ref().is_ok_and(|value| *value == true)
    });
    admission?;
    Ok(serde_json::to_value(outcome?)?)
}

pub(crate) fn recover(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    project: &str,
    approval: &str,
) -> Result<Value> {
    let governance = Governance::load(cut, project)?;
    let row = governance.transition(
        program,
        json!({ "operation": "recover", "approval": approval }),
    )?;
    let attempt = row.as_str().ok_or_else(|| err("No admitted attempt"))?;
    recover_attempt(cut.workspace_root(), &serde_json::from_str(attempt)?)
}

pub(crate) fn recover_attempt(
    directory: &std::path::Path,
    record: &DescriptionRecovery,
) -> Result<Value> {
    dispatch_capability(
        "gitops.jj.reconcile-description",
        HostEffectClass::HostRead,
        &json!({ "directory": directory.to_string_lossy(), "attempt": record }),
        None,
    )
}
