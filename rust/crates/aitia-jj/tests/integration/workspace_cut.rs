// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use aitia_jj::observe_workspace;
use std::path::{Path, PathBuf};
use std::process::Command;

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
fn a_nested_git_project_reads_its_recorded_manifest() {
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

    assert!(aitia_jj::observe_project_manifest(&nested).is_err());
    std::fs::write(&manifest, r#"{"scenario":"aitia"}"#).unwrap();
    let model = nested.join("model witness.qnt");
    std::fs::write(&model, "recorded model").unwrap();
    jj(
        &executable,
        &project,
        &["describe", "-m", "record project configuration"],
    );
    let (cut, source) = aitia_jj::observe_project_manifest(&nested).unwrap();
    assert_eq!(
        cut.workspace_root().canonicalize().unwrap(),
        project.canonicalize().unwrap()
    );
    assert_eq!(source, r#"{"scenario":"aitia"}"#);
    std::fs::write(&manifest, r#"{"scenario":"dirty"}"#).unwrap();
    assert_eq!(
        aitia_jj::observe_project_manifest(&nested).unwrap(),
        (cut, source)
    );
    let model_cut = observe_workspace(&project).unwrap();
    std::fs::write(&model, "dirty model").unwrap();
    assert_eq!(
        aitia_jj::read_recorded_file(&model_cut, "src/model witness.qnt").unwrap(),
        "recorded model"
    );
    assert!(aitia_jj::read_recorded_file(&model_cut, "../outside.qnt").is_err());
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
    let error = aitia_jj::observe_project_manifest(&nested).unwrap_err();
    assert!(error.to_string().contains("regular file"), "{error}");
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
    jj(&executable, &workspace, &["new", "-m", "Candidate"]);
    std::fs::write(workspace.join("candidate.txt"), "reviewed\n").unwrap();
    jj(&executable, &workspace, &["describe", "-m", "Candidate"]);
    let original = observe_workspace(&workspace).unwrap();
    let description = "Publish reviewed change\n\nEvidence\nThe candidate was checked.\n\nOpen\nLocal fixture only.\n";
    aitia_jj::prepare_description(&original, description)
        .unwrap()
        .publish(|_| true)
        .unwrap();
    let current = observe_workspace(&workspace).unwrap();
    assert!(matches!(
        aitia_jj::push_reviewed_description(
            &original,
            description,
            "origin",
            "reviewed",
            || panic!("stale cut")
        ),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
    assert!(
        aitia_jj::push_reviewed_description(&current, "forged", "origin", "reviewed", || panic!(
            "unreviewed description"
        ))
        .is_err()
    );
    assert!(
        aitia_jj::push_reviewed_description(&current, description, "origin", "absent", || panic!(
            "absent bookmark"
        ))
        .is_err()
    );
    assert!(
        aitia_jj::push_reviewed_description(&current, description, "origin", "reviewed", || false)
            .is_err()
    );
    let remote_head = || {
        let result = Command::new("git")
            .arg("--git-dir")
            .arg(&remote)
            .args(["rev-parse", "refs/heads/reviewed"])
            .output()
            .unwrap();
        assert!(result.status.success());
        String::from_utf8(result.stdout).unwrap().trim().to_owned()
    };
    assert_eq!(remote_head(), base.commit_id());
    let receipt =
        aitia_jj::push_reviewed_description(&current, description, "origin", "reviewed", || true)
            .unwrap();
    assert_eq!(receipt.commit, current.commit_id());
    assert_eq!(remote_head(), current.commit_id());
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
    let refused =
        aitia_jj::push_reviewed_description(&after, description, "origin", "reviewed", || true);
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
        || panic!("non-fast-forward"),
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
    let receipt =
        aitia_jj::push_reviewed_description(&candidate, description, "origin", "reviewed", || true)
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
