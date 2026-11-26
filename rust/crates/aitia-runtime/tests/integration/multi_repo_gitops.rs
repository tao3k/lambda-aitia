// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Multi-repository GitOps end-to-end qualification helper for `sysml_model`.

use serde_json::{Value, json};
use std::ffi::OsStr;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

/// Create a second real JJ workspace depending on `upstream_root` with a stale pinned SHA,
/// run `aitia flow run --case aitia/case/multi-repo-gitops --proposal-stdin`, and assert
/// cross-repo bitemporal pin-drift detection and topological wave ordering.
pub(crate) fn verify_two_repo_pin_drift(
    jj: &OsStr,
    upstream_root: &Path,
    upstream_applied_commit: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let downstream_dir = tempfile::tempdir()?;
    let down_root = downstream_dir.path();
    let run_down_jj = |args: &[&str]| {
        let out = Command::new(jj)
            .current_dir(down_root)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()
            .expect("run downstream jj");
        assert!(out.status.success(), "downstream jj {:?} failed", args);
    };
    run_down_jj(&["git", "init", "--colocate"]);
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
    std::fs::write(down_root.join("app/lib.rs"), "pub fn run() {}\n")?;
    run_down_jj(&["describe", "-m", "downstream candidate"]);

    let multi_manifest = json!({
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
    let mut multi_child = Command::new(env!("CARGO_BIN_EXE_aitia"))
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
    multi_child
        .stdin
        .take()
        .unwrap()
        .write_all(&serde_json::to_vec(&multi_manifest)?)?;
    let multi_out = multi_child.wait_with_output()?;
    assert!(
        multi_out.status.success(),
        "multi-repo flow failed: {}",
        String::from_utf8_lossy(&multi_out.stderr)
    );
    let multi_json: Value = serde_json::from_slice(&multi_out.stdout)?;
    assert_eq!(multi_json["caseId"], "aitia/case/multi-repo-gitops");
    assert_eq!(multi_json["state"], "need-agent-synthesis");
    assert_eq!(multi_json["escalationReason"], "cross-repo-pin-drift");
    assert_eq!(
        multi_json["waves"],
        json!([["upstream-core"], ["downstream-app"]])
    );
    assert_eq!(multi_json["pinDrifts"].as_array().unwrap().len(), 1);
    assert_eq!(
        multi_json["pinDrifts"][0]["actualCommit"],
        upstream_applied_commit
    );
    assert_eq!(
        multi_json["repairTasks"][0]["recomputeScope"],
        "cross-repo-pin-drift"
    );
    assert_eq!(multi_json["actionAuthorized"], false);
    Ok(())
}
