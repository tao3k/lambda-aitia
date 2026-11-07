// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use serde_json::{Value, json};
use std::io::Write;
use std::process::{Command, Stdio};

fn run_request(operation: &str, request: &[u8]) -> std::process::Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .arg(operation)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(request).unwrap();
    child.wait_with_output().unwrap()
}

fn check_command_line() {
    eprintln!("AITIA-LINKED-TEST: CLI init and argument handling");
    let binary = env!("CARGO_BIN_EXE_aitia");
    let help = Command::new(binary).arg("--help").output().unwrap();
    assert!(help.status.success());
    let help_text = String::from_utf8_lossy(&help.stdout);
    assert!(help_text.contains("gitops-evaluate"));
    assert!(help_text.contains("jj-observe"));

    let directory = tempfile::tempdir().unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--quiet"])
            .current_dir(directory.path())
            .status()
            .unwrap()
            .success()
    );
    let other = tempfile::tempdir().unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--quiet"])
            .current_dir(other.path())
            .status()
            .unwrap()
            .success()
    );
    let init = || {
        Command::new(binary)
            .arg("init")
            .current_dir(directory.path())
            .env("GIT_DIR", other.path().join(".git"))
            .env("GIT_WORK_TREE", other.path())
            .output()
            .unwrap()
    };
    assert!(init().status.success());
    assert!(!other.path().join(".agents").exists());
    let manifest = directory.path().join(".agents/aita/project.json");
    let initial: Value = serde_json::from_slice(&std::fs::read(&manifest).unwrap()).unwrap();
    assert_eq!(initial, json!({"schemaVersion": 1}));
    std::fs::write(&manifest, r#"{"schemaVersion":1,"scenario":"custom"}"#).unwrap();
    assert!(init().status.success());
    let existing: Value = serde_json::from_slice(&std::fs::read(&manifest).unwrap()).unwrap();
    assert_eq!(existing["scenario"], "custom");

    if let Some(jj) = std::env::var_os("AITIA_JJ_BIN") {
        eprintln!("AITIA-LINKED-TEST: CLI recorded manifest");
        let record = |description| {
            assert!(
                Command::new(&jj)
                    .current_dir(directory.path())
                    .args([
                        "--config",
                        "user.name='AITIA Test'",
                        "--config",
                        "user.email='test@example.invalid'",
                        "describe",
                        "-m",
                        description
                    ])
                    .status()
                    .unwrap()
                    .success()
            );
        };
        assert!(
            Command::new(&jj)
                .current_dir(directory.path())
                .args(["git", "init", "--colocate"])
                .status()
                .unwrap()
                .success()
        );
        std::fs::write(&manifest, r#"{"schemaVersion":1}"#).unwrap();
        record("minimal AITIA configuration");
        let read = || {
            Command::new(binary)
                .current_dir(directory.path())
                .arg("project-manifest")
                .arg(&jj)
                .arg(".")
                .output()
                .unwrap()
        };
        let output = read();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let effective: Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(effective["manifest"]["scenario"], "aitia");
        assert_eq!(
            effective["manifest"]["models"],
            json!({"quint": [], "sysml": []})
        );
        assert!(effective["cut"]["commit_id"].is_string());

        std::fs::write(&manifest, r#"{"schemaVersion":2}"#).unwrap();
        record("invalid AITIA configuration");
        let rejected = read();
        assert!(!rejected.status.success());
        assert!(rejected.stdout.is_empty());
        assert!(String::from_utf8_lossy(&rejected.stderr).contains("envelope Contract"));
    }

    let incomplete_observation = Command::new(binary).arg("jj-observe").output().unwrap();
    assert!(!incomplete_observation.status.success());
    assert!(incomplete_observation.stdout.is_empty());

    let invalid = Command::new(binary).arg("unknown").output().unwrap();
    assert!(!invalid.status.success());
    assert!(invalid.stdout.is_empty());

    eprintln!("AITIA-LINKED-TEST: CLI Graph");
    let output = run_request("flow-graph", br#"{"lifecycle-id":"cli/42"}"#);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let graph: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(graph["schema"], "lambda-aitia.sdlc-flow-graph");
    assert_eq!(graph["lifecycleId"], "cli/42");
    assert_eq!(graph["releaseAuthorized"], false);
    assert_eq!(graph["runtimeExecuted"], false);

    eprintln!("AITIA-LINKED-TEST: CLI ORG");
    let output = run_request(
        "org-contract-evaluate",
        org_request().to_string().as_bytes(),
    );
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let verdict: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(verdict["matchedCount"], 1);
    assert_eq!(verdict["passed"], true);
}

fn org_request() -> Value {
    json!({
        "rows": [
            {"id": 0, "parentId": -1, "kind": "org-data", "fieldName": "", "fieldValue": ""},
            {"id": 1, "parentId": 0, "kind": "headline", "fieldName": "title", "fieldValue": "Evidence"}
        ],
        "scopeId": 0,
        "queryKind": "headline",
        "fieldName": "title",
        "fieldValue": "Evidence",
        "expectation": "exactly",
        "expectedCount": 1
    })
}

#[test]
fn linked_scheme_program_publishes_the_sdlc_graph_and_gitops_decision() {
    eprintln!("AITIA-LINKED-TEST: session start");
    let program = aitia_runtime::AitiaSession::start().expect("start linked AITIA owner");
    eprintln!("AITIA-LINKED-TEST: session Graph");
    assert!(program.flow_graph("{}".into()).is_err());
    let payload = std::thread::scope(|scope| {
        scope
            .spawn(|| program.flow_graph(r#"{"lifecycle-id":"release/42"}"#.into()))
            .join()
            .unwrap()
    })
    .unwrap();
    let graph: Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(graph["schema"], "lambda-aitia.sdlc-flow-graph");
    assert_eq!(graph["nodes"].as_array().unwrap().len(), 8);
    assert_eq!(graph["edges"].as_array().unwrap().len(), 7);
    assert_eq!(
        graph["edges"][6],
        json!({
            "from": "release/42/authorize", "to": "release/42/effect", "relation": "sdlc-next"
        })
    );
    eprintln!("AITIA-LINKED-TEST: session GitOps");
    let mut request = json!({
        "event": "pull-request",
        "repository": "tao3k/agentic-ai-lab",
        "revision": "0123456789abcdef",
        "source-ref": "feature/aitia",
        "target-ref": "develop",
        "pull-request": 42,
        "checks": [
            {"name": "commit-policy", "conclusion": "success"},
            {"name": "build", "conclusion": "success"},
            {"name": "unit-test", "conclusion": "success"},
            {
                "name": "nasa/sdlc/npr-7150.2",
                "conclusion": "success",
                "standardEdition": "D",
                "sourceLockDigest": "sha256:68113744771506840ed6d7abb4873f87fc6b490d405b9637d446ba4b2ba39108"
            }
        ]
    });
    let accepted: Value =
        serde_json::from_str(&program.gitops_evaluate(request.to_string()).unwrap()).unwrap();
    assert_eq!(accepted["accepted"], true);
    assert_eq!(accepted["profile"], "dev");
    assert_eq!(accepted["releaseAuthorized"], false);
    assert_eq!(accepted["runtimeExecuted"], false);

    request["checks"][0]["conclusion"] = json!("pending");
    let pending: Value =
        serde_json::from_str(&program.gitops_evaluate(request.to_string()).unwrap()).unwrap();
    assert_eq!(pending["accepted"], false);
    assert_eq!(pending["failedChecks"], json!(["commit-policy"]));
    assert_eq!(
        pending["checkBlockers"],
        json!([{"name": "commit-policy", "conclusion": "pending"}])
    );
    request["checks"][0]["conclusion"] = json!("success");

    request["checks"][0]["revision"] = json!("obsolete");
    let stale_revision: Value =
        serde_json::from_str(&program.gitops_evaluate(request.to_string()).unwrap()).unwrap();
    assert_eq!(stale_revision["accepted"], false);
    assert_eq!(stale_revision["staleChecks"], json!(["commit-policy"]));
    request["checks"][0]["revision"] = request["revision"].clone();

    request["checks"][3]["sourceLockDigest"] = json!("sha256:stale");
    let rejected: Value =
        serde_json::from_str(&program.gitops_evaluate(request.to_string()).unwrap()).unwrap();
    assert_eq!(rejected["accepted"], false);
    assert_eq!(rejected["staleChecks"], json!(["nasa/sdlc/npr-7150.2"]));
    eprintln!("AITIA-LINKED-TEST: session ORG");
    let mut request = org_request();
    request["expectedCount"] = json!(2);
    let verdict: Value =
        serde_json::from_str(&program.org_contract_evaluate(request.to_string()).unwrap()).unwrap();
    assert_eq!(verdict["matchedCount"], 1);
    assert_eq!(verdict["passed"], false);
    assert!(program.org_contract_evaluate("{}".into()).is_err());
    eprintln!("AITIA-LINKED-TEST: session close");
    program.close().expect("clean linked AITIA shutdown");
    check_command_line();
}
