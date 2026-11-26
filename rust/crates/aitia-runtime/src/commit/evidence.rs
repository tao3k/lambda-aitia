// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Archived commit evidence verification and lineage projection.

use super::{
    CommitProposal, Result, check_execution_identity, dispatch_capability, err, proposal_binding,
    review_cut_value, review_input_digest,
};
use crate::{AitiaProgram, HostEffectClass, project, with_linked_program};
use aitia_jj::DescriptionRecovery;
use serde::Deserialize;
use serde_json::{Value, json};
use std::io;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RecoveredDescription {
    attempt: DescriptionRecovery,
    outcome: String,
}

/// Verify archived raw reports against an applied local revision. This reads
/// host observations and projects the original project configuration through
/// the linked Scheme Contract to determine model check applicability.
pub(crate) fn evidence(revision: &str, input: &str, query: bool) -> Result<Value> {
    with_linked_program(|program| Ok(evidence_with_program(&program, revision, input, query)))?
}

/// Verify archived raw reports against an applied local revision using an already-live
/// linked Scheme [`AitiaProgram`] session.
fn evidence_with_program(
    program: &AitiaProgram<'_>,
    revision: &str,
    input: &str,
    query: bool,
) -> Result<Value> {
    evidence_with_program_in(program, std::path::Path::new("."), revision, input, query)
}

/// Verify archived raw reports against an applied local revision in an explicit workspace
/// directory using an already-live linked Scheme [`AitiaProgram`] session.
pub(crate) fn evidence_with_program_in(
    program: &AitiaProgram<'_>,
    directory: &std::path::Path,
    revision: &str,
    input: &str,
    query: bool,
) -> Result<Value> {
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
            return Err(err("Description recovery remains unresolved"));
        }
        recovery.attempt
    };
    let facts = aitia_jj::read_applied_description_evidence(
        directory,
        revision,
        &record,
        crate::MAX_REQUEST_BYTES as usize,
    )?;
    let expected_cut = review_cut_value(&facts.original);
    if applied.is_some()
        && (artifact["cut"] != expected_cut
            || artifact["review"]["description"] != record.description)
    {
        return Err(err("Archived review does not match the applied rewrite"));
    }
    let reports = if applied.is_some() {
        artifact["executions"]
            .as_array()
            .ok_or_else(|| err("Archived execution list is missing"))?
            .as_slice()
    } else {
        &[]
    };
    let input_digest = review_input_digest(&expected_cut, &facts.project_sources, &facts.changes)?;
    let changes = serde_json::to_value(&facts.changes)?;
    verify_archived_jj_reports(reports, &input_digest, &changes, &facts.configuration)?;
    let model_paths = project::affected_sysml_paths(&facts.changes);
    let archived_model = applied
        .map(|_| &artifact["modelCheck"])
        .filter(|model| !model.is_null());
    if archived_model.is_some_and(|model| {
        model_paths.is_empty()
            || model["paths"] != json!(model_paths)
            || model["status"] != "passed"
    }) {
        return Err(err("Archived SysML observation is out of scope"));
    }
    let evidence = RecordedEvidence {
        revision,
        archived_context: applied.and_then(|_| artifact["review"]["context"].as_str()),
        proposal: if applied.is_some() {
            Some(
                CommitProposal::deserialize(&artifact["proposal"]).map_err(|error| {
                    io::Error::new(
                        io::ErrorKind::InvalidData,
                        format!("Invalid archived commit proposal: {error}"),
                    )
                })?,
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
    verified_evidence(program, evidence, query)
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
        return Err(err("Archived check method is outside the recorded policy"));
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
            return Err(err(format!("Archived {method} report rejected")));
        }
    }
    Ok(())
}

struct RecordedEvidence<'a> {
    revision: &'a str,
    archived_context: Option<&'a str>,
    proposal: Option<CommitProposal>,
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
    let configuration = project::validate_project_manifest(program, &facts.project_sources)?;
    let checks = configuration
        .commit
        .as_ref()
        .map(project::commit_checks)
        .transpose()?
        .unwrap_or_default();
    let source_paths = configuration
        .commit
        .as_ref()
        .map(project::review_source_paths)
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
            .ok_or_else(|| err("Archived report digest is missing"))?;
        let identity = check_execution_identity(check, &input_digest, digest)?;
        if row["requirement"] != check["requirement"] || row["identity"] != identity {
            return Err(err(format!("Archived {method} report rejected")));
        }
        observations.push(json!({"method":method,"report":row["report"],"reportDigest":digest}));
    }
    if observations.len() != reports.len() {
        return Err(err("Archived check method is outside the recorded policy"));
    }
    if let Some(archived_model) = archived_model {
        if !model_applies {
            return Err(err("Archived SysML observation is out of scope"));
        }
        let actual = dispatch_capability(
            "sysml.parse-revision",
            HostEffectClass::HostRead,
            &json!({ "directory": ".", "revision": revision, "paths": model_paths }),
            None,
        )?;
        if actual["documents"] != json!(model_paths) || archived_model["report"] != actual {
            return Err(err("Archived SysML report rejected"));
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
            return Err(err(
                "Archived review context differs from the applied review",
            ));
        }
        if facts.review_proposal.as_deref() != Some(proposal_binding(&proposal)?.as_str()) {
            return Err(err(
                "Archived commit proposal differs from the applied review",
            ));
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
        let sysml_scopes = dispatch_capability(
            "sysml.revision-scopes",
            HostEffectClass::HostRead,
            &json!({
                "directory": facts.original.workspace_root().to_string_lossy(),
                "revision": revision,
                "enabled": configuration.model_check_enabled(),
            }),
            None,
        )?;
        graph["engineeringReview"] = json!({
            "naming": policy["naming"],
            "sysmlScopes": sysml_scopes,
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
