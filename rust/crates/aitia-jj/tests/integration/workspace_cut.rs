// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use aitia_jj::observe_workspace;
use std::path::{Path, PathBuf};
use std::process::Command;

#[path = "workspace_cut/push.rs"]
mod push;

fn jj(jj: &Path, workspace: &Path, arguments: &[&str]) {
    let output = Command::new(jj)
        .current_dir(workspace)
        .args([
            "--config",
            "user.name='AITIA Test'",
            "--config",
            "user.email='test@example.invalid'",
        ])
        .args(arguments)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn review_bookmarks_follow_ancestry_and_preserve_ambiguous_routes() {
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
    let run = |args: &[&str]| jj(&executable, &workspace, args);
    run(&["git", "init", "--colocate"]);
    run(&["describe", "-m", "Shared base"]);
    run(&["bookmark", "create", "shared"]);
    run(&["new", "-m", "Published topic"]);
    run(&["bookmark", "create", "topic", "topic-alias"]);
    let topic = observe_workspace(&workspace).unwrap();
    run(&["new", "shared", "-m", "Published sibling"]);
    run(&["bookmark", "create", "sibling"]);
    let sibling = observe_workspace(&workspace).unwrap();
    run(&["git", "remote", "add", "origin", remote.to_str().unwrap()]);
    run(&[
        "git",
        "push",
        "--remote",
        "origin",
        "--bookmark",
        "shared",
        "--bookmark",
        "topic",
        "--bookmark",
        "topic-alias",
        "--bookmark",
        "sibling",
    ]);

    run(&["new", "topic", "-m", "First unpublished change"]);
    run(&["new", "-m", "Second unpublished change"]);
    let current = observe_workspace(&workspace).unwrap();
    assert!(
        !current
            .parent_ids()
            .iter()
            .any(|id| id == topic.commit_id())
    );
    let found = aitia_jj::recorded_review_bookmarks(&current).unwrap();
    assert_eq!(
        found
            .iter()
            .map(|row| (row.bookmark.as_str(), row.commit.as_deref()))
            .collect::<Vec<_>>(),
        [
            ("topic", Some(topic.commit_id())),
            ("topic-alias", Some(topic.commit_id()))
        ]
    );

    run(&[
        "new",
        "@",
        "sibling",
        "-m",
        "Join the unpublished topic and published sibling",
    ]);
    let joined = observe_workspace(&workspace).unwrap();
    let found = aitia_jj::recorded_review_bookmarks(&joined).unwrap();
    assert_eq!(
        found
            .iter()
            .map(|row| (row.bookmark.as_str(), row.commit.as_deref()))
            .collect::<Vec<_>>(),
        [
            ("sibling", Some(sibling.commit_id())),
            ("topic", Some(topic.commit_id())),
            ("topic-alias", Some(topic.commit_id()))
        ]
    );
    assert!(matches!(
        aitia_jj::recorded_review_bookmarks(&current),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
}

#[test]
fn observation_preserves_dirty_workspace_and_distinguishes_a_rewrite() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path();
    jj(&executable, workspace, &["git", "init"]);
    let original = observe_workspace(workspace).unwrap();
    assert_eq!(original.workspace_name(), "default");
    assert_eq!(original.parent_ids().len(), 1);

    let untracked = workspace.join("untracked.txt");
    std::fs::write(&untracked, "new work").unwrap();
    assert_eq!(observe_workspace(workspace).unwrap(), original);
    assert_eq!(std::fs::read_to_string(&untracked).unwrap(), "new work");
    assert!(aitia_jj::recorded_changes(&original).unwrap().is_empty());

    jj(
        &executable,
        workspace,
        &["describe", "-m", "captured rewrite"],
    );
    let rewritten = observe_workspace(workspace).unwrap();
    assert_eq!(rewritten.change_id(), original.change_id());
    assert_ne!(rewritten.commit_id(), original.commit_id());
    assert_ne!(rewritten.tree_id(), original.tree_id());
    assert_ne!(rewritten.operation_id(), original.operation_id());
    assert_eq!(rewritten.parent_ids(), original.parent_ids());
    assert!(matches!(
        aitia_jj::recorded_changes(&original),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    std::fs::write(&untracked, "not in the recorded tree").unwrap();
    let changes = aitia_jj::recorded_changes(&rewritten).unwrap();
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].path, "untracked.txt");
    assert!(changes[0].before.is_none());
    assert!(matches!(
        changes[0].after,
        Some(aitia_jj::RecordedTreeEntry::File {
            executable: false,
            ..
        })
    ));

    if let Some(path) = std::env::var_os("AITIA_JJ_REPLAY_CUTS") {
        let cuts = serde_json::json!({"before": original, "rewritten": rewritten});
        std::fs::write(path, serde_json::to_vec(&cuts).unwrap()).unwrap();
    }
}

#[test]
fn git_discovery_keeps_bootstrap_worktree_and_bare_boundaries() {
    let directory = tempfile::tempdir().unwrap();
    let project = directory.path().join("project ");
    gix::init(&project).unwrap();
    let nested = project.join("src/nested");
    std::fs::create_dir_all(&nested).unwrap();
    assert_eq!(
        aitia_jj::git_project_root(&nested).unwrap(),
        project.canonicalize().unwrap()
    );
    // Git is fixture setup only. The production discovery never executes it.
    let commit = Command::new("git")
        .current_dir(&project)
        .args([
            "-c",
            "user.name=AITIA Test",
            "-c",
            "user.email=test@example.invalid",
            "commit",
            "--allow-empty",
            "-m",
            "Worktree discovery fixture",
        ])
        .output()
        .unwrap();
    assert!(commit.status.success(), "{commit:?}");
    let worktree = directory.path().join("worktree ");
    let created = Command::new("git")
        .current_dir(&project)
        .args(["worktree", "add", "--detach"])
        .arg(&worktree)
        .arg("HEAD")
        .output()
        .unwrap();
    assert!(created.status.success(), "{created:?}");
    assert!(worktree.join(".git").is_file());
    let inside = worktree.join("src");
    std::fs::create_dir(&inside).unwrap();
    assert_eq!(
        aitia_jj::git_project_root(&inside).unwrap(),
        worktree.canonicalize().unwrap()
    );
    let bare = directory.path().join("bare.git");
    gix::init_bare(&bare).unwrap();
    assert!(aitia_jj::git_project_root(&bare).is_err());
    let invalid = directory.path().join("invalid");
    std::fs::create_dir_all(invalid.join(".git")).unwrap();
    assert!(aitia_jj::git_project_root(&invalid).is_err());
}

#[test]
fn a_nested_git_project_reads_its_recorded_project_sources() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let outer = directory.path();
    jj(&executable, outer, &["git", "init", "--colocate"]);
    let project = outer.join("subproject ");
    std::fs::create_dir(&project).unwrap();
    jj(&executable, &project, &["git", "init", "--colocate"]);
    let config = project.join(".agents/aita");
    std::fs::create_dir_all(&config).unwrap();
    let manifest = config.join("project.json");
    let nested = project.join("src");
    std::fs::create_dir(&nested).unwrap();

    let observe = || aitia_jj::observe_project_sources(&nested, 1024);
    let (_, absent) = observe().unwrap();
    assert_eq!(absent.declaration, None);
    assert_eq!(absent.manifest, None);
    let declaration = config.join("project.ss");
    std::fs::write(&declaration, "(.o schemaVersion: 1)").unwrap();
    std::fs::write(&manifest, r#"{"scenario":"aitia"}"#).unwrap();
    let model = nested.join("model witness.qnt");
    std::fs::write(&model, "recorded model").unwrap();
    jj(
        &executable,
        &project,
        &["describe", "-m", "record project configuration"],
    );
    let (cut, sources) = observe().unwrap();
    assert_eq!(
        cut.workspace_root().canonicalize().unwrap(),
        project.canonicalize().unwrap()
    );
    assert_eq!(sources.manifest.as_deref(), Some(r#"{"scenario":"aitia"}"#));
    assert_eq!(
        sources.declaration.as_deref(),
        Some("(.o schemaVersion: 1)")
    );
    assert!(aitia_jj::observe_project_sources(&nested, 25).is_err());
    std::fs::write(&manifest, r#"{"scenario":"dirty"}"#).unwrap();
    std::fs::write(&declaration, "dirty source").unwrap();
    assert_eq!(observe().unwrap(), (cut, sources));
    let model_cut = observe_workspace(&project).unwrap();
    std::fs::write(&model, "dirty model").unwrap();
    assert_eq!(
        aitia_jj::read_recorded_file(&model_cut, "src/model witness.qnt").unwrap(),
        "recorded model"
    );
    assert!(aitia_jj::read_recorded_file(&model_cut, "../outside.qnt").is_err());
    let observed = aitia_jj::observe_recorded_sources(
        &model_cut,
        &[
            "missing.org",
            "src/model witness.qnt",
            ".agents/aita/project.ss",
        ],
        "recorded model".len(),
    )
    .unwrap();
    assert!(observed[0].1.is_err());
    assert_eq!(observed[1].1.as_deref().unwrap(), "recorded model");
    assert!(
        observed[2]
            .1
            .as_ref()
            .unwrap_err()
            .to_string()
            .contains("byte limit")
    );
    std::fs::remove_file(&manifest).unwrap();
    std::fs::create_dir(&manifest).unwrap();
    std::fs::write(manifest.join("nested.json"), "{}").unwrap();
    jj(
        &executable,
        &project,
        &["describe", "-m", "record directory instead"],
    );
    assert!(matches!(
        aitia_jj::read_recorded_file(&model_cut, "src/model witness.qnt"),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    assert!(matches!(
        aitia_jj::observe_recorded_sources(&model_cut, &["missing.org"], 64),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    let historical = aitia_jj::recorded_revision_source_entries(
        &nested,
        model_cut.commit_id(),
        &["missing.org", ".agents/aita/project.json"],
    )
    .unwrap();
    assert!(matches!(
        historical.as_slice(),
        [(
            ".agents/aita/project.json",
            aitia_jj::RecordedTreeEntry::File { .. }
        )]
    ));
    let error = observe().unwrap_err();
    assert!(error.to_string().contains("regular file"), "{error}");

    let current = observe_workspace(&nested).unwrap();
    let path = "src/model witness.qnt";
    let original = model_cut.commit_id();
    assert_eq!(
        aitia_jj::read_revision_files(&nested, original, &[path], 14).unwrap(),
        [b"recorded model".to_vec()]
    );
    assert_eq!(
        aitia_jj::read_revision_files(&nested, current.commit_id(), &[path], 14).unwrap(),
        [b"dirty model".to_vec()]
    );
    assert!(aitia_jj::read_revision_files(&nested, original, &[path, path], 27).is_err());
    assert!(aitia_jj::read_revision_files(&nested, &original[..12], &[path], 14).is_err());
    assert!(aitia_jj::read_revision_files(&nested, "@", &[path], 14).is_err());
    assert!(aitia_jj::read_revision_files(&nested, original, &["../outside"], 14).is_err());
    assert!(aitia_jj::read_revision_files(&nested, original, &["missing"], 14).is_err());
    assert_eq!(observe_workspace(&nested).unwrap(), current);

    let receipt = aitia_jj::prepare_description(&current, "Recorded project recovery")
        .unwrap()
        .publish(|_| true)
        .unwrap();
    let record = receipt.recovery_record();
    assert_eq!(
        aitia_jj::reconcile_description(&nested, &record).unwrap(),
        aitia_jj::DescriptionOutcome::Applied
    );
    let independent = nested.join("independent");
    assert!(
        std::process::Command::new("git")
            .args(["init", "-q"])
            .arg(&independent)
            .status()
            .unwrap()
            .success()
    );
    let error = aitia_jj::reconcile_description(&independent, &record).unwrap_err();
    assert!(
        error.to_string().contains("no matching JJ workspace"),
        "{error}"
    );
}

#[test]
fn description_publish_compares_the_head_before_consuming_admission() {
    if let Some(path) = std::env::var_os("AITIA_DESCRIPTION_RECOVERY_FIXTURE") {
        let (workspace, record): (PathBuf, aitia_jj::DescriptionRecovery) =
            serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!(
            aitia_jj::reconcile_description(&workspace, &record).unwrap(),
            aitia_jj::DescriptionOutcome::Applied
        );
        println!("AITIA-DESCRIPTION-RECOVERY-OK");
        return;
    }
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path();
    jj(&executable, workspace, &["git", "init", "--colocate"]);
    std::fs::write(workspace.join("recorded.txt"), "recorded input").unwrap();
    jj(&executable, workspace, &["describe", "-m", "record input"]);
    let cut = observe_workspace(workspace).unwrap();

    let denied = aitia_jj::prepare_description(&cut, "denied candidate").unwrap();
    assert_eq!(observe_workspace(workspace).unwrap(), cut);
    assert!(denied.publish(|_| false).is_err());
    assert_eq!(observe_workspace(workspace).unwrap(), cut);

    let prepared = aitia_jj::prepare_description(&cut, "approved candidate").unwrap();
    let stale = aitia_jj::prepare_description(&cut, "competing candidate").unwrap();
    let dirty_file = workspace.join("unrecorded.txt");
    std::fs::write(&dirty_file, "parallel work").unwrap();
    let proposal = prepared.proposed_receipt().clone();
    let record = proposal.recovery_record();
    drop(prepared);
    let recovery = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(
        recovery.path(),
        serde_json::to_vec(&(workspace, &record)).unwrap(),
    )
    .unwrap();
    assert_eq!(
        aitia_jj::reconcile_description(workspace, &record).unwrap(),
        aitia_jj::DescriptionOutcome::Unresolved
    );
    let (_, reviewed): (PathBuf, aitia_jj::DescriptionRecovery) =
        serde_json::from_slice(&std::fs::read(recovery.path()).unwrap()).unwrap();
    assert!(aitia_jj::reopen_description(&cut, "unreviewed description", &reviewed).is_err());
    let mut substituted: aitia_jj::DescriptionRecovery =
        serde_json::from_value(serde_json::to_value(&reviewed).unwrap()).unwrap();
    substituted.resulting_operation = stale.proposed_receipt().resulting_operation.clone();
    assert!(aitia_jj::reopen_description(&cut, "approved candidate", &substituted).is_err());
    assert_eq!(observe_workspace(workspace).unwrap(), cut);
    let reopened = aitia_jj::reopen_description(&cut, "approved candidate", &reviewed).unwrap();
    let receipt = reopened.publish(|exact| exact == &proposal).unwrap();
    assert!(matches!(
        aitia_jj::reopen_description(&cut, "approved candidate", &reviewed),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    let current = observe_workspace(workspace).unwrap();
    assert_eq!(receipt.resulting_operation, current.operation_id());
    assert_eq!(receipt.resulting_commit, current.commit_id());
    assert_eq!(current.change_id(), cut.change_id());
    assert_eq!(current.tree_id(), cut.tree_id());
    assert_eq!(current.parent_ids(), cut.parent_ids());
    let audit = aitia_jj::audit_recorded_configuration(&current).unwrap();
    assert_eq!(audit.git_commit, current.commit_id());
    assert_eq!(audit.git_tree, current.tree_id());
    assert!(audit.git_parents.is_empty());
    assert!(matches!(
        aitia_jj::audit_recorded_configuration(&cut),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));

    assert_eq!(
        std::fs::read_to_string(dirty_file).unwrap(),
        "parallel work"
    );

    assert!(matches!(
        stale.publish(|_| panic!("stale writes must not consume admission")),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    assert_eq!(observe_workspace(workspace).unwrap(), current);
    jj(
        &executable,
        workspace,
        &[
            "--ignore-working-copy",
            "bookmark",
            "create",
            "observed-later",
            "-r",
            "@",
        ],
    );
    let later = observe_workspace(workspace).unwrap();
    assert_ne!(later.operation_id(), current.operation_id());
    let recovered = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "description_publish_compares_the_head_before_consuming_admission",
            "--nocapture",
        ])
        .env("AITIA_DESCRIPTION_RECOVERY_FIXTURE", recovery.path())
        .output()
        .unwrap();
    assert!(recovered.status.success(), "{:?}", recovered);
    assert!(
        String::from_utf8_lossy(&recovered.stdout)
            .lines()
            .any(|line| line == "AITIA-DESCRIPTION-RECOVERY-OK")
    );
    let mut forged = record;
    forged.description.push('!');
    assert!(aitia_jj::reconcile_description(workspace, &forged).is_err());
    assert_eq!(observe_workspace(workspace).unwrap(), later);
}

#[test]
fn prepared_description_requires_its_recorded_review_context() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path();
    jj(&executable, workspace, &["git", "init", "--colocate"]);
    jj(&executable, workspace, &["describe", "-m", "record input"]);
    let cut = observe_workspace(workspace).unwrap();
    let description = "Reviewed prose";
    let before = "original context";
    let after = "current context";
    let unbound = aitia_jj::prepare_description(&cut, description)
        .unwrap()
        .proposed_receipt()
        .recovery_record();
    let original = aitia_jj::prepare_reviewed_description(&cut, description, before, "proposal")
        .unwrap()
        .proposed_receipt()
        .recovery_record();
    let refreshed = aitia_jj::prepare_reviewed_description(&cut, description, after, "proposal")
        .unwrap()
        .proposed_receipt()
        .recovery_record();
    assert_eq!(original.resulting_commit, refreshed.resulting_commit);
    assert_ne!(original.resulting_operation, refreshed.resulting_operation);
    for refused in [&unbound, &original] {
        assert!(matches!(
            aitia_jj::reopen_reviewed_description(&cut, description, refused, after, "proposal"),
            Err(aitia_jj::JjObservationError::Output(message))
                if message == "prepared rewrite does not match the current review context"
        ));
    }
    assert!(
        aitia_jj::reopen_reviewed_description(
            &cut,
            description,
            &refreshed,
            after,
            "changed proposal"
        )
        .is_err()
    );
    assert_eq!(observe_workspace(workspace).unwrap(), cut);
    let receipt =
        aitia_jj::reopen_reviewed_description(&cut, description, &refreshed, after, "proposal")
            .unwrap()
            .publish(|_| true)
            .unwrap();
    assert_eq!(receipt.resulting_operation, refreshed.resulting_operation);
    assert_eq!(receipt.resulting_commit, refreshed.resulting_commit);
    assert_eq!(
        aitia_jj::reconcile_description(workspace, &refreshed).unwrap(),
        aitia_jj::DescriptionOutcome::Applied
    );
    assert_eq!(
        aitia_jj::reconcile_description(workspace, &original).unwrap(),
        aitia_jj::DescriptionOutcome::Unresolved
    );
}

#[test]
fn description_prepare_refuses_a_bookmark_rewrite() {
    let executable = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path();
    jj(&executable, workspace, &["git", "init"]);
    jj(&executable, workspace, &["describe", "-m", "record input"]);
    jj(
        &executable,
        workspace,
        &["bookmark", "create", "preserved", "-r", "@"],
    );
    let cut = observe_workspace(workspace).unwrap();
    assert!(aitia_jj::prepare_description(&cut, "new description").is_err());
    assert_eq!(observe_workspace(workspace).unwrap(), cut);
}
