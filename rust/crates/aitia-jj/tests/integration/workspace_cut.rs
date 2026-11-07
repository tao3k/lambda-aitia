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
    assert_eq!(std::fs::read_to_string(untracked).unwrap(), "new work");

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

    if let Some(path) = std::env::var_os("AITIA_JJ_REPLAY_CUTS") {
        let cuts = serde_json::json!({"before": original, "rewritten": rewritten});
        std::fs::write(path, serde_json::to_vec(&cuts).unwrap()).unwrap();
    }
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
