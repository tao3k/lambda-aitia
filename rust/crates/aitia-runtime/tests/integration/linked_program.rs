// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use serde_json::{Value, json};
use std::io::Write;
use std::process::{Command, Stdio};

#[cfg(target_os = "macos")]
#[path = "linked_program/compiled_program.rs"]
mod compiled_program;

#[path = "linked_program/commit.rs"]
mod commit;

#[cfg(feature = "sysml")]
mod sysml_model;

#[test]
fn review_context_tracks_the_linked_program_instead_of_manifest_paths() {
    use sha2::{Digest, Sha256};

    let archive = std::path::Path::new(env!("OUT_DIR")).join("libaitia_program.a");
    let actual = format!(
        "sha256:{:x}",
        Sha256::digest(std::fs::read(archive).unwrap())
    );
    assert_eq!(actual, env!("AITIA_PROGRAM_CONTEXT"));
    let manifest = format!(
        "sha256:{:x}",
        Sha256::digest(include_bytes!(env!("AITIA_PROGRAM_MANIFEST")))
    );
    assert_ne!(actual, manifest, "manifest paths are not program contents");
}

#[test]
#[ignore = "requires the project declaration qualification input in the AOT program"]
fn compiled_project_declaration_requires_its_recorded_source() {
    let declaration = include_str!("../../../../../dev/qualification/project-declaration.ss");
    let fixture = tempfile::tempdir().unwrap();
    let root = fixture.path();
    #[cfg(target_os = "macos")]
    compiled_program::assert_controls(root);
    let jj = std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN");
    let record = |args: &[&str]| {
        let output = Command::new(&jj)
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
        assert!(output.status.success(), "{output:?}");
    };
    let run = |args: &[&str], input: Option<&Value>| {
        #[cfg(target_os = "macos")]
        let mut command = compiled_program::command(args);
        #[cfg(not(target_os = "macos"))]
        let mut command = {
            let mut command = Command::new(env!("CARGO_BIN_EXE_aitia"));
            command.args(args);
            command
        };
        let mut child = command
            .current_dir(root)
            .env("PATH", "/usr/bin:/bin")
            .env_remove("GERBIL_HOME")
            .env_remove("GERBIL_PATH")
            .env_remove("GERBIL_LOADPATH")
            .env(
                "AITIA_PROJECT_DECLARATION",
                "a runtime path must be ignored",
            )
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        if let Some(input) = input {
            serde_json::to_writer(child.stdin.take().unwrap(), input).unwrap();
        }
        child.wait_with_output().unwrap()
    };
    let read = || {
        let output = run(&["project-manifest"], None);
        assert!(output.status.success(), "{output:?}");
        serde_json::from_slice::<Value>(&output.stdout).unwrap()
    };
    let assert_source_refused = |output: std::process::Output| {
        assert!(!output.status.success(), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        let diagnostic = String::from_utf8_lossy(&output.stderr);
        assert!(
            diagnostic.contains("recorded project.ss differs from the compiled declaration"),
            "{output:?}"
        );
        assert!(
            !diagnostic.contains("untrusted declaration evaluated"),
            "{output:?}"
        );
    };
    record(&["git", "init", "--colocate"]);
    let directory = root.join(".agents/aita");
    std::fs::create_dir_all(&directory).unwrap();
    let source = directory.join("project.ss");
    let data = directory.join("project.json");
    std::fs::write(&source, declaration).unwrap();
    std::fs::write(&data, r#"{"services":{"sysml":{"enable":true}}}"#).unwrap();
    std::fs::write(root.join("Model.sysml"), "package Model {}").unwrap();
    record(&[
        "describe",
        "-m",
        "Record Scheme declaration and JSON overlay",
    ]);
    let first = read();
    assert_eq!(first["manifest"]["services"]["sysml"]["parse"], true);
    assert_eq!(first["inputs"]["sysml"], json!(["Model.sysml"]));

    std::fs::write(&source, format!("{declaration}\n;; changed source\n")).unwrap();
    assert_eq!(read(), first);
    record(&["describe", "-m", "Record changed declaration"]);
    assert_source_refused(run(&["project-manifest"], None));
    std::fs::write(&source, "(error \"untrusted declaration evaluated\")\n").unwrap();
    record(&["describe", "-m", "Record an executable replacement"]);
    assert_source_refused(run(&["project-manifest"], None));
    std::fs::remove_file(&source).unwrap();
    std::fs::write(&data, r#"{"schemaVersion":1}"#).unwrap();
    record(&["describe", "-m", "Remove compiled declaration"]);
    assert_source_refused(run(&["project-manifest"], None));

    std::fs::write(&source, declaration).unwrap();
    std::fs::remove_file(&data).unwrap();
    record(&[
        "describe",
        "-m",
        "Restore the compiled declaration without an overlay",
    ]);
    let restored = read();
    assert_eq!(restored["manifest"]["services"]["sysml"]["parse"], false);
    assert_eq!(restored["inputs"]["sysml"], json!([]));

    let mut overlay: Value =
        serde_json::from_str(include_str!("../../../../../.agents/aita/project.json")).unwrap();
    overlay.as_object_mut().unwrap().remove("services");
    let naming = &mut overlay["programs"]["jj"]["settings"]["naming"];
    naming["references"] = json!([{
        "identity":"WORK-1", "source":".agents/aita/work.org", "element":"work-1"
    }]);
    naming["languageSources"] = json!([".agents/aita/work.org"]);
    std::fs::write(&data, serde_json::to_vec(&overlay).unwrap()).unwrap();
    write_commit_work_item(root);
    record(&["describe", "-m", "Record the commit policy overlay"]);
    let context = commit::json_output(run(&["jj", "commit"], None));
    let mut draft = json!({
        "proposal":commit_proposal("Review the recorded declaration"),
        "narration":narration(
            "Bind the review to the compiled project declaration.",
            "JJ read the recorded change inventory.",
            "JJ audited the recorded configuration.",
        ),
        "org":commit::review_org(&context),
        "context":context["review"]["context"],
    });
    let preview = commit::json_output(run(&["jj", "commit", "preview"], Some(&draft)));
    assert!(
        preview["review"]["description"]
            .as_str()
            .unwrap()
            .starts_with("AITIA-WORK-1 fix(gitops): Review the recorded declaration\n")
    );
    draft["context"] = preview["review"]["context"].clone();
    let prepared = commit::json_output(run(&["jj", "commit", "prepare"], Some(&draft)));
    assert_eq!(
        prepared["review"]["description"],
        preview["review"]["description"]
    );
    assert!(prepared["attempt"].is_object());

    let applied = commit::json_output(run(
        &["jj", "commit", "apply"],
        Some(&json!({"draft": draft, "attempt": prepared["attempt"]})),
    ));
    let revision = applied["receipt"]["resulting_commit"].as_str().unwrap();
    let evidence_args = ["jj", "commit", "evidence", revision, "--gql"];
    let evidence = commit::json_output(run(&evidence_args, Some(&applied)));
    assert_eq!(evidence["description"], preview["review"]["description"]);
    assert_eq!(evidence["missingReports"], json!([]));
    assert_eq!(
        evidence["lineage"]["query"]["engineeringReference"]["rows"],
        json!([{"engineeringId":"WORK-1","element":"work-1","path":".agents/aita/work.org"}])
    );

    std::fs::write(
        &source,
        format!("{declaration}\n;; changed policy source\n"),
    )
    .unwrap();
    record(&[
        "describe",
        "-m",
        "Record a change to the project declaration",
    ]);
    let changed = aitia_jj::observe_workspace(root).unwrap();
    assert_source_refused(run(&["jj", "commit", "prepare"], Some(&draft)));
    assert_eq!(
        commit::json_output(run(&evidence_args, Some(&applied))),
        evidence
    );
    assert_eq!(aitia_jj::observe_workspace(root).unwrap(), changed);
}

fn write_commit_work_item(root: &std::path::Path) {
    std::fs::write(
        root.join(".agents/aita/work.org"),
        "* Engineering work\n:PROPERTIES:\n:ID: work-1\n:ENGINEERING_ID: WORK-1\n:END:\n",
    )
    .unwrap();
}

fn commit_proposal(summary: &str) -> Value {
    json!({"identity":"narration", "reference":"WORK-1", "type":"fix",
        "scope":"gitops", "summary":summary, "language":"en", "languageSource":".agents/aita/work.org",
        "rationale":"Repairs the recorded commit admission boundary"})
}

fn narration(change: &str, recorded: &str, audited: &str) -> Value {
    json!({"change":change,"evidence":[
        {"obligation":"SWE-083","text":recorded},
        {"obligation":"SWE-084","text":audited}
    ],"open":[]})
}

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
        br#"{"schemaVersion":1,"services":{"assurance":{"enable":true,"project":"cli-assurance","profile":"adr-0008"}},"programs":{"jj":{"enable":true,"settings":{"project":"cli-assurance","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-083","checks":[{"requirement":"SWE-083","method":"jj.recorded-change"},{"requirement":"SWE-084","method":"jj.configuration-audit"}],"naming":{"projectKey":"TEST","types":["feat","fix","test"],"scopes":[{"name":"gitops","paths":[".agents/aita","change.txt"]}],"references":[{"identity":"WORK-1","source":".agents/aita/work.org","element":"work-1"}],"languageSources":[".agents/aita/work.org"]}}}}}"#,
    ).unwrap();
    write_commit_work_item(root);
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
    for arguments in [
        &["commit-context"][..],
        &["jj", "commit", "prepare", "extra"],
    ] {
        let refused = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .args(arguments)
            .current_dir(&recorded)
            .output()
            .unwrap();
        assert!(!refused.status.success(), "{refused:?}");
        assert!(refused.stdout.is_empty());
    }
    assert_eq!(aitia_jj::observe_workspace(root).unwrap(), original);
    let context = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .args(["jj", "commit"])
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
    let paths: Vec<_> = context["changes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|change| change["path"].as_str().unwrap())
        .collect();
    assert_eq!(
        paths,
        [
            ".agents/aita/project.json",
            ".agents/aita/work.org",
            "dev/qualification/job-executor/test_unique_effect.py",
            "dev/qualification/job-executor/worker.py",
        ]
    );
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
    let run_draft = |command, org: &str, review_context: &Value| {
        let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .args(["jj", "commit", command])
            .current_dir(&recorded)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(
            child.stdin.take().unwrap(),
            &serde_json::json!({
                "proposal": commit_proposal("Record the candidate configuration"),
                "narration": narration(
                    "Bind the recorded paths and audited Git object.",
                    "JJ read the changed paths.",
                    "JJ audited the recorded configuration.",
                ),
                "org": org,
                "context": review_context,
            }),
        )
        .unwrap();
        child.wait_with_output().unwrap()
    };
    let description = run_draft("preview", &org, &context["review"]["context"]);
    assert!(description.status.success(), "{:?}", description);
    let description: Value = serde_json::from_slice(&description.stdout).unwrap();
    assert_eq!(description["review"]["draftValid"], true);
    let rendered = description["review"]["description"].as_str().unwrap();
    assert!(rendered.starts_with("TEST-WORK-1 fix(gitops): Record the candidate configuration\n"));
    assert!(!rendered.contains(original.tree_id()));
    assert!(!rendered.contains("AITIA-Draft:"));
    assert!(!rendered.contains("sha256:"));

    let refused = run_draft("prepare", "", &description["review"]["context"]);
    assert!(!refused.status.success(), "{:?}", refused);
    let refused: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(refused.get("attempt").is_none());
    let prepared = run_draft("prepare", &org, &description["review"]["context"]);
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
