// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::jj;
use aitia_jj::observe_workspace;
use std::path::{Path, PathBuf};
use std::process::Command;

#[test]
fn reviewed_push_preserves_history_and_rejects_stale_cuts_and_remote_leases() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let remote = directory.path().join("remote.git");
    std::fs::create_dir(&workspace).unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--bare"])
            .arg(&remote)
            .status()
            .unwrap()
            .success()
    );
    jj(&executable, &workspace, &["git", "init", "--colocate"]);
    std::fs::write(workspace.join("base.txt"), "base\n").unwrap();
    jj(&executable, &workspace, &["describe", "-m", "Base"]);
    jj(
        &executable,
        &workspace,
        &["bookmark", "create", "reviewed", "-r", "@"],
    );
    jj(
        &executable,
        &workspace,
        &["bookmark", "create", "local-only", "-r", "@"],
    );
    jj(
        &executable,
        &workspace,
        &["bookmark", "create", "second-review", "-r", "@"],
    );
    jj(
        &executable,
        &workspace,
        &["git", "remote", "add", "origin", remote.to_str().unwrap()],
    );
    jj(
        &executable,
        &workspace,
        &[
            "git",
            "push",
            "--remote",
            "origin",
            "--bookmark",
            "reviewed",
            "--bookmark",
            "second-review",
        ],
    );
    let base = observe_workspace(&workspace).unwrap();
    jj(&executable, &workspace, &["new", "-m", "Candidate"]);
    std::fs::write(workspace.join("candidate.txt"), "reviewed\n").unwrap();
    jj(&executable, &workspace, &["describe", "-m", "Candidate"]);
    let original = observe_workspace(&workspace).unwrap();
    let bookmarks = aitia_jj::recorded_review_bookmarks(&original).unwrap();
    assert_eq!(
        bookmarks,
        ["reviewed", "second-review"].map(|bookmark| aitia_jj::RecordedReviewBookmark {
            remote: "origin".into(),
            bookmark: bookmark.into(),
            commit: Some(base.commit_id().into()),
            github_repository: None,
            route_identity: bookmarks[0].route_identity.clone(),
        })
    );
    let config = |args: &[&str]| {
        let result = Command::new("git")
            .current_dir(&workspace)
            .arg("config")
            .args(args)
            .output()
            .unwrap();
        assert!(result.status.success(), "{result:?}");
    };
    config(&[
        "remote.origin.url",
        "https://fixture-user:fixture-secret@github.com/Team/Project.git",
    ]);
    config(&["remote.origin.pushurl", "git@github.com:team/project.git"]);
    let candidates = aitia_jj::recorded_review_bookmarks(&original).unwrap();
    assert_eq!(candidates.len(), 2);
    assert!(
        candidates
            .iter()
            .all(|row| { row.github_repository.as_deref() == Some("team/project") })
    );
    let serialized = serde_json::to_string(&candidates).unwrap();
    assert!(!serialized.contains("fixture-user") && !serialized.contains("fixture-secret"));
    let assert_changed_route = || {
        let mut changed = aitia_jj::recorded_review_bookmarks(&original).unwrap();
        assert_eq!(changed.len(), bookmarks.len());
        for (row, original) in changed.iter_mut().zip(&bookmarks) {
            assert!(row.route_identity.is_some());
            assert_ne!(row.route_identity, original.route_identity);
            row.route_identity.clone_from(&original.route_identity);
        }
        assert_eq!(changed, bookmarks);
    };
    config(&[
        "--add",
        "remote.origin.pushurl",
        "git@github.com:another/project.git",
    ]);
    assert_changed_route();
    config(&["--unset-all", "remote.origin.pushurl"]);
    for url in [
        "git@github.com:another/project.git",
        "https://github.com.example.invalid/team/project.git",
        "https://github.com:444/team/project.git",
        "https://github.com/team/project.git?alternate",
    ] {
        config(&["remote.origin.pushurl", url]);
        assert_changed_route();
    }
    config(&["--unset", "remote.origin.pushurl"]);
    config(&["remote.origin.url", remote.to_str().unwrap()]);
    assert_eq!(observe_workspace(&workspace).unwrap(), original);
    let bookmarks = aitia_jj::recorded_review_bookmarks(&original).unwrap();
    let description = "Publish reviewed change\n\nEvidence\nThe candidate was checked.\n\nOpen\nLocal fixture only.\n";
    let applied = aitia_jj::prepare_description(&original, description)
        .unwrap()
        .publish(|_| true)
        .unwrap();
    let current = observe_workspace(&workspace).unwrap();
    assert!(matches!(
        aitia_jj::recorded_review_bookmarks(&original),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    assert_eq!(
        aitia_jj::recorded_review_bookmarks(&current).unwrap(),
        bookmarks
    );
    assert!(
        aitia_jj::push_reviewed_description(
            &current,
            description,
            "git",
            "reviewed",
            |_, _, _| panic!("local Git tracking ref is not a remote lease")
        )
        .is_err()
    );
    assert!(matches!(
        aitia_jj::push_reviewed_description(
            &original,
            description,
            "origin",
            "reviewed",
            |_, _, _| panic!("stale cut")
        ),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    assert!(
        aitia_jj::push_reviewed_description(
            &current,
            "forged",
            "origin",
            "reviewed",
            |_, _, _| panic!("unreviewed description")
        )
        .is_err()
    );
    assert!(
        aitia_jj::push_reviewed_description(
            &current,
            description,
            "origin",
            "absent",
            |_, _, _| panic!("absent bookmark")
        )
        .is_err()
    );
    assert!(
        aitia_jj::push_reviewed_description(
            &current,
            description,
            "origin",
            "reviewed",
            |_, _, _| { false }
        )
        .is_err()
    );
    let remote_head_at = |repository: &Path| {
        let result = Command::new("git")
            .arg("--git-dir")
            .arg(repository)
            .args(["rev-parse", "refs/heads/reviewed"])
            .output()
            .unwrap();
        assert!(result.status.success());
        String::from_utf8(result.stdout).unwrap().trim().to_owned()
    };
    let remote_head = || remote_head_at(&remote);
    assert_eq!(remote_head(), base.commit_id());
    // Git configuration can change without producing a JJ operation.
    config(&["remote.origin.pushurl", "git@github.com:team/project.git"]);
    let mut inspected = false;
    let refused = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |destination, head, _| {
            inspected = true;
            assert_eq!(destination, aitia_jj::PushRemote::UnresolvedGitHub);
            assert_eq!(head, base.commit_id());
            false
        },
    );
    assert!(inspected && refused.is_err());
    assert_eq!(observe_workspace(&workspace).unwrap(), current);
    assert_eq!(remote_head(), base.commit_id());
    config(&["--unset", "remote.origin.pushurl"]);

    // Both remotes have the same branch lease and classify as local routes.
    let alternate = directory.path().join("alternate.git");
    assert!(
        Command::new("git")
            .args(["clone", "--bare", "--quiet"])
            .arg(&remote)
            .arg(&alternate)
            .status()
            .unwrap()
            .success()
    );
    for url in [&remote, &alternate] {
        config(&["--add", "remote.origin.pushurl", url.to_str().unwrap()]);
    }
    let refused = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |_, _, _| panic!("multiple push URLs reached admission"),
    );
    assert!(matches!(
        refused,
        Err(aitia_jj::JjObservationError::Repository(message))
            if message == "reviewed push requires exactly one destination URL"
    ));
    assert_eq!(observe_workspace(&workspace).unwrap(), current);
    assert_eq!(remote_head(), base.commit_id());
    assert_eq!(remote_head_at(&alternate), base.commit_id());
    config(&["--unset-all", "remote.origin.pushurl"]);

    let tag = Command::new("git")
        .current_dir(&workspace)
        .args([
            "-c",
            "user.name=AITIA Test",
            "-c",
            "user.email=test@example.invalid",
        ])
        .args([
            "tag",
            "-am",
            "Outside the reviewed bookmark",
            "extra",
            current.commit_id(),
        ])
        .output()
        .unwrap();
    assert!(tag.status.success(), "{tag:?}");
    let assert_no_tag = || {
        assert!(
            !Command::new("git")
                .arg("--git-dir")
                .arg(&remote)
                .args(["show-ref", "--verify", "--quiet", "refs/tags/extra"])
                .status()
                .unwrap()
                .success()
        );
    };
    for key in ["push.followTags", "remote.origin.mirror"] {
        config(&[key, "true"]);
        let refused = aitia_jj::push_reviewed_description(
            &current,
            description,
            "origin",
            "reviewed",
            |_, _, _| panic!("expanded push reached admission"),
        );
        assert!(matches!(
            refused,
            Err(aitia_jj::JjObservationError::Repository(message))
                if message == format!("reviewed push cannot use {key}")
        ));
        config(&["--unset", key]);
    }
    let refused = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |_, _, _| {
            config(&["push.followTags", "true"]);
            true
        },
    );
    assert!(matches!(
        refused,
        Err(aitia_jj::JjObservationError::Repository(message))
            if message == "reviewed push cannot use push.followTags"
    ));
    config(&["--unset", "push.followTags"]);
    config(&["push.recurseSubmodules", "on-demand"]);
    let refused = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |_, _, _| panic!("recursive push reached admission"),
    );
    assert!(matches!(
        refused,
        Err(aitia_jj::JjObservationError::Repository(message))
            if message == "reviewed push requires push.recurseSubmodules to be no or check"
    ));
    config(&["--unset", "push.recurseSubmodules"]);
    assert_eq!(observe_workspace(&workspace).unwrap(), current);
    assert_eq!(remote_head(), base.commit_id());
    assert_no_tag();

    let refused = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |destination, head, _| {
            assert_eq!(destination, aitia_jj::PushRemote::Other);
            assert_eq!(head, base.commit_id());
            config(&["remote.origin.pushurl", alternate.to_str().unwrap()]);
            true
        },
    );
    assert!(
        matches!(
            &refused,
            Err(aitia_jj::JjObservationError::Repository(message))
                if message == "Git push destination changed during admission"
        ),
        "expected a destination-change refusal, got {refused:?}"
    );
    assert_eq!(observe_workspace(&workspace).unwrap(), current);
    assert_eq!(remote_head(), base.commit_id());
    assert_eq!(remote_head_at(&alternate), base.commit_id());
    config(&["--unset", "remote.origin.pushurl"]);
    if let Some(fault) = std::env::var_os("AITIA_TEST_PUSH_FAULT") {
        for mode in ["omitted", "lost"] {
            std::fs::write(&fault, mode).unwrap();
            let result = aitia_jj::push_reviewed_description(
                &current,
                description,
                "origin",
                "reviewed",
                |_, _, _| true,
            );
            std::fs::remove_file(&fault).unwrap();
            assert!(
                matches!(&result, Err(aitia_jj::JjObservationError::Repository(message))
                    if message == "JJ did not acknowledge the selected bookmark; push outcome is unresolved"),
                "{mode}: expected an unresolved push, got {result:?}"
            );
            let expected = if mode == "omitted" {
                base.commit_id()
            } else {
                current.commit_id()
            };
            assert_eq!(remote_head(), expected);
            assert_eq!(observe_workspace(&workspace).unwrap(), current);
            assert!(
                aitia_jj::recover_reviewed_push(
                    &workspace,
                    &applied.recovery_record(),
                    "origin",
                    "reviewed",
                )
                .unwrap()
                .is_none()
            );
            assert_eq!(remote_head(), expected);
        }
        // Reset the fixture after the lost acknowledgement to exercise success.
        assert!(
            Command::new("git")
                .arg("--git-dir")
                .arg(&remote)
                .args(["update-ref", "refs/heads/reviewed", base.commit_id()])
                .status()
                .unwrap()
                .success()
        );
    }
    let fault = std::env::var_os("AITIA_TEST_PUSH_FAULT");
    if let Some(path) = &fault {
        std::fs::write(path, "no-url-reset").unwrap();
        let refused = aitia_jj::push_reviewed_description(
            &current,
            description,
            "origin",
            "reviewed",
            |_, _, _| panic!("Git without URL reset reached admission"),
        );
        assert!(matches!(
            refused,
            Err(aitia_jj::JjObservationError::Repository(message))
                if message == "reviewed push requires Git push URL reset support"
        ));
        config(&["push.recurseSubmodules", "check"]);
        std::fs::write(
            path,
            format!("late-config\n{}\n{}", remote.display(), alternate.display()),
        )
        .unwrap();
    }
    let receipt = aitia_jj::push_reviewed_description(
        &current,
        description,
        "origin",
        "reviewed",
        |_, _, _| true,
    )
    .unwrap();
    if let Some(path) = &fault {
        std::fs::remove_file(path).unwrap();
        config(&["--unset", "push.followTags"]);
        config(&["--unset", "remote.origin.mirror"]);
        config(&["--unset", "push.recurseSubmodules"]);
        config(&["--unset-all", "remote.origin.pushurl"]);
        config(&["--remove-section", &format!("url.{}", alternate.display())]);
    }
    assert_eq!(receipt.commit, current.commit_id());
    assert_eq!(remote_head(), current.commit_id());
    let nested = workspace.join("src");
    std::fs::create_dir(&nested).unwrap();
    let attempt = applied.recovery_record();
    let recovered = aitia_jj::recover_reviewed_push(&nested, &attempt, "origin", "reviewed")
        .unwrap()
        .unwrap();
    assert_eq!(recovered.operation, receipt.operation);
    let independent = nested.join("independent");
    std::fs::create_dir(&independent).unwrap();
    assert!(
        Command::new("git")
            .arg("init")
            .arg(&independent)
            .output()
            .unwrap()
            .status
            .success()
    );
    let refused = aitia_jj::recover_reviewed_push(&independent, &attempt, "origin", "reviewed");
    assert!(matches!(
        refused,
        Err(aitia_jj::JjObservationError::Output(message))
            if message == "nearest Git project has no matching JJ workspace"
    ));
    assert_eq!(remote_head_at(&alternate), base.commit_id());
    assert_no_tag();
    let object = Command::new("git")
        .arg("--git-dir")
        .arg(&remote)
        .args(["cat-file", "commit", current.commit_id()])
        .output()
        .unwrap();
    assert!(object.status.success());
    let object = String::from_utf8(object.stdout).unwrap();
    assert_eq!(object.split_once("\n\n").unwrap().1, description);
    assert!(
        Command::new("git")
            .arg("--git-dir")
            .arg(&remote)
            .args(["update-ref", "refs/heads/reviewed", base.commit_id()])
            .status()
            .unwrap()
            .success()
    );
    let after = observe_workspace(&workspace).unwrap();
    // A remote change made without a JJ fetch does not rewrite the recorded
    // discovery facts. The real push lease still detects it.
    let observed = aitia_jj::recorded_review_bookmarks(&after).unwrap();
    assert_eq!(
        observed
            .iter()
            .find(|row| row.bookmark == "reviewed")
            .and_then(|row| row.commit.as_deref()),
        Some(current.commit_id())
    );
    assert_eq!(remote_head(), base.commit_id());
    let refused = aitia_jj::push_reviewed_description(
        &after,
        description,
        "origin",
        "reviewed",
        |_, _, _| true,
    );
    assert!(
        refused.is_err(),
        "a stale remote lease must refuse publication"
    );
    assert_eq!(remote_head(), base.commit_id());
    jj(
        &executable,
        &workspace,
        &["new", "root()", "-m", "Unrelated"],
    );
    let unrelated = observe_workspace(&workspace).unwrap();
    aitia_jj::prepare_description(&unrelated, "Unrelated reviewed\n")
        .unwrap()
        .publish(|_| true)
        .unwrap();
    let unrelated = observe_workspace(&workspace).unwrap();
    let refused = aitia_jj::push_reviewed_description(
        &unrelated,
        "Unrelated reviewed\n",
        "origin",
        "reviewed",
        |_, _, _| panic!("non-fast-forward"),
    );
    assert!(
        refused
            .unwrap_err()
            .to_string()
            .contains("preserve bookmark history")
    );
    assert_eq!(remote_head(), base.commit_id());
}

#[test]
fn reviewed_push_preserves_divergent_unpublished_local_work() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().join("workspace");
    let remote = directory.path().join("remote.git");
    std::fs::create_dir(&workspace).unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--bare"])
            .arg(&remote)
            .status()
            .unwrap()
            .success()
    );
    jj(&executable, &workspace, &["git", "init", "--colocate"]);
    std::fs::write(workspace.join("base.txt"), "base\n").unwrap();
    jj(&executable, &workspace, &["describe", "-m", "Base"]);
    jj(
        &executable,
        &workspace,
        &["bookmark", "create", "reviewed", "-r", "@"],
    );
    jj(
        &executable,
        &workspace,
        &["git", "remote", "add", "origin", remote.to_str().unwrap()],
    );
    jj(
        &executable,
        &workspace,
        &[
            "git",
            "push",
            "--remote",
            "origin",
            "--bookmark",
            "reviewed",
        ],
    );
    let base = observe_workspace(&workspace).unwrap();
    jj(
        &executable,
        &workspace,
        &["new", "-m", "Independent local work"],
    );
    std::fs::write(workspace.join("private.txt"), "preserve unpublished work\n").unwrap();
    jj(
        &executable,
        &workspace,
        &["bookmark", "set", "reviewed", "-r", "@"],
    );
    let private = observe_workspace(&workspace).unwrap();
    jj(
        &executable,
        &workspace,
        &["new", base.commit_id(), "-m", "Candidate"],
    );
    std::fs::write(workspace.join("candidate.txt"), "reviewed change\n").unwrap();
    jj(&executable, &workspace, &["status"]);
    let candidate = observe_workspace(&workspace).unwrap();
    let description = "fix(review): preserve parallel local work\n";
    aitia_jj::prepare_description(&candidate, description)
        .unwrap()
        .publish(|_| true)
        .unwrap();
    let candidate = observe_workspace(&workspace).unwrap();
    let receipt = aitia_jj::push_reviewed_description(
        &candidate,
        description,
        "origin",
        "reviewed",
        |_, _, _| true,
    )
    .unwrap();
    assert_eq!(receipt.commit, candidate.commit_id());
    let local = Command::new(&executable)
        .current_dir(&workspace)
        .args([
            "--ignore-working-copy",
            "log",
            "--no-graph",
            "-r",
            "reviewed",
            "-T",
            "commit_id",
        ])
        .output()
        .unwrap();
    assert!(local.status.success(), "{local:?}");
    assert_eq!(
        String::from_utf8(local.stdout).unwrap().trim(),
        private.commit_id()
    );
    let native_local = Command::new("git")
        .current_dir(&workspace)
        .args(["rev-parse", "refs/heads/reviewed"])
        .output()
        .unwrap();
    assert!(native_local.status.success());
    assert_eq!(
        String::from_utf8(native_local.stdout).unwrap().trim(),
        private.commit_id()
    );
    let published = Command::new("git")
        .arg("--git-dir")
        .arg(&remote)
        .args(["rev-parse", "refs/heads/reviewed"])
        .output()
        .unwrap();
    assert!(published.status.success());
    assert_eq!(
        String::from_utf8(published.stdout).unwrap().trim(),
        candidate.commit_id()
    );
}

#[cfg(unix)]
#[test]
fn missing_push_acknowledgement_stays_unresolved() {
    use std::os::unix::fs::PermissionsExt;

    let directory = tempfile::tempdir().unwrap();
    let git = directory.path().join("git");
    std::fs::write(
        &git,
        r#"#!/bin/sh
git_dir=
next_is_git_dir=
for argument in "$@"; do
    if [ -n "$next_is_git_dir" ]; then
        git_dir=$argument
        next_is_git_dir=
    elif [ "$argument" = --git-dir ]; then
        next_is_git_dir=1
    fi
    if [ "$argument" = get-url ] && [ -f "$AITIA_TEST_PUSH_FAULT" ] &&
        [ "$(head -n 1 "$AITIA_TEST_PUSH_FAULT")" = no-url-reset ]; then
        printf 'aitia-url-reset-old:\n\naitia-url-reset-new:\n'
        exit 0
    fi
    if [ "$argument" = push ] && [ -f "$AITIA_TEST_PUSH_FAULT" ]; then
        mode=$(head -n 1 "$AITIA_TEST_PUSH_FAULT")
        if [ "$mode" = late-config ]; then
            test -n "$git_dir" || exit 1
            reviewed=$(sed -n '2p' "$AITIA_TEST_PUSH_FAULT")
            alternate=$(sed -n '3p' "$AITIA_TEST_PUSH_FAULT")
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config --add remote.origin.pushurl "$alternate" || exit $?
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config --add remote.origin.pushurl "$reviewed" || exit $?
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config "url.$alternate.insteadOf" "$reviewed" || exit $?
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config push.followTags true || exit $?
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config remote.origin.mirror true || exit $?
            PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config push.recurseSubmodules on-demand || exit $?
            effective=$(PATH="$AITIA_TEST_REAL_PATH" git --git-dir "$git_dir" config --get push.recurseSubmodules) || exit $?
            test "$effective" = check || exit 1
            break
        fi
        if [ "$mode" = lost ]; then
            PATH="$AITIA_TEST_REAL_PATH" git "$@" >/dev/null || exit $?
        fi
        printf 'To local test remote\nDone\n'
        exit 0
    fi
done
PATH="$AITIA_TEST_REAL_PATH" exec git "$@"
"#,
    )
    .unwrap();
    std::fs::set_permissions(&git, std::fs::Permissions::from_mode(0o755)).unwrap();
    let real_path = std::env::var_os("PATH").unwrap();
    let path = std::env::join_paths(
        std::iter::once(directory.path().to_owned()).chain(std::env::split_paths(&real_path)),
    )
    .unwrap();
    let result = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "push::reviewed_push_preserves_history_and_rejects_stale_cuts_and_remote_leases",
        ])
        .env("PATH", path)
        .env("AITIA_TEST_REAL_PATH", real_path)
        .env("AITIA_TEST_PUSH_FAULT", directory.path().join("push-fault"))
        .output()
        .unwrap();
    assert!(
        result.status.success() && String::from_utf8_lossy(&result.stdout).contains("1 passed"),
        "{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}
