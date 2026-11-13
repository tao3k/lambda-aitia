// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::push_route_matches;
use crate::review_provider::ReviewObservation;
use aitia_jj::{PushRemote, RecordedReviewBookmark};
use serde_json::{Value, json};

fn github() -> PushRemote {
    PushRemote::GitHub("team/project".into())
}

fn no_pr() -> ReviewObservation {
    ReviewObservation::NoOpenPullRequest {
        repository: "team/project".into(),
        remote: "origin".into(),
        source: "topic".into(),
        head_revision: "old".into(),
    }
}

fn observed(
    target: &str,
    target_revision: &str,
    updated_at: &str,
    number: u64,
) -> ReviewObservation {
    ReviewObservation::Observed {
        repository: "team/project".into(),
        remote: "origin".into(),
        number,
        source: "topic".into(),
        target: target.into(),
        target_revision: target_revision.into(),
        head_revision: "old".into(),
        updated_at: updated_at.into(),
        on_candidate: false,
        checks: None,
    }
}

fn report(field: &str, observation: ReviewObservation) -> Value {
    json!({
        "review": { (field): {
            "repository": "team/project",
            "remote": "origin",
            "source": "topic",
            "headRevision": "old"
        }},
        "providerReview": observation,
    })
}

fn admit(
    report: &Value,
    destination: PushRemote,
    bookmark: &str,
    head: &str,
    observation: ReviewObservation,
) -> bool {
    push_route_matches(
        report,
        destination,
        "origin",
        bookmark,
        head,
        "candidate",
        |route, cut| {
            assert_eq!(
                route,
                RecordedReviewBookmark {
                    remote: "origin".into(),
                    bookmark: "topic".into(),
                    commit: Some("old".into()),
                    github_repository: Some("team/project".into()),
                    route_identity: None,
                }
            );
            assert_eq!(cut, "candidate");
            observation
        },
    )
}

#[test]
fn push_requires_the_reviewed_github_destination_even_without_an_open_pr() {
    let absent = json!({});
    assert!(push_route_matches(
        &absent,
        PushRemote::Other,
        "origin",
        "topic",
        "old",
        "candidate",
        |_, _| panic!("local routes must not query GitHub"),
    ));
    assert!(!admit(&absent, github(), "topic", "old", no_pr()));
    assert!(!admit(
        &absent,
        PushRemote::UnresolvedGitHub,
        "topic",
        "old",
        no_pr()
    ));

    let verified = report("pullRequestAbsence", no_pr());
    assert!(admit(&verified, github(), "topic", "old", no_pr()));
    assert!(!admit(
        &verified,
        PushRemote::Other,
        "topic",
        "old",
        no_pr()
    ));
    let status_only = json!({"providerReview": {"status": "no-open-pull-request"}});
    assert!(!admit(&status_only, github(), "topic", "old", no_pr()));
    assert!(!admit(&verified, github(), "other", "old", no_pr()));
    assert!(!admit(&verified, github(), "topic", "new", no_pr()));

    let current = || observed("main", "base", "observed", 2);
    let associated = report("pullRequest", current());
    assert!(admit(&associated, github(), "topic", "old", current()));
    assert!(!admit(
        &associated,
        PushRemote::Other,
        "topic",
        "old",
        current()
    ));
    assert!(!admit(
        &associated,
        PushRemote::GitHub("other/project".into()),
        "topic",
        "old",
        current(),
    ));
}

#[test]
fn push_rejects_pr_drift_while_the_remote_branch_lease_stays_current() {
    let current = || observed("main", "base", "observed", 2);
    let associated = report("pullRequest", current());
    assert!(admit(&associated, github(), "topic", "old", current()));
    for changed in [
        observed("release", "base", "observed", 2),
        observed("main", "new-base", "observed", 2),
        observed("main", "base", "later", 2),
        observed("main", "base", "observed", 3),
        no_pr(),
        ReviewObservation::Unavailable,
    ] {
        assert!(!admit(&associated, github(), "topic", "old", changed));
    }
    assert!(!admit(
        &report("pullRequestAbsence", no_pr()),
        github(),
        "topic",
        "old",
        current(),
    ));
}

#[test]
fn push_refuses_a_changed_check_result_on_the_same_pr_head() {
    let with_conclusion = |conclusion: &str| {
        let mut observation = observed("main", "base", "observed", 2);
        if let ReviewObservation::Observed { checks, .. } = &mut observation {
            *checks = Some(
                serde_json::from_value(json!([{
                    "id":1,"name":"Build","status":"completed","conclusion":conclusion,
                    "head_sha":"old"
                }]))
                .unwrap(),
            );
        }
        observation
    };
    let reviewed = report("pullRequest", with_conclusion("failure"));
    assert!(admit(
        &reviewed,
        github(),
        "topic",
        "old",
        with_conclusion("failure"),
    ));
    assert!(!admit(
        &reviewed,
        github(),
        "topic",
        "old",
        with_conclusion("success"),
    ));
    assert!(!admit(
        &reviewed,
        github(),
        "topic",
        "old",
        observed("main", "base", "observed", 2),
    ));
}
