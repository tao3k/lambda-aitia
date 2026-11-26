// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Multi-repository GitOps end-to-end qualification helper for `sysml_model`.

use serde_json::{Value, json};
use std::ffi::OsStr;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

fn run_jj_in(jj: &OsStr, dir: &Path, args: &[&str]) {
    let out = Command::new(jj)
        .current_dir(dir)
        .args([
            "--config",
            "user.name='AITIA Test'",
            "--config",
            "user.email='test@example.invalid'",
        ])
        .args(args)
        .output()
        .expect("run jj");
    assert!(
        out.status.success(),
        "jj {:?} in {} failed: {}",
        args,
        dir.display(),
        String::from_utf8_lossy(&out.stderr)
    );
}

fn preview_reviewed_draft(
    dir: &Path,
    identity: &str,
    reference: &str,
    scope: &str,
    summary: &str,
) -> Result<Value, Box<dyn std::error::Error>> {
    let commit_out = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .current_dir(dir)
        .args(["jj", "commit"])
        .output()?;
    assert!(
        commit_out.status.success(),
        "aitia jj commit failed in {}: {}",
        dir.display(),
        String::from_utf8_lossy(&commit_out.stderr)
    );
    let commit_json: Value = serde_json::from_slice(&commit_out.stdout)?;
    let mut draft = json!({
        "context": commit_json["review"]["context"],
        "proposal": {
            "identity": identity,
            "reference": reference,
            "type": "feat",
            "scope": scope,
            "summary": summary,
            "rationale": "Exercise multi-repo cascading Wave 0 -> Wave 1 fenced execution.",
            "language": "en",
            "languageSource": "README.org"
        },
        "narration": {
            "change": summary,
            "evidence": [
                {"obligation": "sdlc.change-record", "text": "JJ recorded the workspace cut."},
                {"obligation": "sdlc.config-audit", "text": "JJ audited project configuration."}
            ],
            "open": []
        },
        "org": format!(
            "* {identity} feat({scope}): {summary}\n:PROPERTIES:\n:AITIA_SUPPORT: sdlc.config-audit\n:END:\n** Change\n:PROPERTIES:\n:AITIA_SUPPORT: sdlc.change-record\n:END:\n"
        )
    });
    let mut prev_child = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .current_dir(dir)
        .args(["jj", "commit", "preview"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    prev_child
        .stdin
        .take()
        .unwrap()
        .write_all(&serde_json::to_vec(&draft)?)?;
    let prev_out = prev_child.wait_with_output()?;
    assert!(
        prev_out.status.success(),
        "preview failed in {}: {}",
        dir.display(),
        String::from_utf8_lossy(&prev_out.stderr)
    );
    let prev_json: Value = serde_json::from_slice(&prev_out.stdout)?;
    assert_eq!(prev_json["review"]["draftValid"], true);
    draft["context"] = prev_json["review"]["context"].clone();
    Ok(draft)
}

fn init_downstream_repo(
    jj: &OsStr,
    down_root: &Path,
    down_remote: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let bare = Command::new("git")
        .args(["init", "--bare", down_remote.to_str().unwrap()])
        .output()?;
    assert!(bare.status.success(), "git init --bare downstream failed");
    run_jj_in(jj, down_root, &["git", "init", "--colocate"]);
    std::fs::create_dir_all(down_root.join(".agents/aita"))?;
    std::fs::create_dir_all(down_root.join("app"))?;
    std::fs::write(
        down_root.join(".agents/aita/project.json"),
        serde_json::to_vec(&json!({
            "schemaVersion": 1,
            "programs": {
                "jj": {
                    "enable": true,
                    "settings": {
                        "project": "downstream-app",
                        "profile": "lambda-aitia/sdlc",
                        "primary": "sdlc.config-audit",
                        "checks": [
                            {"requirement": "sdlc.change-record", "method": "jj.recorded-change"},
                            {"requirement": "sdlc.config-audit", "method": "jj.configuration-audit"}
                        ],
                        "naming": {
                            "projectKey": "APP",
                            "primaryLanguage": "en",
                            "languageSources": ["README.org"],
                            "types": ["feat"],
                            "scopes": [{"name": "app", "paths": ["app", ".agents/aita", "README.org", "work.org"]}],
                            "references": [{"identity": "RFC-2", "source": "work.org", "element": "work2"}]
                        }
                    }
                }
            }
        }))?,
    )?;
    std::fs::write(down_root.join("README.org"), "* App\nEnglish readme.\n")?;
    std::fs::write(
        down_root.join("work.org"),
        "* App RFC\n:PROPERTIES:\n:ID: work2\n:ENGINEERING_ID: RFC-2\n:END:\n",
    )?;
    run_jj_in(jj, down_root, &["describe", "-m", "base downstream cut"]);
    run_jj_in(
        jj,
        down_root,
        &["bookmark", "create", "reviewed", "-r", "@"],
    );
    run_jj_in(
        jj,
        down_root,
        &[
            "git",
            "remote",
            "add",
            "origin",
            down_remote.to_str().unwrap(),
        ],
    );
    run_jj_in(
        jj,
        down_root,
        &[
            "git",
            "push",
            "--remote",
            "origin",
            "--bookmark",
            "reviewed",
        ],
    );
    run_jj_in(jj, down_root, &["new", "-m", "downstream candidate"]);
    std::fs::write(down_root.join("app/lib.rs"), "pub fn run() {}\n")?;
    run_jj_in(jj, down_root, &["describe", "-m", "downstream candidate"]);
    Ok(())
}

/// Exercise two real JJ workspaces (`upstream-core` -> `downstream-app`) end-to-end:
/// 1. Detect cross-repo bitemporal pin drift via `aitia flow run --case aitia/case/multi-repo-gitops`.
/// 2. Execute full cascading Wave 0 -> Wave 1 `prepare -> apply -> push-reviewed` via
///    `aitia flow submit-decision --case aitia/case/multi-repo-gitops --execute-fenced`,
///    verifying `repoEvidenceLineages` and real bare Git remote heads for BOTH repositories.
pub(crate) fn verify_two_repo_pin_drift(
    jj: &OsStr,
    upstream_root: &Path,
    upstream_remote: &Path,
    upstream_applied_commit: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let downstream_dir = tempfile::tempdir()?;
    let down_remote_dir = tempfile::tempdir()?;
    let down_root = downstream_dir.path();
    init_downstream_repo(jj, down_root, down_remote_dir.path())?;

    // Part A: Read-only multi-repo run detects stale downstream pin against real upstream commit.
    let drift_manifest = json!({
        "repos": [
            {
                "repoId": "upstream-core",
                "directory": upstream_root.to_str().unwrap(),
                "dependsOn": [],
                "approvalLive": true
            },
            {
                "repoId": "downstream-app",
                "directory": down_root.to_str().unwrap(),
                "dependsOn": ["upstream-core"],
                "pinnedUpstreamCommits": {
                    "upstream-core": "0000000000000000000000000000000000000000"
                },
                "approvalLive": true
            }
        ]
    });
    let mut drift_child = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .current_dir(upstream_root)
        .args([
            "flow",
            "run",
            "--case",
            "aitia/case/multi-repo-gitops",
            "--proposal-stdin",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    drift_child
        .stdin
        .take()
        .unwrap()
        .write_all(&serde_json::to_vec(&drift_manifest)?)?;
    let drift_out = drift_child.wait_with_output()?;
    assert!(
        drift_out.status.success(),
        "multi-repo drift flow failed: {}",
        String::from_utf8_lossy(&drift_out.stderr)
    );
    let drift_json: Value = serde_json::from_slice(&drift_out.stdout)?;
    assert_eq!(drift_json["caseId"], "aitia/case/multi-repo-gitops");
    assert_eq!(drift_json["state"], "need-agent-synthesis");
    assert_eq!(drift_json["escalationReason"], "cross-repo-pin-drift");
    assert_eq!(
        drift_json["waves"],
        json!([["upstream-core"], ["downstream-app"]])
    );
    assert_eq!(drift_json["pinDrifts"].as_array().unwrap().len(), 1);
    assert_eq!(
        drift_json["pinDrifts"][0]["actualCommit"],
        upstream_applied_commit
    );
    assert_eq!(
        drift_json["repairTasks"][0]["recomputeScope"],
        "cross-repo-pin-drift"
    );
    assert_eq!(drift_json["actionAuthorized"], false);

    // Part B: Full cascading Wave 0 -> Wave 1 fenced commit + push across BOTH real JJ workspaces!
    run_jj_in(
        jj,
        upstream_root,
        &["new", "-m", "wave0 upstream candidate"],
    );
    std::fs::write(upstream_root.join("src/wave0.rs"), "pub fn wave0() {}\n")?;
    run_jj_in(
        jj,
        upstream_root,
        &["describe", "-m", "wave0 upstream candidate"],
    );

    let upstream_draft = preview_reviewed_draft(
        upstream_root,
        "CORE-RFC-1",
        "RFC-1",
        "core",
        "Add wave0 upstream export",
    )?;
    let downstream_draft = preview_reviewed_draft(
        down_root,
        "APP-RFC-2",
        "RFC-2",
        "app",
        "Add wave1 downstream consumer",
    )?;
    let cascade_manifest = json!({
        "repos": [
            {
                "repoId": "upstream-core",
                "directory": upstream_root.to_str().unwrap(),
                "dependsOn": [],
                "approvalLive": true,
                "draft": upstream_draft,
                "pushTarget": {"remote": "origin", "bookmark": "reviewed"}
            },
            {
                "repoId": "downstream-app",
                "directory": down_root.to_str().unwrap(),
                "dependsOn": ["upstream-core"],
                "approvalLive": true,
                "draft": downstream_draft,
                "pushTarget": {"remote": "origin", "bookmark": "reviewed"}
            }
        ]
    });
    let mut exec_child = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .current_dir(upstream_root)
        .args([
            "flow",
            "submit-decision",
            "--case",
            "aitia/case/multi-repo-gitops",
            "--execute-fenced",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    exec_child
        .stdin
        .take()
        .unwrap()
        .write_all(&serde_json::to_vec(&cascade_manifest)?)?;
    let exec_out = exec_child.wait_with_output()?;
    assert!(
        exec_out.status.success(),
        "multi-repo cascading fenced flow failed: {}",
        String::from_utf8_lossy(&exec_out.stderr)
    );
    let exec_json: Value = serde_json::from_slice(&exec_out.stdout)?;
    assert_eq!(exec_json["caseId"], "aitia/case/multi-repo-gitops");
    assert_eq!(exec_json["state"], "quiescent");
    assert_eq!(exec_json["actionAuthorized"], false);
    assert_eq!(
        exec_json["waves"],
        json!([["upstream-core"], ["downstream-app"]])
    );
    let lineages = &exec_json["repoEvidenceLineages"];
    assert_eq!(lineages["upstream-core"]["missingReports"], json!([]));
    assert_eq!(lineages["downstream-app"]["missingReports"], json!([]));
    let up_commit = lineages["upstream-core"]["revision"]
        .as_str()
        .expect("upstream verified revision");
    let down_commit = lineages["downstream-app"]["revision"]
        .as_str()
        .expect("downstream verified revision");

    let up_remote_head = Command::new("git")
        .current_dir(upstream_remote)
        .args(["rev-parse", "refs/heads/reviewed"])
        .output()?;
    assert!(up_remote_head.status.success());
    assert_eq!(
        String::from_utf8_lossy(&up_remote_head.stdout).trim(),
        up_commit,
        "upstream bare Git remote must hold Wave 0 applied commit"
    );

    let down_remote_head = Command::new("git")
        .current_dir(down_remote_dir.path())
        .args(["rev-parse", "refs/heads/reviewed"])
        .output()?;
    assert!(down_remote_head.status.success());
    assert_eq!(
        String::from_utf8_lossy(&down_remote_head.stdout).trim(),
        down_commit,
        "downstream bare Git remote must hold Wave 1 applied commit"
    );
    Ok(())
}
