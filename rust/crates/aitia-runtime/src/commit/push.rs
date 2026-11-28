// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Reviewed Git push verification, route matching, and push recovery.

use super::{Apply, Result, commit_review_report, description, dispatch_capability, err};
use crate::{HostEffectClass, with_linked_program};
use aitia_jj::DescriptionRecovery;
use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DirectRecovery {
    attempt: DescriptionRecovery,
}

pub(crate) fn recover_push(input: &str, remote: &str, bookmark: &str) -> Result<Value> {
    let recovery: DirectRecovery = serde_json::from_str(input)?;
    let payload = json!({
        "directory": ".",
        "attempt": recovery.attempt,
        "remote": remote,
        "bookmark": bookmark,
    });
    dispatch_capability(
        "gitops.jj.recover-push",
        HostEffectClass::HostRead,
        &payload,
        None,
    )
}

pub(crate) fn push(input: &str, remote: &str, bookmark: &str) -> Result<Value> {
    let input: Apply = serde_json::from_str(input)?;
    if input.approval.is_some() {
        return Err(err(
            "Signed description approval does not authorize a remote push",
        ));
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
        return Err(err(
            "Commit review context is stale; review the current applied preview before pushing",
        ));
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
        Ok(commit_review_report(
            &program,
            observed,
            Some(&input.draft),
            Some(&origin),
            false,
        ))
    })??;
    if report["policy"]["governance"] != "default" {
        return Err(err(
            "Signed description approval does not authorize a remote push",
        ));
    }
    if report["review"]["context"].as_str() != Some(input.draft.context.as_str()) {
        return Err(err(
            "Commit review context is stale; review the current applied preview before pushing",
        ));
    }
    let actual = description(&report)?;
    if checked != current || actual != input.attempt.description {
        return Err(err("Written commit differs from the reviewed candidate"));
    }
    let reviewed_route = &report["review"]["pullRequest"];
    if !reviewed_route.is_null()
        && (reviewed_route["remote"].as_str() != Some(remote)
            || reviewed_route["source"].as_str() != Some(bookmark))
    {
        return Err(err("Push destination differs from the reviewed PR source"));
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

#[cfg(test)]
#[path = "../../tests/unit/cli_commit.rs"]
mod tests;
