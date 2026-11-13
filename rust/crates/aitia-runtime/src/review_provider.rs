// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Read-only GitHub facts for a single JJ-recorded remote bookmark.
//! This boundary does not interpret check conclusions or admit evidence.

use aitia_jj::RecordedReviewBookmark;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{fmt::Write as _, time::Duration};

#[derive(Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "kebab-case")]
pub(super) enum ReviewObservation {
    NoBookmark,
    AmbiguousBookmark,
    UnsupportedRemote,
    Unavailable,
    NoOpenPullRequest {
        repository: String,
        remote: String,
        source: String,
        #[serde(rename = "headRevision")]
        head_revision: String,
    },
    AmbiguousPullRequest,
    UnmatchedPullRequest,
    UnmatchedBranchRef,
    StaleHead,
    Observed {
        repository: String,
        remote: String,
        number: u64,
        source: String,
        target: String,
        #[serde(rename = "targetRevision")]
        target_revision: String,
        #[serde(rename = "headRevision")]
        head_revision: String,
        #[serde(rename = "updatedAt")]
        updated_at: String,
        #[serde(rename = "onCandidate")]
        on_candidate: bool,
        checks: Option<Vec<CheckRun>>,
    },
}

#[derive(Deserialize)]
struct BranchRef {
    #[serde(rename = "ref")]
    name: String,
    object: RefObject,
}

#[derive(Deserialize)]
struct RefObject {
    #[serde(rename = "type")]
    kind: String,
    sha: String,
}

fn encode_ref_path(reference: &str) -> String {
    let mut path = String::with_capacity(reference.len());
    for byte in reference.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~' | b'/') {
            path.push(char::from(byte));
        } else {
            write!(&mut path, "%{byte:02X}").expect("formatting into a string cannot fail");
        }
    }
    path
}

#[derive(Deserialize)]
struct PullRequest {
    number: u64,
    state: String,
    updated_at: String,
    head: PullRef,
    base: PullRef,
}

#[derive(Deserialize)]
struct PullRef {
    #[serde(rename = "ref")]
    name: String,
    sha: String,
    repo: Option<Repository>,
}

impl PullRef {
    fn belongs_to(&self, repository: &str) -> bool {
        self.repo
            .as_ref()
            .is_some_and(|repo| repo.full_name.eq_ignore_ascii_case(repository))
    }
}

#[derive(Deserialize)]
struct Repository {
    full_name: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq, Serialize)]
pub(super) struct CheckRun {
    id: u64,
    name: String,
    status: String,
    conclusion: Option<String>,
    app: Option<CheckApp>,
    #[serde(rename(deserialize = "head_sha", serialize = "headRevision"))]
    head_revision: String,
    #[serde(rename(deserialize = "details_url", serialize = "detailsUrl"))]
    details_url: Option<String>,
}

#[derive(Debug, Deserialize, PartialEq, Eq, Serialize)]
struct CheckApp {
    id: u64,
    slug: Option<String>,
}

#[derive(Deserialize)]
struct CheckRuns {
    total_count: usize,
    check_runs: Vec<CheckRun>,
}

pub(super) fn observe(bookmarks: &[RecordedReviewBookmark], candidate: &str) -> ReviewObservation {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(3)))
        .https_only(true)
        .max_redirects(0)
        .build()
        .into();
    observe_with(bookmarks, candidate, |path, query| {
        let mut request = agent
            .get(format!("https://api.github.com{path}"))
            .header("Accept", "application/vnd.github+json")
            .header("Cache-Control", "no-cache")
            .header("User-Agent", "lambda-aitia")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .query_pairs(query.iter().copied());
        if let Ok(token) = std::env::var("GH_TOKEN")
            && !token.is_empty()
        {
            request = request.header("Authorization", format!("Bearer {token}"));
        }
        let mut response = request.call().ok()?;
        if response.status() != 200 {
            return None;
        }
        let next_page = response.headers().get_all("link").iter().any(|value| {
            value
                .to_str()
                .map_or(true, |text| text.contains("rel=\"next\""))
        });
        if next_page {
            return None;
        }
        let bytes = response
            .body_mut()
            .with_config()
            .limit(crate::MAX_REQUEST_BYTES)
            .read_to_vec()
            .ok()?;
        serde_json::from_slice(&bytes).ok()
    })
}

fn observe_with(
    bookmarks: &[RecordedReviewBookmark],
    candidate: &str,
    mut read: impl FnMut(&str, &[(&str, &str)]) -> Option<Value>,
) -> ReviewObservation {
    let bookmark = match bookmarks {
        [] => return ReviewObservation::NoBookmark,
        [bookmark] => bookmark,
        _ => return ReviewObservation::AmbiguousBookmark,
    };
    let Some(repository) = &bookmark.github_repository else {
        return ReviewObservation::UnsupportedRemote;
    };
    let Some(commit) = &bookmark.commit else {
        return ReviewObservation::AmbiguousBookmark;
    };
    let Some((owner, _)) = repository.split_once('/') else {
        return ReviewObservation::UnsupportedRemote;
    };
    let head = format!("{owner}:{}", bookmark.bookmark);
    let Some(pulls) = read(
        &format!("/repos/{repository}/pulls"),
        &[("state", "open"), ("head", &head), ("per_page", "2")],
    )
    .and_then(|value| serde_json::from_value::<Vec<PullRequest>>(value).ok()) else {
        return ReviewObservation::Unavailable;
    };
    let pull = match pulls.as_slice() {
        [] => {
            let name = format!("heads/{}", bookmark.bookmark);
            let path = encode_ref_path(&name);
            let Some(reference) = read(&format!("/repos/{repository}/git/ref/{path}"), &[])
                .and_then(|value| serde_json::from_value::<BranchRef>(value).ok())
            else {
                return ReviewObservation::Unavailable;
            };
            if reference.name != format!("refs/{name}") || reference.object.kind != "commit" {
                return ReviewObservation::UnmatchedBranchRef;
            }
            if &reference.object.sha != commit {
                return ReviewObservation::StaleHead;
            }
            return ReviewObservation::NoOpenPullRequest {
                repository: repository.clone(),
                remote: bookmark.remote.clone(),
                source: bookmark.bookmark.clone(),
                head_revision: reference.object.sha,
            };
        }
        [pull] => pull,
        _ => return ReviewObservation::AmbiguousPullRequest,
    };
    if pull.number == 0
        || pull.state != "open"
        || pull.updated_at.is_empty()
        || !pull.head.belongs_to(repository)
        || !pull.base.belongs_to(repository)
        || pull.head.name != bookmark.bookmark
        || pull.base.name.is_empty()
        || pull.base.sha.is_empty()
    {
        return ReviewObservation::UnmatchedPullRequest;
    }
    if &pull.head.sha != commit {
        return ReviewObservation::StaleHead;
    }
    let checks = read(
        &format!("/repos/{repository}/commits/{commit}/check-runs"),
        &[("filter", "latest"), ("per_page", "100")],
    )
    .and_then(|value| serde_json::from_value::<CheckRuns>(value).ok())
    .filter(|runs| {
        runs.total_count == runs.check_runs.len()
            && runs
                .check_runs
                .iter()
                .all(|run| &run.head_revision == commit)
    })
    .and_then(|runs| {
        let mut checks = runs.check_runs;
        checks.sort_unstable_by_key(|run| run.id);
        checks
            .windows(2)
            .all(|pair| pair[0].id != pair[1].id)
            .then_some(checks)
    });
    ReviewObservation::Observed {
        repository: repository.clone(),
        remote: bookmark.remote.clone(),
        number: pull.number,
        source: pull.head.name.clone(),
        target: pull.base.name.clone(),
        target_revision: pull.base.sha.clone(),
        head_revision: commit.clone(),
        updated_at: pull.updated_at.clone(),
        on_candidate: commit == candidate,
        checks,
    }
}

#[cfg(test)]
#[path = "../tests/unit/review_provider.rs"]
mod tests;
