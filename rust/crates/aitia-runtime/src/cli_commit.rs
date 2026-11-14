// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use crate::{AitiaProgram, with_linked_program};
use aitia_jj::{
    DescriptionRecovery, WorkspaceCut, reconcile_description, reopen_reviewed_description,
};
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
    pub attempt: DescriptionRecovery,
    approval: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged, deny_unknown_fields)]
pub(super) enum CommitRecovery {
    Attempt { attempt: DescriptionRecovery },
    Approval { approval: String },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DirectRecovery {
    attempt: DescriptionRecovery,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RecoveredDescription {
    attempt: DescriptionRecovery,
    outcome: String,
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
    let prepared = aitia_jj::prepare_reviewed_description(
        cut,
        description,
        review_context(report)?,
        &proposal_binding(&super::cli::CommitProposal::deserialize(
            &report["proposal"],
        )?)?,
    )?;
    let record = prepared.proposed_receipt().recovery_record();
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
    let prepared = reopen_reviewed_description(
        cut,
        description(report)?,
        &apply.attempt,
        review_context(report)?,
        &proposal_binding(&super::cli::CommitProposal::deserialize(
            &report["proposal"],
        )?)?,
    )?;
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
                "operation": "consume", "approval": approval, "attempt": attempt,
                "reviewContext": report["review"]["context"]
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
    approval: &str,
) -> Result<Value> {
    let governance = Governance::load(cut, project)?;
    let row = governance.transition(
        program,
        json!({
            "operation": "recover", "approval": approval
        }),
    )?;
    let attempt = row
        .as_str()
        .ok_or_else(|| io::Error::other("No admitted attempt"))?;
    recover_attempt(cut.workspace_root(), &serde_json::from_str(attempt)?)
}

pub(super) fn recover_attempt(
    directory: &std::path::Path,
    record: &DescriptionRecovery,
) -> Result<Value> {
    let outcome = reconcile_description(directory, record)?;
    Ok(json!({ "attempt": record, "outcome": outcome }))
}

pub(super) fn review_cut_value(cut: &WorkspaceCut) -> Value {
    json!({
        "workspace": cut.workspace_name(),
        "change": cut.change_id(),
        "operation": cut.operation_id(),
        "commit": cut.commit_id(),
        "tree": cut.tree_id(),
        "parents": cut.parent_ids(),
    })
}

pub(super) fn review_input_digest(
    cut: &Value,
    sources: &aitia_jj::RecordedProjectSources,
    changes: &[aitia_jj::RecordedPathChange],
) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(&json!([
        cut, sources, changes
    ]))?))
}

pub(super) fn check_execution_identity(
    check: &Value,
    input_digest: &str,
    report_digest: &str,
) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(&json!([
        check,
        input_digest,
        report_digest
    ]))?))
}

/// Verify archived raw reports against an applied local revision. This reads
/// host observations and projects the original project configuration through
/// the linked Scheme Contract to determine model check applicability.
pub(super) fn evidence(revision: &str, input: &str, query: bool) -> Result<Value> {
    let artifact: Value = serde_json::from_str(input)?;
    let applied = artifact.get("receipt");
    let record: DescriptionRecovery = if let Some(receipt) = applied {
        let expected = &receipt["expected"];
        serde_json::from_value(json!({
            "workspace": expected["workspace_name"],
            "expected_operation": expected["operation_id"],
            "expected_commit": expected["commit_id"],
            "resulting_operation": receipt["resulting_operation"],
            "resulting_commit": receipt["resulting_commit"],
            "description": receipt["description"],
        }))?
    } else {
        let recovery = RecoveredDescription::deserialize(&artifact)?;
        if recovery.outcome != "applied" {
            return Err(io::Error::other("Description recovery remains unresolved").into());
        }
        recovery.attempt
    };
    let facts = aitia_jj::read_applied_description_evidence(
        std::path::Path::new("."),
        revision,
        &record,
        crate::MAX_REQUEST_BYTES as usize,
    )?;
    let expected_cut = review_cut_value(&facts.original);
    if applied.is_some()
        && (artifact["cut"] != expected_cut
            || artifact["review"]["description"] != record.description)
    {
        return Err(io::Error::other("Archived review does not match the applied rewrite").into());
    }
    let reports = if applied.is_some() {
        artifact["executions"]
            .as_array()
            .ok_or_else(|| io::Error::other("Archived execution list is missing"))?
            .as_slice()
    } else {
        &[]
    };
    let input_digest = review_input_digest(&expected_cut, &facts.project_sources, &facts.changes)?;
    let changes = serde_json::to_value(&facts.changes)?;
    verify_archived_jj_reports(reports, &input_digest, &changes, &facts.configuration)?;
    let model_paths = super::cli::affected_sysml_paths(&facts.changes);
    let archived_model = applied
        .map(|_| &artifact["modelCheck"])
        .filter(|model| !model.is_null());
    if archived_model.is_some_and(|model| {
        model_paths.is_empty()
            || model["paths"] != json!(model_paths)
            || model["status"] != "passed"
    }) {
        return Err(io::Error::other("Archived SysML observation is out of scope").into());
    }
    let evidence = RecordedEvidence {
        revision,
        archived_context: applied.and_then(|_| artifact["review"]["context"].as_str()),
        proposal: if applied.is_some() {
            Some(
                super::cli::CommitProposal::deserialize(&artifact["proposal"]).map_err(
                    |error| {
                        io::Error::new(
                            io::ErrorKind::InvalidData,
                            format!("Invalid archived commit proposal: {error}"),
                        )
                    },
                )?,
            )
        } else {
            None
        },
        archived_model,
        model_paths,
        facts,
        expected_cut,
        changes,
        reports,
        input_digest,
        description: record.description,
    };
    with_linked_program(|program| Ok(verified_evidence(&program, evidence, query)))?
}

// JJ supplies the raw facts. Scheme still selects the policy checks that
// can admit each report and determines which obligations remain open.
fn verify_archived_jj_reports(
    reports: &[Value],
    input_digest: &str,
    changes: &Value,
    configuration: &impl serde::Serialize,
) -> Result<()> {
    // These are the only report types emitted in the execution list by this
    // host. Whether a supported type is selected still depends on Scheme.
    if reports.iter().any(|row| {
        !matches!(
            row["method"].as_str(),
            Some("jj.recorded-change" | "jj.configuration-audit")
        )
    }) {
        return Err(
            io::Error::other("Archived check method is outside the recorded policy").into(),
        );
    }
    for (method, actual) in [
        ("jj.recorded-change", changes),
        (
            "jj.configuration-audit",
            &serde_json::to_value(configuration)?,
        ),
    ] {
        let mut matching = reports.iter().filter(|row| row["method"] == method);
        let Some(row) = matching.next() else {
            continue;
        };
        let digest = crate::source_tree::sha256(&serde_json::to_vec(actual)?);
        if matching.next().is_some()
            || row["report"] != *actual
            || row["reportDigest"] != digest
            || row["inputDigest"] != input_digest
        {
            return Err(io::Error::other(format!("Archived {method} report rejected")).into());
        }
    }
    Ok(())
}

struct RecordedEvidence<'a> {
    revision: &'a str,
    archived_context: Option<&'a str>,
    proposal: Option<super::cli::CommitProposal>,
    archived_model: Option<&'a Value>,
    model_paths: Vec<String>,
    facts: aitia_jj::AppliedDescriptionEvidence,
    expected_cut: Value,
    changes: Value,
    reports: &'a [Value],
    input_digest: String,
    description: String,
}

fn verified_evidence(
    program: &AitiaProgram<'_>,
    evidence: RecordedEvidence<'_>,
    query: bool,
) -> Result<Value> {
    let RecordedEvidence {
        revision,
        archived_context,
        proposal,
        archived_model,
        model_paths,
        facts,
        expected_cut,
        changes,
        reports,
        input_digest,
        description,
    } = evidence;
    let configuration = super::cli::validate_project_manifest(program, &facts.project_sources)?;
    let checks = configuration
        .commit
        .as_ref()
        .map(super::cli::commit_checks)
        .transpose()?
        .unwrap_or_default();
    let source_paths = configuration
        .commit
        .as_ref()
        .map(super::cli::review_source_paths)
        .transpose()?
        .unwrap_or_default();
    let policy_sources = aitia_jj::recorded_revision_source_entries(
        facts.original.workspace_root(),
        revision,
        &source_paths,
    )?;
    let model_applies = !model_paths.is_empty() && configuration.model_check_enabled();
    let checks = if facts.changes.is_empty() {
        &[]
    } else {
        checks
    };
    let mut graph = json!({
        "revision": revision,
        "changes": changes,
        "projectInputs": facts.project_inputs,
        "policySources": policy_sources.iter().map(|(path, entry)| json!({ "path": path, "entry": entry })).collect::<Vec<_>>(),
        "parsedDocuments": [],
        "query": query,
    });
    let mut observations = Vec::new();
    let mut missing = Vec::new();
    for method in ["jj.recorded-change", "jj.configuration-audit"] {
        let Some(check) = checks.iter().find(|check| check["method"] == method) else {
            continue;
        };
        let Some(row) = reports.iter().find(|row| row["method"] == method) else {
            missing.push(method);
            continue;
        };
        let digest = row["reportDigest"]
            .as_str()
            .ok_or_else(|| io::Error::other("Archived report digest is missing"))?;
        let identity = check_execution_identity(check, &input_digest, digest)?;
        if row["requirement"] != check["requirement"] || row["identity"] != identity {
            return Err(io::Error::other(format!("Archived {method} report rejected")).into());
        }
        observations.push(json!({"method":method,"report":row["report"],"reportDigest":digest}));
    }
    if observations.len() != reports.len() {
        return Err(
            io::Error::other("Archived check method is outside the recorded policy").into(),
        );
    }
    if let Some(archived_model) = archived_model {
        if !model_applies {
            return Err(io::Error::other("Archived SysML observation is out of scope").into());
        }
        let actual = reproduce_sysml_report(revision, &model_paths)?;
        if actual["documents"] != json!(model_paths) || archived_model["report"] != actual {
            return Err(io::Error::other("Archived SysML report rejected").into());
        }
        graph["parsedDocuments"] = actual["documents"].clone();
        let digest = crate::source_tree::sha256(&serde_json::to_vec(&actual)?);
        observations.push(json!({"method":"sysml.parse","report":actual,"reportDigest":digest}));
    } else if model_applies {
        missing.push("sysml.parse");
    }
    if let Some(proposal) = proposal {
        let policy = configuration.commit.as_ref().ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "Applied archive has no commit policy at the recorded revision",
            )
        })?;
        if facts
            .review_context
            .as_deref()
            .zip(archived_context)
            .is_none_or(|(recorded, archived)| recorded != archived)
        {
            return Err(io::Error::other(
                "Archived review context differs from the applied review",
            )
            .into());
        }
        if facts.review_proposal.as_deref() != Some(proposal_binding(&proposal)?.as_str()) {
            return Err(io::Error::other(
                "Archived commit proposal differs from the applied review",
            )
            .into());
        }
        let paths = policy_sources
            .iter()
            .map(|(path, _)| *path)
            .collect::<Vec<_>>();
        let bytes = aitia_jj::read_revision_files(
            facts.original.workspace_root(),
            revision,
            &paths,
            crate::MAX_REQUEST_BYTES as usize,
        )?;
        let sources = paths
            .iter()
            .zip(bytes)
            .filter_map(|(path, bytes)| {
                String::from_utf8(bytes)
                    .ok()
                    .map(|text| json!({"path": path, "text": text}))
            })
            .collect::<Vec<_>>();
        graph["engineeringReview"] = json!({
            "naming": policy["naming"],
            "project": policy["project"],
            "cut": expected_cut,
            "title": description.lines().next(),
            "proposal": proposal,
            "sources": sources,
        });
    }
    graph["reports"] = json!(
        observations
            .iter()
            .map(|row| &row["method"])
            .collect::<Vec<_>>()
    );
    graph["missingReports"] = json!(missing);
    let lineage = program.evidence_lineage(&serde_json::to_string(&graph)?)?;
    Ok(json!({
        "revision": revision,
        "original": expected_cut,
        "description": description,
        "observations": observations,
        "missingReports": missing,
        "lineage": serde_json::from_str::<Value>(&lineage)?,
    }))
}

#[cfg(feature = "sysml")]
fn reproduce_sysml_report(revision: &str, paths: &[String]) -> Result<Value> {
    crate::sysml::parse_model_report(|| {
        crate::sysml::revision_documents(std::path::Path::new("."), revision, paths)
    })
}

#[cfg(not(feature = "sysml"))]
fn reproduce_sysml_report(_revision: &str, _paths: &[String]) -> Result<Value> {
    Err(io::Error::other("SysML evidence verification is unavailable in this build").into())
}

pub(super) fn recover_push(input: &str, remote: &str, bookmark: &str) -> Result<Value> {
    let recovery: DirectRecovery = serde_json::from_str(input)?;
    let receipt = aitia_jj::recover_reviewed_push(
        std::path::Path::new("."),
        &recovery.attempt,
        remote,
        bookmark,
    )?;
    let outcome = if receipt.is_some() {
        "acknowledged"
    } else {
        "unresolved"
    };
    Ok(json!({"outcome": outcome, "receipt": receipt}))
}

pub(super) fn push(input: &str, remote: &str, bookmark: &str) -> Result<Value> {
    let input: Apply = serde_json::from_str(input)?;
    if input.approval.is_some() {
        return Err(io::Error::other(
            "Signed description approval does not authorize a remote push",
        )
        .into());
    }
    // Scheme emits lowercase SHA-256 contexts. A syntactically valid digest
    // still needs current review and destination checks below.
    if !input
        .draft
        .context
        .strip_prefix("sha256:")
        .is_some_and(|digest| {
            digest.len() == 64
                && digest
                    .bytes()
                    .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
        })
    {
        return Err(io::Error::other(
            "Commit review context is stale; review the current applied preview before pushing",
        )
        .into());
    }
    let observed = aitia_jj::observe_project_sources(
        std::path::Path::new("."),
        crate::MAX_REQUEST_BYTES as usize,
    )?;
    let current = observed.0.clone();
    let origin = aitia_jj::observe_description_origin(&current, &input.attempt)?;
    // A verified description rewrite changes repository identity, not the
    // original review. Current Scheme rules must still accept its exact context.
    let (checked, report, reviewed_routes) = with_linked_program(|program| {
        Ok(super::cli::nasa_commit_report(
            &program,
            observed,
            Some(&input.draft),
            Some(&origin),
            false,
        ))
    })??;
    if report["policy"]["governance"] != "default" {
        return Err(io::Error::other(
            "Signed description approval does not authorize a remote push",
        )
        .into());
    }
    if report["review"]["context"].as_str() != Some(input.draft.context.as_str()) {
        return Err(io::Error::other(
            "Commit review context is stale; review the current applied preview before pushing",
        )
        .into());
    }
    let actual = description(&report)?;
    if checked != current || actual != input.attempt.description {
        return Err(io::Error::other("Written commit differs from the reviewed candidate").into());
    }
    let reviewed_route = &report["review"]["pullRequest"];
    if !reviewed_route.is_null()
        && (reviewed_route["remote"].as_str() != Some(remote)
            || reviewed_route["source"].as_str() != Some(bookmark))
    {
        return Err(
            io::Error::other("Push destination differs from the reviewed PR source").into(),
        );
    }
    Ok(serde_json::to_value(aitia_jj::push_reviewed_description(
        &checked,
        actual,
        remote,
        bookmark,
        |destination, head, identity| {
            if !reviewed_routes.iter().any(|route| {
                route.remote == remote
                    && route.bookmark == bookmark
                    && route.commit.as_deref() == Some(head)
                    && route.route_identity.as_deref() == Some(identity)
            }) {
                return false;
            }
            push_route_matches(
                &report,
                destination,
                remote,
                bookmark,
                head,
                checked.commit_id(),
                |route, candidate| crate::review_provider::observe(&[route], candidate),
            )
        },
    )?)?)
}

fn push_route_matches(
    report: &Value,
    destination: aitia_jj::PushRemote,
    remote: &str,
    bookmark: &str,
    head: &str,
    candidate: &str,
    observe: impl FnOnce(
        aitia_jj::RecordedReviewBookmark,
        &str,
    ) -> crate::review_provider::ReviewObservation,
) -> bool {
    use aitia_jj::PushRemote;
    let review = &report["review"];
    let association = &review["pullRequest"];
    let absence = &review["pullRequestAbsence"];
    match destination {
        PushRemote::Other => association.is_null() && absence.is_null(),
        PushRemote::UnresolvedGitHub => false,
        PushRemote::GitHub(repository) => {
            let route = if association.is_null() {
                absence
            } else {
                association
            };
            route["repository"].as_str() == Some(&repository)
                && route["remote"].as_str() == Some(remote)
                && route["source"].as_str() == Some(bookmark)
                && route["headRevision"].as_str() == Some(head)
                // JJ has checked the local operation and selected its remote lease.
                // Re-read the provider before transport, without refreshing review.
                && serde_json::to_value(observe(
                    aitia_jj::RecordedReviewBookmark {
                        remote: remote.to_owned(),
                        bookmark: bookmark.to_owned(),
                        commit: Some(head.to_owned()),
                        github_repository: Some(repository),
                        route_identity: None,
                    },
                    candidate,
                ))
                .is_ok_and(|current| current == report["providerReview"])
        }
    }
}

fn proposal_binding(proposal: &super::cli::CommitProposal) -> Result<String> {
    Ok(crate::source_tree::sha256(&serde_json::to_vec(proposal)?))
}

fn review_context(report: &Value) -> Result<&str> {
    report["review"]["context"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing commit review context").into())
}

fn description(report: &Value) -> Result<&str> {
    report["review"]["description"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing reviewed description").into())
}

#[cfg(test)]
#[path = "../tests/unit/cli_commit.rs"]
mod tests;
