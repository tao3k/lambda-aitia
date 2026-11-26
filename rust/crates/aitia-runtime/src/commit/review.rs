// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Commit narration contract types and standard-agnostic commit review report assembly.

use super::{
    Result, check_execution_identity, dispatch_capability, review_cut_value, review_input_digest,
};
use crate::{AitiaProgram, HostEffectClass, MAX_REQUEST_BYTES, project};
use aitia_jj::{
    DescriptionOrigin, WorkspaceCut, audit_recorded_configuration, observe_recorded_sources,
    observe_workspace, recorded_changes, recorded_review_bookmarks,
};
use std::io::{self, Write};

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CommitNarration {
    pub(crate) proposal: CommitProposal,
    narration: Narration,
    org: String,
    pub(crate) context: String,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
struct Narration {
    change: String,
    evidence: Vec<NarrationRow>,
    open: Vec<NarrationRow>,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
struct NarrationRow {
    obligation: String,
    text: String,
}

/// Agent intent is a proposal; source documents and changed paths are Host facts.
#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CommitProposal {
    identity: String,
    reference: String,
    r#type: String,
    scope: String,
    summary: String,
    rationale: String,
    language: String,
    #[serde(rename = "languageSource")]
    language_source: String,
}

fn compiled_policy_context() -> &'static str {
    // The bridge's archive is identified during the build. The manifest alone
    // names paths and can stay unchanged when their Scheme contents change.
    // Runtime reads neither build files nor a Scheme checkout.
    env!("AITIA_PROGRAM_CONTEXT")
}

fn observe_commit_provider(
    cut: &WorkspaceCut,
) -> std::result::Result<
    (
        Vec<aitia_jj::RecordedReviewBookmark>,
        crate::review_provider::ReviewObservation,
    ),
    aitia_jj::JjObservationError,
> {
    let bookmarks = recorded_review_bookmarks(cut)?;
    let observation = crate::review_provider::observe(&bookmarks, cut.commit_id());
    Ok((bookmarks, observation))
}

pub(crate) fn commit_review_report(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    draft: Option<&CommitNarration>,
    origin: Option<&DescriptionOrigin>,
    preview: bool,
) -> Result<(
    WorkspaceCut,
    serde_json::Value,
    Vec<aitia_jj::RecordedReviewBookmark>,
)> {
    let (cut, project_sources) = observed;
    if origin.is_some_and(|observed| observed.current() != &cut) {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    let source = project::recorded_configuration_input(&project_sources)?;
    let (review_configuration, projection) = program.resolve_project_config(&source)?;
    let configuration = project::decode_configuration_projection(&projection)?;
    // The JJ owner proves identical tree, parents and change identity. Read
    // those immutable inputs at the current anchor, but assess the original
    // review cut instead of silently replacing the user's reviewed context.
    let review_cut = origin.map_or(&cut, DescriptionOrigin::original);
    let policy = configuration
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile in the recorded project"))?;
    let changes = recorded_changes(&cut)?;
    let model_paths = if configuration.model_check_enabled() {
        project::affected_sysml_paths(&changes)
    } else {
        Vec::new()
    };
    let (model, sysml_scopes, (bookmarks, provider)) = std::thread::scope(|scope| {
        let provider = scope.spawn(|| observe_commit_provider(&cut));
        let sysml_obs = dispatch_capability(
            "sysml.parse-workspace",
            HostEffectClass::HostRead,
            &serde_json::json!({
                "directory": cut.workspace_root().to_string_lossy(),
                "mode": "commit",
                "paths": model_paths,
                "enabled": configuration.model_check_enabled(),
            }),
            None,
        )?;
        let model = (!sysml_obs["model"].is_null()).then(|| sysml_obs["model"].clone());
        let sysml_scopes = sysml_obs["scopes"].clone();
        let provider = provider
            .join()
            .map_err(|_| io::Error::other("PR observation worker panicked"))??;
        Ok::<_, Box<dyn std::error::Error>>((model, sysml_scopes, provider))
    })?;
    let requested_paths = project::review_source_paths(policy)?;
    let mut sources = Vec::new();
    let mut source_errors = Vec::new();
    for (path, result) in
        observe_recorded_sources(&cut, &requested_paths, usize::try_from(MAX_REQUEST_BYTES)?)?
    {
        match result {
            Ok(text) => sources.push(serde_json::json!({ "path": path, "text": text })),
            Err(error) => {
                source_errors.push(serde_json::json!({ "path": path, "error": error.to_string() }))
            }
        }
    }
    let cut_value = review_cut_value(review_cut);
    let input_digest = review_input_digest(&cut_value, &project_sources, &changes)?;
    let selected_checks = project::commit_checks(policy)?;
    let mut execution = Vec::new();
    let mut reports = Vec::new();
    for check in selected_checks {
        if changes.is_empty() {
            break;
        }
        let report = match check["method"].as_str() {
            Some("jj.recorded-change") => serde_json::to_value(&changes)?,
            Some("jj.configuration-audit") => match origin {
                Some(observed) => serde_json::to_value(observed.configuration())?,
                None => serde_json::to_value(audit_recorded_configuration(&cut)?)?,
            },
            _ => continue,
        };
        let report_digest = crate::source_tree::sha256(&serde_json::to_vec(&report)?);
        let identity = check_execution_identity(check, &input_digest, &report_digest)?;
        let mut observation = serde_json::json!({
            "requirement": check["requirement"],
            "method": check["method"],
            "identity": identity,
            "inputDigest": input_digest,
            "reportDigest": report_digest,
        });
        execution.push(observation.clone());
        observation["report"] = report;
        reports.push(observation);
    }
    // Git configuration can change without advancing the JJ operation.
    if recorded_review_bookmarks(&cut)? != bookmarks {
        return Err(io::Error::other("JJ review bookmark configuration changed").into());
    }
    let mut request = serde_json::json!({
        "cut": cut_value,
        "checks": execution,
        "ruleContext": compiled_policy_context(),
        "routeContext": crate::source_tree::sha256(&serde_json::to_vec(
            &bookmarks.iter().map(|bookmark| (bookmark, &bookmark.route_identity)).collect::<Vec<_>>(),
        )?),
        "preview": preview,
        "sources": sources,
        "paths": changes.iter().map(|change| change.path.as_str()).collect::<Vec<_>>(),
        "providerBookmarks": bookmarks,
        "providerReview": provider,
        "modelCheck": model,
        "sysmlScopes": sysml_scopes,
    });
    if let Some(draft) = draft {
        request["draft"] = serde_json::to_value(draft)?;
    }
    let mut payload_size = RequestSize(0);
    serde_json::to_writer(&mut payload_size, &request)?;
    // The rooted configuration and the remaining request share the existing
    // budget, including the former projectSources member's framing.
    if payload_size.0 + source.len() + "\"projectSources\":,".len() > MAX_REQUEST_BYTES as usize {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "AITIA input exceeds 4 MiB").into());
    }
    let review = program.commit_review(&review_configuration, &request)?;
    if observe_workspace(cut.workspace_root())? != cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    let result = serde_json::json!({
        "cut": cut_value,
        "policy": policy,
        "changes": changes,
        // Preserve the host-produced observations as well as their bindings.
        // A receipt identity alone cannot recover the original check report.
        "executions": reports,
        "sourceErrors": source_errors,
        "languageSources": sources,
        "proposal": draft.map(|narration| &narration.proposal),
        "recordedReviewBookmarks": request["providerBookmarks"],
        "providerReview": request["providerReview"],
        "modelCheck": request["modelCheck"],
        "review": review,
    });
    Ok((cut, result, bookmarks))
}

// Keep the request limit in serialized bytes without allocating a wire string.
struct RequestSize(usize);

impl Write for RequestSize {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0 += bytes.len();
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}
