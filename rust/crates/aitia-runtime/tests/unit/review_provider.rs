// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::{ReviewObservation, observe_with};
use aitia_jj::RecordedReviewBookmark;
use serde_json::{Value, json};

const HEAD: &str = "published";

fn bookmark() -> RecordedReviewBookmark {
    RecordedReviewBookmark {
        remote: "origin".into(),
        bookmark: "work/feature".into(),
        commit: Some(HEAD.into()),
        github_repository: Some("owner/project".into()),
        route_identity: None,
    }
}

fn pull() -> Value {
    json!({
        "number": 2, "state": "open", "updated_at":"2026-11-12T00:00:00Z",
        "head": {"ref": "work/feature", "sha": HEAD, "repo": {"full_name": "Owner/Project"}},
        "base": {"ref": "main", "sha": "base", "repo": {"full_name": "owner/project"}}
    })
}

fn checks() -> Value {
    json!({
        "total_count": 1,
        "check_runs": [{
            "id": 1, "name": "Build", "status": "completed", "conclusion": "success",
            "head_sha": HEAD, "app": {"id": 7, "slug": "github-actions"}
        }]
    })
}

#[test]
fn captures_provider_observation_without_promoting_parent_checks() {
    for candidate in ["local", HEAD] {
        let observation = observe_with(&[bookmark()], candidate, |path, query| match path {
            "/repos/owner/project/pulls" => {
                assert!(query.contains(&("head", "owner:work/feature")));
                Some(json!([pull()]))
            }
            "/repos/owner/project/commits/published/check-runs" => Some(checks()),
            _ => panic!("unexpected provider request: {path}"),
        });
        assert!(matches!(
            observation,
            ReviewObservation::Observed {
                number: 2, ref target_revision, on_candidate, checks: Some(ref rows), ..
            } if target_revision == "base" && on_candidate == (candidate == HEAD) && rows.len() == 1
        ));
    }
}

#[test]
fn rejects_ambiguous_forged_and_stale_associations_before_check_lookup() {
    let no_read = |_: &str, _: &[(&str, &str)]| panic!("unexpected provider request");
    assert_eq!(
        observe_with(&[], HEAD, no_read),
        ReviewObservation::NoBookmark
    );
    assert_eq!(
        observe_with(&[bookmark(), bookmark()], HEAD, no_read),
        ReviewObservation::AmbiguousBookmark
    );
    for (key, field, value, expected) in [
        (
            "head",
            "repo",
            json!({"full_name":"impostor/project"}),
            ReviewObservation::UnmatchedPullRequest,
        ),
        (
            "base",
            "repo",
            json!({"full_name":"other/project"}),
            ReviewObservation::UnmatchedPullRequest,
        ),
        (
            "base",
            "sha",
            json!(""),
            ReviewObservation::UnmatchedPullRequest,
        ),
        (
            "head",
            "ref",
            json!("wrong/branch"),
            ReviewObservation::UnmatchedPullRequest,
        ),
        (
            "head",
            "sha",
            json!("new-head"),
            ReviewObservation::StaleHead,
        ),
    ] {
        let mut changed = pull();
        changed[key][field] = value;
        assert_eq!(
            observe_with(&[bookmark()], HEAD, |path, _| {
                assert!(path.ends_with("/pulls"));
                Some(json!([changed]))
            }),
            expected
        );
    }
    assert_eq!(
        observe_with(&[bookmark()], HEAD, |_, _| Some(json!([pull(), pull()]))),
        ReviewObservation::AmbiguousPullRequest
    );
}

#[test]
fn an_empty_pull_list_requires_an_exact_live_branch_head() {
    let mut bookmark = bookmark();
    bookmark.bookmark = "work/feature#é%".into();
    let branch_ref = |name: &str, kind: &str, sha: &str| json!({"ref": name, "object": {"type": kind, "sha": sha}});
    let reference = "refs/heads/work/feature#é%";
    for (branch, expected) in [
        (
            Some(branch_ref(reference, "commit", HEAD)),
            ReviewObservation::NoOpenPullRequest {
                repository: "owner/project".into(),
                remote: "origin".into(),
                source: bookmark.bookmark.clone(),
                head_revision: HEAD.into(),
            },
        ),
        (
            Some(branch_ref(reference, "commit", "moved")),
            ReviewObservation::StaleHead,
        ),
        (
            Some(branch_ref("refs/heads/work/feature", "commit", HEAD)),
            ReviewObservation::UnmatchedBranchRef,
        ),
        (
            Some(branch_ref(reference, "tag", HEAD)),
            ReviewObservation::UnmatchedBranchRef,
        ),
        (Some(json!([])), ReviewObservation::Unavailable),
        (None, ReviewObservation::Unavailable),
    ] {
        let observed = observe_with(
            std::slice::from_ref(&bookmark),
            HEAD,
            |path, query| match path {
                "/repos/owner/project/pulls" => {
                    assert!(query.contains(&("head", "owner:work/feature#é%")));
                    Some(json!([]))
                }
                "/repos/owner/project/git/ref/heads/work/feature%23%C3%A9%25" => {
                    assert!(query.is_empty());
                    branch.clone()
                }
                _ => panic!("unexpected provider request: {path}"),
            },
        );
        assert_eq!(observed, expected);
    }
}

#[test]
fn check_list_requires_the_exact_head_and_a_complete_response() {
    let mut stale = checks();
    stale["check_runs"][0]["head_sha"] = json!("different");
    let mut incomplete = checks();
    incomplete["total_count"] = json!(2);
    let mut repeated = checks();
    let row = repeated["check_runs"][0].clone();
    repeated["check_runs"].as_array_mut().unwrap().push(row);
    repeated["total_count"] = json!(2);
    for value in [stale, incomplete, repeated] {
        assert!(matches!(
            observe_with(&[bookmark()], HEAD, |path, _| {
                if path.ends_with("/pulls") {
                    Some(json!([pull()]))
                } else {
                    Some(value.clone())
                }
            }),
            ReviewObservation::Observed { checks: None, .. }
        ));
    }
}

#[test]
fn check_observations_have_stable_order() {
    let mut unordered = checks();
    let mut later = unordered["check_runs"][0].clone();
    later["id"] = json!(2);
    unordered["check_runs"]
        .as_array_mut()
        .unwrap()
        .insert(0, later);
    unordered["total_count"] = json!(2);
    let observation = observe_with(&[bookmark()], HEAD, |path, _| {
        if path.ends_with("/pulls") {
            Some(json!([pull()]))
        } else {
            Some(unordered.clone())
        }
    });
    let facts = serde_json::to_value(observation).unwrap();
    assert_eq!(facts["checks"][0]["id"], 1);
    assert_eq!(facts["checks"][1]["id"], 2);
}
