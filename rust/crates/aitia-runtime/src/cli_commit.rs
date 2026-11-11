// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use crate::AitiaProgram;
use aitia_jj::{DescriptionRecovery, WorkspaceCut, reconcile_description, reopen_description};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{env, fs, io, path::PathBuf};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

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
            return Err(io::Error::other("Governance policy must be outside the workspace").into());
        }
        let bytes = fs::read(&policy)?;
        let authority: Authority = serde_json::from_slice(&bytes)?;
        if authority.project != project || authority.workspace != workspace {
            return Err(io::Error::other("Governance policy does not own this project cut").into());
        }
        let journal = policy.with_extension("sqlite");
        if fs::symlink_metadata(&journal).is_ok_and(|metadata| !metadata.is_file()) {
            return Err(io::Error::other("Governance journal must be a regular file").into());
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
            return Err(io::Error::other("Governance policy changed").into());
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
pub(super) struct Apply {
    pub draft: super::cli::CommitNarration,
    attempt: DescriptionRecovery,
    approval: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Recovery {
    approval: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DirectRecovery {
    attempt: DescriptionRecovery,
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

pub(super) fn prepare(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    report: &mut Value,
) -> Result<()> {
    let project = report["policy"]["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing project identity"))?;
    let description = description(report)?;
    let prepared = aitia_jj::prepare_description(cut, description)?;
    let record = prepared.proposed_receipt().recovery_record();
    let intent = journal(
        program,
        json!({
            "operation": "intent",
            "project": project,
            "attempt": serde_json::to_string(&record)?,
        }),
    )?;
    attach_revision(cut, report)?;
    report["intent"] = intent;
    report["attempt"] = serde_json::to_value(record)?;
    Ok(())
}

pub(super) fn attach_revision(cut: &WorkspaceCut, report: &mut Value) -> Result<()> {
    if report["policy"]["governance"] == "signed" {
        let project = report["policy"]["project"]
            .as_str()
            .ok_or_else(|| io::Error::other("Missing project identity"))?;
        report["governanceRevision"] = json!(Governance::load(cut, project)?.revision);
    }
    Ok(())
}

pub(super) fn record(
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
        return Err(io::Error::other("Governance decision scope or revision rejected").into());
    }
    if governance.transition(program, request)? != true {
        return Err(io::Error::other("Governance decision already recorded or retired").into());
    }
    Ok(json!({"recorded": true}))
}

pub(super) fn apply(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    report: &Value,
    apply: &Apply,
) -> Result<Value> {
    let project = report["policy"]["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing project identity"))?;
    let prepared = reopen_description(cut, description(report)?, &apply.attempt)?;
    if report["policy"]["governance"] == "default" {
        if apply.approval.is_some() {
            return Err(
                io::Error::other("This project does not use signed commit approvals").into(),
            );
        }
        // The draft has passed the recorded Project policy. JJ still
        // compares the cut under the operation-head lock before writing.
        return Ok(serde_json::to_value(prepared.publish(|_| true)?)?);
    }
    let approval = apply
        .approval
        .as_deref()
        .ok_or_else(|| io::Error::other("This project requires a signed commit approval"))?;
    let governance = Governance::load(cut, project)?;
    let attempt = serde_json::to_string(&prepared.proposed_receipt().recovery_record())?;
    let mut admission = Ok(Value::Null);
    let outcome = prepared.publish(|_| {
        admission = governance.transition(
            program,
            json!({
                "operation": "consume", "approval": approval, "attempt": attempt
            }),
        );
        admission.as_ref().is_ok_and(|value| *value == true)
    });
    admission?;
    Ok(serde_json::to_value(outcome?)?)
}

pub(super) fn recover(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    project: &str,
    input: &str,
) -> Result<Value> {
    if let Ok(attempt) = serde_json::from_str::<DirectRecovery>(input) {
        let outcome = reconcile_description(cut.workspace_root(), &attempt.attempt)?;
        return Ok(json!({"attempt": attempt.attempt, "outcome": outcome}));
    }
    let governance = Governance::load(cut, project)?;
    let request: Recovery = serde_json::from_str(input)?;
    let row = governance.transition(
        program,
        json!({
            "operation": "recover", "approval": request.approval
        }),
    )?;
    let attempt = row
        .as_str()
        .ok_or_else(|| io::Error::other("No admitted attempt"))?;
    let record = serde_json::from_str(attempt)?;
    let outcome = reconcile_description(cut.workspace_root(), &record)?;
    Ok(json!({ "attempt": record, "outcome": outcome }))
}

pub(super) fn push(
    program: &AitiaProgram<'_>,
    input: &str,
    remote: &str,
    bookmark: &str,
) -> Result<Value> {
    let mut input: Apply = serde_json::from_str(input)?;
    let current = aitia_jj::observe_workspace(std::path::Path::new("."))?;
    if current.operation_id() != input.attempt.resulting_operation
        || current.commit_id() != input.attempt.resulting_commit
        || reconcile_description(current.workspace_root(), &input.attempt)?
            != aitia_jj::DescriptionOutcome::Applied
    {
        return Err(io::Error::other("Push requires the current applied review receipt").into());
    }
    let (_, context) = super::cli::nasa_commit_report(program, None)?;
    if context["policy"]["governance"] != "default" || input.approval.is_some() {
        return Err(io::Error::other(
            "Signed description approval does not authorize a remote push",
        )
        .into());
    }
    // Recheck the written candidate using current observations. The original
    // narration and Org references must still render the reviewed description.
    input.draft.context = context["review"]["context"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing current review context"))?
        .to_owned();
    let (checked, report) = super::cli::nasa_commit_report(program, Some(&input.draft))?;
    let actual = description(&report)?;
    if checked != current || actual != input.attempt.description {
        return Err(io::Error::other("Written commit differs from the reviewed candidate").into());
    }
    Ok(serde_json::to_value(aitia_jj::push_reviewed_description(
        &checked,
        actual,
        remote,
        bookmark,
        || true,
    )?)?)
}

fn description(report: &Value) -> Result<&str> {
    report["review"]["description"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing reviewed description").into())
}
