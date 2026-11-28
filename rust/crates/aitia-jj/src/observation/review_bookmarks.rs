// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Resolve remote bookmark candidates and their transport identity from JJ.

use super::workspace::{
    JjObservationError, WorkspaceCut, open_workspace, repository_error, require_current,
};
use futures::executor::block_on;
use jj_lib::{
    backend::CommitId,
    git::REMOTE_NAME_FOR_LOCAL_GIT_REPO,
    object_id::ObjectId,
    op_store::OperationId,
    ref_name::{RemoteName, RemoteRefSymbol},
    repo::Repo,
    view::View,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

/// A locally recorded remote bookmark on the candidate’s reachable history.
/// An unresolved target is represented by a null commit, never a selected side.
#[derive(Debug, PartialEq, Eq, Serialize)]
pub struct RecordedReviewBookmark {
    pub remote: String,
    pub bookmark: String,
    pub commit: Option<String>,
    #[serde(rename = "githubRepository")]
    pub github_repository: Option<String>,
    #[serde(skip)]
    pub route_identity: Option<String>,
}

fn is_github_host(url: &gix::Url) -> bool {
    url.host().is_some_and(|host| {
        host.trim_end_matches('.')
            .eq_ignore_ascii_case("github.com")
    })
}

fn github_repository(url: &gix::Url) -> Option<String> {
    use gix::url::Scheme;
    if !is_github_host(url)
        || !matches!(
            (&url.scheme, url.port),
            (Scheme::Https, None | Some(443)) | (Scheme::Ssh, None | Some(22))
        )
    {
        return None;
    }
    // A GitHub lookup needs only the repository identity. Never serialize
    // a transport URL, username, password, query or fragment.
    let path = std::str::from_utf8(url.path.as_ref()).ok()?;
    let path = path.strip_prefix('/').unwrap_or(path);
    let (owner, name) = path.split_once('/')?;
    let name = name.strip_suffix(".git").unwrap_or(name);
    if owner.is_empty()
        || !owner
            .bytes()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == b'-')
        || matches!(name, "" | "." | "..")
        || !name
            .bytes()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, b'.' | b'_' | b'-'))
    {
        return None;
    }
    Some(format!("{owner}/{name}").to_ascii_lowercase())
}

/// Provider identity of the selected JJ transport route.
#[derive(Debug, PartialEq, Eq)]
pub enum PushRemote {
    GitHub(String),
    UnresolvedGitHub,
    Other,
}

pub(crate) fn configured_push_remote<'repo>(
    repo: &'repo gix::Repository,
    name: &RemoteName,
) -> Result<(gix::Remote<'repo>, PushRemote), JjObservationError> {
    use gix::remote::Direction::{Fetch, Push};
    let remote = jj_lib::git::try_find_active_remote(repo, name)
        .map_err(repository_error)?
        .ok_or_else(|| repository_error("remote has no active configuration"))?;
    let urls = || remote.urls(Fetch).chain(remote.urls(Push));
    let destination = if urls().any(is_github_host) {
        match remote.url(Fetch).and_then(github_repository) {
            Some(repository)
                if remote.url(Push).is_some()
                    && urls().all(|url| github_repository(url).as_ref() == Some(&repository)) =>
            {
                PushRemote::GitHub(repository)
            }
            _ => PushRemote::UnresolvedGitHub,
        }
    } else {
        PushRemote::Other
    };
    Ok((remote, destination))
}

// Bind the ordered effective fetch and push URLs without exposing them.
pub(crate) fn route_identity(remote: &gix::Remote<'_>) -> String {
    use gix::remote::Direction::{Fetch, Push};
    let mut digest = Sha256::new();
    for (marker, direction) in [(0, Fetch), (1, Push)] {
        digest.update([marker]);
        for url in remote.urls(direction) {
            let bytes = url.to_bstring();
            digest.update((bytes.len() as u64).to_be_bytes());
            digest.update(bytes.as_slice());
        }
        digest.update(0_u64.to_be_bytes());
    }
    format!("sha256:{:x}", digest.finalize())
}

pub(crate) fn resolved_remote_commit<'a>(
    view: &'a View,
    symbol: RemoteRefSymbol<'_>,
) -> Option<&'a CommitId> {
    if symbol.remote == REMOTE_NAME_FOR_LOCAL_GIT_REPO {
        return None;
    }
    view.get_remote_bookmark(symbol).target.as_normal()
}

/// Discover recorded bookmark candidates without contacting a provider.
///
/// Keep the closest heads by ancestry per remote, retaining equal-head aliases,
/// incomparable heads and conflicts. A local Git ref is not a remote
/// observation, and an empty result does not establish PR absence.
///
/// # Errors
/// Refuses a stale or ambiguous JJ operation.
pub fn recorded_review_bookmarks(
    cut: &WorkspaceCut,
) -> Result<Vec<RecordedReviewBookmark>, JjObservationError> {
    let workspace = open_workspace(cut.workspace_root())?;
    block_on(async {
        require_current(&workspace, cut).await?;
        let operation_id = OperationId::try_from_hex(cut.operation_id())
            .ok_or_else(|| repository_error("invalid recorded operation"))?;
        let operation = workspace
            .repo_loader()
            .load_operation(&operation_id)
            .await
            .map_err(repository_error)?;
        let repo = workspace
            .load_at(&operation)
            .await
            .map_err(repository_error)?;
        let view = repo.view();
        let index = repo.index();
        let git = jj_lib::git::get_git_repo(repo.store()).map_err(repository_error)?;
        let candidate = CommitId::try_from_hex(cut.commit_id())
            .ok_or_else(|| repository_error("invalid recorded commit"))?;

        let mut reachable = BTreeMap::new();
        let mut normal_heads = BTreeMap::<&RemoteName, BTreeSet<&CommitId>>::new();
        let mut relevant = Vec::new();
        for (symbol, reference) in view.all_remote_bookmarks() {
            if symbol.remote == REMOTE_NAME_FOR_LOCAL_GIT_REPO {
                continue;
            }
            for head in reference.target.present_adds() {
                let reaches_candidate = match reachable.get(head) {
                    Some(&reaches_candidate) => reaches_candidate,
                    None => {
                        let reaches_candidate = index
                            .is_ancestor(head, &candidate)
                            .await
                            .map_err(repository_error)?;
                        reachable.insert(head.clone(), reaches_candidate);
                        reaches_candidate
                    }
                };
                if reaches_candidate {
                    if let Some(head) = reference.target.as_normal() {
                        normal_heads.entry(symbol.remote).or_default().insert(head);
                    }
                    relevant.push((symbol, reference.target.as_normal()));
                    break;
                }
            }
        }

        let mut frontier = BTreeMap::<&RemoteName, BTreeSet<CommitId>>::new();
        for (remote, heads) in normal_heads {
            let maximal = index
                .heads(&mut heads.into_iter())
                .await
                .map_err(repository_error)?;
            frontier.insert(remote, maximal.into_iter().collect());
        }
        let mut repositories = BTreeMap::new();
        let observed = relevant
            .into_iter()
            .filter(|(symbol, head)| head.is_none_or(|head| frontier[symbol.remote].contains(head)))
            .map(|(symbol, head)| {
                let (repository, route) =
                    repositories.entry(symbol.remote).or_insert_with(
                        || match configured_push_remote(&git, symbol.remote) {
                            Ok((remote, identity)) => {
                                let repository = match identity {
                                    PushRemote::GitHub(repository) => Some(repository),
                                    _ => None,
                                };
                                (repository, Some(route_identity(&remote)))
                            }
                            Err(_) => (None, None),
                        },
                    );
                RecordedReviewBookmark {
                    remote: symbol.remote.as_str().to_owned(),
                    bookmark: symbol.name.as_str().to_owned(),
                    commit: head.map(ObjectId::hex),
                    github_repository: repository.clone(),
                    route_identity: route.clone(),
                }
            })
            .collect();
        require_current(&workspace, cut).await?;
        Ok(observed)
    })
}
