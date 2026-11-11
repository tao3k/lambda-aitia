// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use serde_json::{Value, json};
use std::io::Write;
use std::process::{Command, Stdio};

#[cfg(target_os = "macos")]
#[path = "linked_program/compiled_program.rs"]
mod compiled_program;

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
    std::fs::write(
        &manifest,
        r#"{"schemaVersion":1,"services":{"sysml":{"enable":true,"parse":false}}}"#,
    )
    .unwrap();
    assert!(init().status.success());
    let existing: Value = serde_json::from_slice(&std::fs::read(&manifest).unwrap()).unwrap();
    assert_eq!(existing["services"]["sysml"]["parse"], false);

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
        assert_eq!(effective["manifest"]["services"], json!({}));
        assert_eq!(effective["inputs"]["sysml"], json!([]));
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

#[test]
#[ignore = "requires JJ, pytest and a local loopback Provider"]
fn check_runs_the_recorded_assurance_profile() {
    let jj = std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN");
    let python = std::env::var_os("AITIA_PYTEST_PYTHON").expect("set AITIA_PYTEST_PYTHON");
    let workspace = tempfile::tempdir().unwrap();
    let root = workspace.path();
    let run_jj = |args: &[&str]| {
        let result = Command::new(&jj)
            .current_dir(root)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
    };
    run_jj(&["git", "init", "--colocate"]);
    std::fs::create_dir_all(root.join(".agents/aita")).unwrap();
    std::fs::write(
        root.join(".agents/aita/project.json"),
        br#"{"schemaVersion":1,"services":{"assurance":{"enable":true,"project":"cli-assurance","profile":"adr-0008"},"commit":{"project":"cli-assurance","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-083","checks":[{"requirement":"SWE-083","method":"jj.recorded-change"},{"requirement":"SWE-084","method":"jj.configuration-audit"}]}}}"#,
    ).unwrap();
    let directory = "dev/qualification/job-executor";
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join(directory);
    let recorded = root.join(directory);
    std::fs::create_dir_all(&recorded).unwrap();
    for file in ["worker.py", "test_unique_effect.py"] {
        std::fs::copy(fixture.join(file), recorded.join(file)).unwrap();
    }
    run_jj(&[
        "describe",
        "-m",
        "record the Assurance profile and its cases",
    ]);
    let original = aitia_jj::observe_workspace(root).unwrap();
    std::fs::write(
        recorded.join("test_unique_effect.py"),
        "raise RuntimeError('unrecorded edit')",
    )
    .unwrap();

    std::fs::write(recorded.join("unrecorded.txt"), "parallel edit").unwrap();
    let context = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .arg("commit-context")
        .current_dir(&recorded)
        .output()
        .unwrap();
    assert!(context.status.success(), "{:?}", context);
    let context: Value = serde_json::from_slice(&context.stdout).unwrap();
    assert_eq!(context["policy"]["project"], "cli-assurance");
    assert_eq!(context["policy"]["primary"], "SWE-083");
    assert_eq!(context["policy"]["edition"], "D");
    assert_eq!(
        context["policy"]["checks"][0]["method"],
        "jj.recorded-change"
    );
    assert_eq!(context["cut"]["commit"], original.commit_id());
    assert_eq!(context["cut"]["tree"], original.tree_id());
    assert_eq!(
        context["cut"]["parents"],
        serde_json::json!(original.parent_ids())
    );
    assert_eq!(context["changes"].as_array().unwrap().len(), 3);
    assert_eq!(context["review"]["open"], serde_json::json!([]));
    assert_eq!(context["review"]["supported"].as_array().unwrap().len(), 2);
    let clauses = context["review"]["clauses"].as_array().unwrap();
    let org: String = clauses
        .iter()
        .map(|clause| {
            format!(
                "* Review\n:PROPERTIES:\n:{}: {}\n:END:\n",
                clause["property"].as_str().unwrap(),
                clause["value"].as_str().unwrap()
            )
        })
        .collect();
    let run_draft = |command, org: &str| {
        let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .arg(command)
            .current_dir(&recorded)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(
            child.stdin.take().unwrap(),
            &serde_json::json!({
                "title": "Record the candidate configuration",
                "body": "Bind the recorded paths and audited Git object.",
                "org": org,
                "context": context["review"]["context"],
            }),
        )
        .unwrap();
        child.wait_with_output().unwrap()
    };
    let description = run_draft("commit-description", &org);
    assert!(description.status.success(), "{:?}", description);
    let description: Value = serde_json::from_slice(&description.stdout).unwrap();
    assert_eq!(description["review"]["draftValid"], true);
    let rendered = description["review"]["description"].as_str().unwrap();
    assert!(rendered.starts_with("Record the candidate configuration\n"));
    assert!(!rendered.contains(original.tree_id()));
    assert!(!rendered.contains("AITIA-Draft:"));
    assert!(!rendered.contains("sha256:"));

    let refused = run_draft("commit-prepare", "");
    assert!(!refused.status.success(), "{:?}", refused);
    let refused: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(refused.get("attempt").is_none());
    let prepared = run_draft("commit-prepare", &org);
    assert!(prepared.status.success(), "{:?}", prepared);
    let prepared: Value = serde_json::from_slice(&prepared.stdout).unwrap();
    assert_eq!(prepared["review"]["description"], rendered);
    let attempt: aitia_jj::DescriptionRecovery =
        serde_json::from_value(prepared["attempt"].clone()).unwrap();
    let reopened = aitia_jj::reopen_description(&original, rendered, &attempt).unwrap();
    assert_eq!(reopened.proposed_receipt().expected, original);
    assert_eq!(aitia_jj::observe_workspace(root).unwrap(), original);

    let check = || {
        Command::new(env!("CARGO_BIN_EXE_aitia"))
            .arg("check")
            .current_dir(&recorded)
            .env("AITIA_PYTEST_PYTHON", &python)
            .output()
            .unwrap()
    };
    let passing = check();
    assert!(
        passing.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&passing.stderr),
        String::from_utf8_lossy(&passing.stdout)
    );
    let receipt: Value = serde_json::from_slice(&passing.stdout).unwrap();
    assert_eq!(receipt["cut"]["commit_id"], original.commit_id());
    let cases = receipt["checks"]["assurance"]["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 2);
    for case in cases {
        assert_eq!(case["matched"], true);
        let assessment = &case["assessment"];
        assert_eq!(assessment["revision"], original.commit_id());
        assert_eq!(assessment["releaseAuthorized"], false);
        assert_eq!(assessment["deployment"]["assessment"]["complete"], false);
        let receipt: Value =
            serde_json::from_str(assessment["observationReceipt"].as_str().unwrap()).unwrap();
        assert_eq!(receipt["PROJECT"], "cli-assurance");
        assert_eq!(receipt["COMMIT"], original.commit_id());
    }
    assert_eq!(cases[0]["assessment"]["supported"][0][1], "fixed-check");
    assert_eq!(cases[1]["assessment"]["contradicted"][0][1], "buggy-check");

    let original_test = std::fs::read_to_string(fixture.join("test_unique_effect.py")).unwrap();
    let unrelated = original_test
        .replace("assert committed == 1,", "assert mode != \"buggy\",")
        .replace(
            "ADR0008 duplicate effects: expected 1, observed",
            "unrelated failure, count",
        );
    assert_ne!(unrelated, original_test);
    std::fs::write(recorded.join("test_unique_effect.py"), unrelated).unwrap();
    run_jj(&["describe", "-m", "record an unrelated buggy-case assertion"]);
    let unrelated = check();
    assert!(!unrelated.status.success());
    let report: Value = serde_json::from_slice(&unrelated.stdout).unwrap();
    let cases = report["checks"]["assurance"]["cases"].as_array().unwrap();
    assert_eq!(cases[0]["matched"], true);
    assert_eq!(cases[1]["matched"], false);
    assert!(cases[1]["assessment"].is_null());

    std::fs::write(
        recorded.join("test_unique_effect.py"),
        "raise RuntimeError('recorded collection error')",
    )
    .unwrap();
    run_jj(&["describe", "-m", "record the broken test source"]);
    let failure = check();
    assert!(!failure.status.success());
    let receipt: Value = serde_json::from_slice(&failure.stdout).unwrap();
    assert_ne!(receipt["cut"]["commit_id"], original.commit_id());
    for case in receipt["checks"]["assurance"]["cases"].as_array().unwrap() {
        assert_eq!(case["matched"], false);
        assert!(case["assessment"].is_null());
    }
}

#[test]
fn signed_commit_uses_the_prepared_operation_and_durable_approval() {
    use ring::signature::{Ed25519KeyPair, KeyPair};

    fn hex(bytes: &[u8]) -> String {
        use std::fmt::Write as _;
        bytes.iter().fold(String::new(), |mut output, byte| {
            write!(output, "{byte:02x}").unwrap();
            output
        })
    }

    let jj = std::env::var_os("AITIA_JJ_BIN").unwrap_or_else(|| "jj".into());
    let fixture = tempfile::tempdir().unwrap();
    let workspace = fixture.path().join("workspace");
    let policy = fixture.path().join("authority.json");
    std::fs::create_dir(&workspace).unwrap();
    let workspace = workspace.canonicalize().unwrap();
    let run_jj = |args: &[&str]| {
        let result = Command::new(&jj)
            .current_dir(&workspace)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(result.status.success(), "{result:?}");
    };
    run_jj(&["git", "init", "--colocate"]);
    std::fs::create_dir_all(workspace.join(".agents/aita")).unwrap();
    std::fs::write(
        workspace.join(".agents/aita/project.json"),
        br#"{"schemaVersion":1,"services":{"commit":{"project":"signed-fixture","governance":"signed","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-084","checks":[{"requirement":"SWE-084","method":"jj.configuration-audit"}]}}}"#,
    ).unwrap();
    run_jj(&["describe", "-m", "record project profile"]);
    let original = aitia_jj::observe_workspace(&workspace).unwrap();

    let signer = Ed25519KeyPair::from_seed_unchecked(&[42; 32]).unwrap();
    std::fs::write(
        &policy,
        json!({
            "project": "signed-fixture", "workspace": workspace,
            "publicKey": hex(signer.public_key().as_ref()),
        })
        .to_string(),
    )
    .unwrap();

    let run = |operation: &str, input: Value| {
        let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .arg(operation)
            .current_dir(&workspace)
            .env("AITIA_GOVERNANCE_POLICY", &policy)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(child.stdin.take().unwrap(), &input).unwrap();
        child.wait_with_output().unwrap()
    };
    let json_output = |result: std::process::Output| {
        assert!(result.status.success(), "{result:?}");
        serde_json::from_slice::<Value>(&result.stdout).unwrap()
    };

    let context = json_output(run("commit-context", Value::Null));
    let org: String = context["review"]["clauses"]
        .as_array()
        .unwrap()
        .iter()
        .map(|clause| {
            format!(
                "* Evidence\n:PROPERTIES:\n:{}: {}\n:END:\n",
                clause["property"].as_str().unwrap(),
                clause["value"].as_str().unwrap()
            )
        })
        .collect();
    let draft = json!({"title":"Audit the recorded configuration",
        "body":"Bind the Git object to its recorded cut.", "org":org,
        "context":context["review"]["context"]});
    let prepared = json_output(run("commit-prepare", draft.clone()));
    assert_eq!(
        prepared["governanceRevision"],
        context["governanceRevision"]
    );
    let denied = run(
        "commit-apply",
        json!({"draft":draft, "attempt":prepared["attempt"]}),
    );
    assert!(!denied.status.success(), "{denied:?}");
    assert!(String::from_utf8_lossy(&denied.stderr).contains("requires a signed commit approval"));
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), original);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let message = json!({"kind":"aitia.commit.approve.v1", "project":"signed-fixture",
        "revision":prepared["governanceRevision"], "approval":"first",
        "intent":prepared["intent"], "notBefore":now, "expiresAt":now + 300})
    .to_string();
    let forged = run(
        "commit-decision",
        json!({"message":message, "signature":"00".repeat(64)}),
    );
    assert!(!forged.status.success(), "{forged:?}");
    assert!(String::from_utf8_lossy(&forged.stderr).contains("signature rejected"));
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), original);
    json_output(run(
        "commit-decision",
        json!({"message":message,
        "signature":hex(signer.sign(message.as_bytes()).as_ref())}),
    ));
    let written = json_output(run(
        "commit-apply",
        json!({
            "draft":draft, "attempt":prepared["attempt"], "approval":"first"
        }),
    ));
    let published = aitia_jj::observe_workspace(&workspace).unwrap();
    assert_eq!(
        written["receipt"]["resulting_commit"],
        published.commit_id()
    );
    assert_eq!(
        prepared["attempt"]["resulting_operation"],
        published.operation_id()
    );
    assert_eq!(published.parent_ids(), original.parent_ids());
    assert_eq!(published.tree_id(), original.tree_id());
    let recovered = json_output(run("commit-recover", json!({"approval":"first"})));
    assert_eq!(recovered["outcome"], "applied");
    assert_eq!(recovered["attempt"], prepared["attempt"]);
}

#[test]
fn reviewed_commit_push_reads_back_prose_without_scheme_compilers() {
    let jj = std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN");
    let fixture = tempfile::tempdir().unwrap();
    let workspace = fixture.path().join("workspace");
    let remote = fixture.path().join("remote.git");
    std::fs::create_dir(&workspace).unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--bare"])
            .arg(&remote)
            .status()
            .unwrap()
            .success()
    );
    let run_jj = |args: &[&str]| {
        let output = Command::new(&jj)
            .current_dir(&workspace)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(output.status.success(), "{output:?}");
    };
    run_jj(&["git", "init", "--colocate"]);
    std::fs::create_dir_all(workspace.join(".agents/aita")).unwrap();
    std::fs::write(workspace.join(".agents/aita/project.json"), br#"{"schemaVersion":1,"services":{"commit":{"project":"reviewed-push-fixture","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-084","checks":[{"requirement":"SWE-083","method":"jj.recorded-change"},{"requirement":"SWE-084","method":"jj.configuration-audit"}]}}}"#).unwrap();
    run_jj(&["describe", "-m", "Base"]);
    run_jj(&["bookmark", "create", "reviewed", "-r", "@"]);
    run_jj(&["git", "remote", "add", "origin", remote.to_str().unwrap()]);
    run_jj(&[
        "git",
        "push",
        "--remote",
        "origin",
        "--bookmark",
        "reviewed",
    ]);
    let base = aitia_jj::observe_workspace(&workspace).unwrap();
    run_jj(&["new", "-m", "Candidate"]);
    std::fs::write(workspace.join("change.txt"), "reviewed change\n").unwrap();
    run_jj(&["describe", "-m", "Candidate"]);
    #[cfg(target_os = "macos")]
    compiled_program::assert_controls(fixture.path());
    let run = |args: &[&str], input: &Value| {
        #[cfg(target_os = "macos")]
        let mut command = compiled_program::command(args);
        #[cfg(not(target_os = "macos"))]
        let mut command = {
            let mut command = Command::new(env!("CARGO_BIN_EXE_aitia"));
            command.args(args);
            command
        };
        let mut child = command
            .current_dir(&workspace)
            .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
            .env_remove("GERBIL_HOME")
            .env_remove("GERBIL_PATH")
            .env_remove("GERBIL_LOADPATH")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(child.stdin.take().unwrap(), input).unwrap();
        child.wait_with_output().unwrap()
    };
    let json_output = |output: std::process::Output| {
        assert!(output.status.success(), "{output:?}");
        serde_json::from_slice::<Value>(&output.stdout).unwrap()
    };
    let context = json_output(run(&["commit-context"], &Value::Null));
    let org: String = context["review"]["clauses"]
        .as_array()
        .unwrap()
        .iter()
        .map(|clause| {
            format!(
                "* Evidence\n:PROPERTIES:\n:{}: {}\n:END:\n",
                clause["property"].as_str().unwrap(),
                clause["value"].as_str().unwrap()
            )
        })
        .collect();
    assert!(!org.contains("sha256:"));
    let draft = json!({"title":"fix(review): publish the reviewed candidate",
        "body":"Evidence\nThe recorded change and configuration were checked.\n\nOpen\nBroader model coverage remains open.",
        "org":org,"context":context["review"]["context"]});
    let prepared = json_output(run(&["commit-prepare"], &draft));
    let approved = json!({"draft":draft,"attempt":prepared["attempt"]});
    let written = json_output(run(&["commit-apply"], &approved));
    let description = written["review"]["description"].as_str().unwrap();
    assert!(description.contains("\nEvidence\n"));
    assert!(description.contains("\nOpen\n"));
    assert!(!description.contains("sha256:"));
    assert!(!description.contains("JJ-Cut:"));
    let head = || {
        let output = Command::new("git")
            .arg("--git-dir")
            .arg(&remote)
            .args(["rev-parse", "refs/heads/reviewed"])
            .output()
            .unwrap();
        assert!(output.status.success());
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    };
    let args = [
        "jj",
        "git",
        "push",
        "--remote",
        "origin",
        "--bookmark",
        "reviewed",
    ];
    let mut forged = approved.clone();
    forged["attempt"]["description"] = json!(format!("{description}forged"));
    let refused = run(&args, &forged);
    assert!(!refused.status.success(), "{refused:?}");
    assert_eq!(head(), base.commit_id());
    let pushed = json_output(run(&args, &approved));
    assert_eq!(pushed["commit"], written["receipt"]["resulting_commit"]);
    assert_eq!(head(), pushed["commit"].as_str().unwrap());
    let object = Command::new("git")
        .arg("--git-dir")
        .arg(&remote)
        .args(["cat-file", "commit", &head()])
        .output()
        .unwrap();
    assert!(object.status.success());
    let object = String::from_utf8(object.stdout).unwrap();
    assert_eq!(object.split_once("\n\n").unwrap().1, description);
    let replayed = run(&args, &approved);
    assert!(!replayed.status.success(), "{replayed:?}");
    assert_eq!(head(), pushed["commit"].as_str().unwrap());
}
