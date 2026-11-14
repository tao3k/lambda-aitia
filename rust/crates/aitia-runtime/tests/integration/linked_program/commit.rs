// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Commit admission, recovery and publication through the linked binary.

#[cfg(target_os = "macos")]
use super::compiled_program;
use super::{commit_proposal, narration, write_commit_work_item};
use serde_json::{Value, json};
use std::process::{Command, Stdio};

#[path = "archive.rs"]
mod archive;

pub(super) fn json_output(output: std::process::Output) -> Value {
    assert!(output.status.success(), "{output:?}");
    serde_json::from_slice(&output.stdout).unwrap()
}

pub(super) fn review_org(context: &Value) -> String {
    context["review"]["clauses"]
        .as_array()
        .unwrap()
        .iter()
        .map(|clause| {
            format!(
                "* Review note\n:PROPERTIES:\n:{}: {}\n:END:\n",
                clause["property"].as_str().unwrap(),
                clause["value"].as_str().unwrap()
            )
        })
        .collect()
}

#[test]
fn commit_requires_a_recorded_workspace() {
    let directory = tempfile::tempdir().unwrap();
    assert!(
        Command::new("git")
            .args(["init", "--quiet"])
            .current_dir(directory.path())
            .status()
            .unwrap()
            .success()
    );
    let rejected = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .args(["jj", "commit"])
        .current_dir(directory.path())
        .output()
        .unwrap();
    assert_eq!(rejected.status.code(), Some(1), "{rejected:?}");
    assert!(rejected.stdout.is_empty(), "{rejected:?}");
    assert!(
        String::from_utf8_lossy(&rejected.stderr).contains("no JJ workspace found"),
        "{rejected:?}"
    );
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
        br#"{"schemaVersion":1,"services":{},"programs":{"jj":{"enable":true,"settings":{"project":"signed-fixture","governance":"signed","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-084","checks":[{"requirement":"SWE-084","method":"jj.configuration-audit"}],"naming":{"projectKey":"TEST","types":["feat","fix","test"],"scopes":[{"name":"gitops","paths":[".agents/aita","change.txt"]}],"references":[{"identity":"WORK-1","source":".agents/aita/work.org","element":"work-1"}],"languageSources":[".agents/aita/work.org"]}}}}}"#,
    ).unwrap();
    write_commit_work_item(&workspace);
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

    let run = |operation: &[&str], input: Value| {
        let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .args(["jj", "commit"])
            .args(operation)
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
    let context = json_output(run(&[], Value::Null));
    let org = review_org(&context);
    let mut draft = json!({"proposal":commit_proposal("Audit the recorded configuration"),
        "narration":{"change":"Bind the Git object to its recorded cut.",
                     "evidence":[{"obligation":"SWE-084","text":"JJ audited the recorded configuration."}],
                     "open":[]},
        "org":org,
        "context":context["review"]["context"]});
    let preview = json_output(run(&["preview"], draft.clone()));
    draft["context"] = preview["review"]["context"].clone();
    let prepared = json_output(run(&["prepare"], draft.clone()));
    assert_eq!(
        prepared["governanceRevision"],
        context["governanceRevision"]
    );
    let denied = run(
        &["apply"],
        json!({"draft":draft, "attempt":prepared["attempt"]}),
    );
    assert!(!denied.status.success(), "{denied:?}");
    assert!(String::from_utf8_lossy(&denied.stderr).contains("requires a signed commit approval"));
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), original);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let approval_message = |identity: &str, not_before, expires_at| {
        json!({"kind":"aitia.commit.approve.v1", "project":"signed-fixture",
            "revision":prepared["governanceRevision"], "approval":identity,
            "intent":prepared["intent"], "notBefore":not_before, "expiresAt":expires_at})
        .to_string()
    };
    let signed = |message: &str| json!({"message":message, "signature":hex(signer.sign(message.as_bytes()).as_ref())});
    let message = approval_message("first", now, now + 300);
    let forged = run(
        &["decision"],
        json!({"message":message, "signature":"00".repeat(64)}),
    );
    assert!(!forged.status.success(), "{forged:?}");
    assert!(String::from_utf8_lossy(&forged.stderr).contains("signature rejected"));
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), original);
    json_output(run(&["decision"], signed(&message)));

    let refuse = |draft: &Value, attempt: &Value, approval: &str| {
        let output = run(
            &["apply"],
            json!({"draft":draft,"attempt":attempt,"approval":approval}),
        );
        assert!(
            !output.status.success() && output.stdout.is_empty(),
            "{output:?}"
        );
        assert!(
            String::from_utf8_lossy(&output.stderr).contains("description write admission refused"),
            "{output:?}"
        );
        assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), original);
    };
    let expired = approval_message("expired", now - 60, now - 1);
    json_output(run(&["decision"], signed(&expired)));
    refuse(&draft, &prepared["attempt"], "expired");

    let revoke = |approval: &str| {
        let message = json!({"kind":"aitia.commit.revoke.v1", "project":"signed-fixture",
            "revision":prepared["governanceRevision"], "approval":approval})
        .to_string();
        json_output(run(&["decision"], signed(&message)));
    };
    let revoked = approval_message("revoked", now, now + 300);
    json_output(run(&["decision"], signed(&revoked)));
    revoke("revoked");
    refuse(&draft, &prepared["attempt"], "revoked");

    let policy_bytes = std::fs::read(&policy).unwrap();
    let mut changed_policy = policy_bytes.clone();
    changed_policy.push(b'\n');
    std::fs::write(&policy, changed_policy).unwrap();
    refuse(&draft, &prepared["attempt"], "first");
    std::fs::write(&policy, policy_bytes).unwrap();
    let mut changed_reasoning = draft.clone();
    changed_reasoning["proposal"]["rationale"] =
        json!("A different rationale needs its own review");
    let revised_preview = json_output(run(&["preview"], changed_reasoning.clone()));
    changed_reasoning["context"] = revised_preview["review"]["context"].clone();
    let revised = json_output(run(&["prepare"], changed_reasoning.clone()));
    assert_eq!(
        revised["review"]["description"],
        prepared["review"]["description"]
    );
    assert_ne!(revised["intent"], prepared["intent"]);
    refuse(&changed_reasoning, &revised["attempt"], "first");
    let written = json_output(run(
        &["apply"],
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
    revoke("first");
    let recovered = json_output(run(&["recover"], json!({"approval":"first"})));
    assert_eq!(recovered["outcome"], "applied");
    assert_eq!(recovered["attempt"], prepared["attempt"]);
    let evidence = json_output(run(&["evidence", published.commit_id()], recovered));
    assert_eq!(evidence["original"], written["cut"]);
    assert_eq!(evidence["description"], written["review"]["description"]);
    assert_eq!(evidence["observations"], json!([]));
    assert_eq!(
        evidence["missingReports"],
        json!(["jj.configuration-audit"])
    );
    // A genuine recorded inventory still falls outside this configuration-only policy.
    use sha2::{Digest, Sha256};
    let report = &written["changes"];
    let mut extra = written.clone();
    extra["executions"].as_array_mut().unwrap().push(json!({
        "method":"jj.recorded-change",
        "report":report,
        "reportDigest":format!("sha256:{:x}", Sha256::digest(serde_json::to_vec(report).unwrap())),
        "inputDigest":written["executions"][0]["inputDigest"],
    }));
    let rejected = run(&["evidence", published.commit_id()], extra);
    assert!(
        !rejected.status.success() && rejected.stdout.is_empty(),
        "{rejected:?}"
    );
    assert!(
        String::from_utf8_lossy(&rejected.stderr)
            .contains("Archived check method is outside the recorded policy"),
        "{rejected:?}"
    );
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
    std::fs::write(workspace.join(".agents/aita/project.json"), br#"{"schemaVersion":1,"services":{},"programs":{"jj":{"enable":true,"settings":{"project":"reviewed-push-fixture","profile":"nasa/sdlc/npr-7150.2","primary":"SWE-084","checks":[{"requirement":"SWE-083","method":"jj.recorded-change"},{"requirement":"SWE-084","method":"jj.configuration-audit"}],"naming":{"projectKey":"TEST","primaryLanguage":"en","types":["feat","fix","test"],"scopes":[{"name":"gitops","paths":[".agents/aita","change.txt"]}],"references":[{"identity":"WORK-1","source":".agents/aita/work.org","element":"work-1"}],"languageSources":[".agents/aita/work.org"]}}}}}"#).unwrap();
    std::fs::write(
        workspace.join(".agents/aita/work.org"),
        "* Review the commit\n:PROPERTIES:\n:ID: work-1\n:ENGINEERING_ID: WORK-1\n:END:\nThe project uses English.\n",
    )
    .unwrap();
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
        let started = std::time::Instant::now();
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
            .env("GIT_ALLOW_PROTOCOL", "file")
            .env_remove("GERBIL_HOME")
            .env_remove("GERBIL_PATH")
            .env_remove("GERBIL_LOADPATH")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(child.stdin.take().unwrap(), input).unwrap();
        let output = child.wait_with_output().unwrap();
        eprintln!(
            "AITIA-LINKED-TEST: {args:?} exited {} in {:.3}s",
            output.status,
            started.elapsed().as_secs_f64()
        );
        output
    };
    let context = json_output(run(&["jj", "commit"], &Value::Null));
    assert_eq!(
        context["recordedReviewBookmarks"],
        json!([{"remote":"origin","bookmark":"reviewed","commit":base.commit_id(),"githubRepository":null}])
    );
    assert_eq!(
        context["providerReview"],
        json!({"status":"unsupported-remote"})
    );
    assert_eq!(
        context["review"]["semantics"]["references"],
        json!([["WORK-1", ".agents/aita/work.org", "work-1"]])
    );
    assert_eq!(context["review"]["auditChecklist"], json!([]));
    assert!(context["review"]["pullRequest"].is_null());
    assert!(context["review"]["draftValid"].is_null());
    let executions = context["executions"].as_array().unwrap();
    assert_eq!(executions.len(), 2);
    for execution in executions {
        use sha2::{Digest, Sha256};
        let actual = Sha256::digest(serde_json::to_vec(&execution["report"]).unwrap());
        assert_eq!(execution["reportDigest"], format!("sha256:{actual:x}"));
        match execution["method"].as_str().unwrap() {
            "jj.recorded-change" => assert_eq!(execution["report"], context["changes"]),
            "jj.configuration-audit" => {
                assert_eq!(execution["report"]["git_commit"], context["cut"]["commit"]);
                assert_eq!(execution["report"]["git_tree"], context["cut"]["tree"]);
            }
            method => panic!("unexpected host check: {method}"),
        }
    }
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
    let mut proposal = commit_proposal("Publish the reviewed change");
    proposal["rationale"] =
        json!("Review the GitOps change against the recorded engineering item.");
    let mut draft = json!({"proposal":proposal,
        "narration":narration("Explain why this GitOps change is needed.", "Read the recorded changes.", "Audited the recorded configuration."),
        "org":org,"context":context["review"]["context"]});
    let preview = json_output(run(&["jj", "commit", "preview"], &draft));
    assert_ne!(draft["context"], preview["review"]["context"]);
    draft["context"] = preview["review"]["context"].clone();
    let previous = json_output(run(&["jj", "commit", "prepare"], &draft));

    // Replace the recorded association without changing the title or the
    // engineering identity. Keep the project's language source unchanged.
    let manifest_path = workspace.join(".agents/aita/project.json");
    let mut manifest: Value =
        serde_json::from_slice(&std::fs::read(&manifest_path).unwrap()).unwrap();
    let mut conflicting = manifest.clone();
    let naming = &mut conflicting["programs"]["jj"]["settings"]["naming"];
    let references = naming["references"].as_array_mut().unwrap();
    references.push(json!({
        "identity":"WORK-1", "source":".agents/aita/missing.org", "element":"work-1"
    }));
    naming["scopes"].as_array_mut().unwrap().push(json!({
        "name": "gitops", "paths": ["unrelated"]
    }));
    std::fs::write(&manifest_path, serde_json::to_vec(&conflicting).unwrap()).unwrap();
    run_jj(&["describe", "-m", "Candidate with conflicting association"]);
    let conflict_cut = aitia_jj::observe_workspace(&workspace).unwrap();
    let refused = run(&["jj", "commit", "prepare"], &draft);
    assert!(!refused.status.success(), "{refused:?}");
    let refusal: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(refusal["review"]["description"].is_null());
    assert!(refusal.get("attempt").is_none());
    assert_eq!(
        refusal["review"]["semantics"]["conflictingReferences"],
        json!([["WORK-1"]])
    );
    assert_eq!(
        refusal["review"]["semantics"]["unresolvedReferences"],
        json!([["WORK-1"]])
    );
    assert_eq!(
        refusal["review"]["semantics"]["conflictingScopes"],
        json!([["gitops"]])
    );
    assert_eq!(refusal["review"]["semantics"]["affectedScopes"], json!([]));
    assert!(
        refusal["review"]["semantics"]["open"]
            .as_array()
            .unwrap()
            .iter()
            .any(|row| row[1] == "conflicting-scope")
    );
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        conflict_cut
    );

    std::fs::copy(
        workspace.join(".agents/aita/work.org"),
        workspace.join(".agents/aita/rebound.org"),
    )
    .unwrap();
    manifest["programs"]["jj"]["settings"]["naming"]["references"][0]["source"] =
        json!(".agents/aita/rebound.org");
    std::fs::write(&manifest_path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    run_jj(&["describe", "-m", "Candidate with replacement association"]);
    let rebound_cut = aitia_jj::observe_workspace(&workspace).unwrap();
    let refused = run(&["jj", "commit", "prepare"], &draft);
    assert!(!refused.status.success(), "{refused:?}");
    let refusal: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(refusal["review"]["description"].is_null());
    assert!(refusal.get("attempt").is_none());
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        rebound_cut
    );
    let rebound = json_output(run(&["jj", "commit", "preview"], &draft));
    assert_eq!(
        rebound["review"]["description"],
        preview["review"]["description"]
    );
    assert_ne!(rebound["review"]["context"], draft["context"]);
    draft["context"] = rebound["review"]["context"].clone();
    let refused = run(
        &["jj", "commit", "apply"],
        &json!({"draft":draft,"attempt":previous["attempt"]}),
    );
    assert!(!refused.status.success(), "{refused:?}");
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr)
            .contains("prepared rewrite does not match the reviewed cut"),
        "{refused:?}"
    );
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        rebound_cut
    );

    let mut changed_text = draft.clone();
    changed_text["narration"]["evidence"][0]["text"] = json!("A statement that was not reviewed.");
    let refused = run(&["jj", "commit", "prepare"], &changed_text);
    assert!(!refused.status.success(), "{refused:?}");
    let report: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(report["review"]["description"].is_null());
    assert!(report.get("attempt").is_none());

    let mut invalid = draft.clone();
    invalid["proposal"]["reference"] = json!("PR-2");
    let refused = run(&["jj", "commit", "prepare"], &invalid);
    assert!(!refused.status.success(), "{refused:?}");
    let report: Value = serde_json::from_slice(&refused.stdout).unwrap();
    assert!(report.get("attempt").is_none());
    assert!(
        report["review"]["semantics"]["open"]
            .as_array()
            .unwrap()
            .iter()
            .any(|row| row[1] == "missing-reference")
    );
    let mut free_title = draft.clone();
    free_title.as_object_mut().unwrap().remove("proposal");
    free_title["title"] = json!("TEST-WORK-1 fix(gitops): Bypass source admission");
    assert!(
        !run(&["jj", "commit", "prepare"], &free_title)
            .status
            .success()
    );
    for field in [
        "sources",
        "paths",
        "ruleContext",
        "executions",
        "modelCheck",
        "preview",
    ] {
        let mut forged_host_input = draft.clone();
        forged_host_input[field] = if field == "preview" {
            json!(true)
        } else {
            json!("Agent-supplied host fact")
        };
        let refused = run(&["jj", "commit", "prepare"], &forged_host_input);
        assert!(!refused.status.success(), "{refused:?}");
        assert!(refused.stdout.is_empty());
        assert!(String::from_utf8_lossy(&refused.stderr).contains("unknown field"));
    }
    let prepared = json_output(run(&["jj", "commit", "prepare"], &draft));
    let revision = prepared["attempt"]["resulting_commit"].as_str().unwrap();
    let evidence_args = ["jj", "commit", "evidence", revision];
    let mut unpublished = prepared.clone();
    unpublished["receipt"] = json!({
        "expected": {"workspace_name": prepared["cut"]["workspace"],
            "operation_id": prepared["cut"]["operation"], "commit_id": prepared["cut"]["commit"]},
        "resulting_operation": prepared["attempt"]["resulting_operation"],
        "resulting_commit": revision,
        "description": prepared["review"]["description"],
    });
    let invisible = run(&evidence_args, &unpublished);
    assert!(!invisible.status.success(), "{invisible:?}");
    assert!(String::from_utf8_lossy(&invisible.stderr).contains("not visible in local JJ history"));
    let mut recovery = json_output(run(
        &["jj", "commit", "recover"],
        &json!({"attempt": prepared["attempt"]}),
    ));
    assert_eq!(recovery["outcome"], "unresolved");
    assert!(!run(&evidence_args, &recovery).status.success());
    recovery["outcome"] = json!("applied");
    let invisible = run(&evidence_args, &recovery);
    assert!(!invisible.status.success());
    assert!(String::from_utf8_lossy(&invisible.stderr).contains("not visible in local JJ history"));

    let approved = json!({"draft":draft,"attempt":prepared["attempt"]});
    let applied_preview = ["jj", "commit", "preview", "--applied"];
    assert!(!run(&applied_preview, &approved).status.success());
    let mut refreshed = approved.clone();
    refreshed["draft"]["proposal"]["rationale"] =
        json!("Reassess the same engineering item without changing the rendered description.");
    let preview = json_output(run(&["jj", "commit", "preview"], &refreshed["draft"]));
    assert_eq!(
        preview["review"]["previewDescription"],
        prepared["review"]["description"]
    );
    assert_ne!(preview["review"]["context"], approved["draft"]["context"]);
    refreshed["draft"]["context"] = preview["review"]["context"].clone();
    let refused = run(&["jj", "commit", "apply"], &refreshed);
    assert_eq!(refused.status.code(), Some(1), "{refused:?}");
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr)
            .contains("prepared rewrite does not match the current review context"),
        "{refused:?}"
    );
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        rebound_cut
    );
    let written = json_output(run(&["jj", "commit", "apply"], &approved));
    let (evidence, recovered, recovered_evidence) = archive::assert_applied_readback(
        &run,
        revision,
        base.commit_id(),
        &prepared["attempt"],
        &written,
        &workspace,
    );

    let description = written["review"]["description"].as_str().unwrap();
    assert!(description.starts_with("TEST-WORK-1 fix(gitops): Publish the reviewed change\n"));
    assert!(description.contains("\n\nEvidence\n- SWE-083: Read the recorded changes.\n"));
    assert!(description.contains("- SWE-084: Audited the recorded configuration.\n"));
    assert!(!description.contains("\nOpen\n"));
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
    let mut signed = approved.clone();
    signed["approval"] = json!("local-description-only");
    let refused = run(&args, &signed);
    assert!(!refused.status.success(), "{refused:?}");
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr)
            .contains("Signed description approval does not authorize a remote push")
    );
    assert_eq!(head(), base.commit_id());
    let stale_context = "Commit review context is stale";
    for changed_field in ["context", "digest", "rationale", "org"] {
        let mut stale_review = approved.clone();
        match changed_field {
            "context" => stale_review["draft"]["context"] = json!("retired review context"),
            "digest" => {
                stale_review["draft"]["context"] = json!(format!("sha256:{}", "0".repeat(64)))
            }
            "rationale" => {
                stale_review["draft"]["proposal"]["rationale"] =
                    json!("A different intent was never part of this review");
            }
            _ => {
                stale_review["draft"]["org"] = json!(format!(
                    "{}\nAdditional ORG material.\n",
                    stale_review["draft"]["org"].as_str().unwrap()
                ));
            }
        }
        let refused = run(&args, &stale_review);
        assert!(!refused.status.success(), "{changed_field}: {refused:?}");
        assert!(String::from_utf8_lossy(&refused.stderr).contains(stale_context));
        assert_eq!(head(), base.commit_id());
    }
    let config = |args: &[&str]| {
        let output = Command::new("git")
            .current_dir(&workspace)
            .arg("config")
            .args(args)
            .output()
            .unwrap();
        assert!(output.status.success(), "{output:?}");
    };
    let before_route_change = aitia_jj::observe_workspace(&workspace).unwrap();
    config(&["remote.origin.pushurl", "git@github.com:team/project.git"]);
    let refused = run(&args, &approved);
    assert!(!refused.status.success(), "{refused:?}");
    assert!(String::from_utf8_lossy(&refused.stderr).contains(stale_context));
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        before_route_change
    );
    assert_eq!(head(), base.commit_id());
    config(&["--unset", "remote.origin.pushurl"]);
    // Both local repositories advertise the same bookmark and commit.
    let alternate = fixture.path().join("alternate.git");
    let cloned = Command::new("git")
        .args(["clone", "--bare", "--quiet"])
        .arg(&remote)
        .arg(&alternate)
        .output()
        .unwrap();
    assert!(cloned.status.success(), "{cloned:?}");
    config(&["remote.origin.pushurl", alternate.to_str().unwrap()]);
    let refused = run(&args, &approved);
    assert!(!refused.status.success(), "{refused:?}");
    assert!(String::from_utf8_lossy(&refused.stderr).contains(stale_context));
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        before_route_change
    );
    assert_eq!(head(), base.commit_id());
    let alternate_head = Command::new("git")
        .arg("--git-dir")
        .arg(&alternate)
        .args(["rev-parse", "refs/heads/reviewed"])
        .output()
        .unwrap();
    assert!(alternate_head.status.success(), "{alternate_head:?}");
    assert_eq!(
        String::from_utf8_lossy(&alternate_head.stdout).trim(),
        base.commit_id()
    );
    config(&["--unset", "remote.origin.pushurl"]);
    let mut changed_description = approved.clone();
    changed_description["draft"]["proposal"]["summary"] = json!("Use a different title");
    let preview = json_output(run(&applied_preview, &changed_description));
    assert_eq!(preview["review"]["matchesWrittenDescription"], false);
    changed_description["draft"]["context"] = preview["review"]["context"].clone();
    assert!(!run(&args, &changed_description).status.success());
    assert_eq!(head(), base.commit_id());

    let mut refreshed = approved.clone();
    refreshed["draft"]["proposal"]["rationale"] = json!("Reconfirm the recorded review facts");
    let preview = json_output(run(&applied_preview, &refreshed));
    assert_eq!(preview["review"]["matchesWrittenDescription"], true);
    assert_eq!(preview["review"]["reviewContextCurrent"], false);
    assert_eq!(preview["review"]["previewDescription"], description);
    assert_eq!(preview["cut"], written["cut"]);
    assert_ne!(preview["review"]["context"], refreshed["draft"]["context"]);
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        before_route_change
    );
    refreshed["draft"]["context"] = preview["review"]["context"].clone();
    let recovery_input = json!({"attempt": prepared["attempt"]});
    let recover_push = ["jj", "git", "push", "--recover", "--bookmark", "reviewed"];
    assert_eq!(
        json_output(run(&recover_push, &recovery_input)),
        json!({"outcome": "unresolved", "receipt": null})
    );
    assert_eq!(head(), base.commit_id());
    let pushed = json_output(run(&args, &refreshed));
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
    let replayed = run(&args, &refreshed);
    assert!(!replayed.status.success(), "{replayed:?}");
    assert_eq!(head(), pushed["commit"].as_str().unwrap());
    let after_push = aitia_jj::observe_workspace(&workspace).unwrap();
    let acknowledgement = json!({"outcome": "acknowledged", "receipt": pushed});
    assert_eq!(
        json_output(run(&recover_push, &recovery_input)),
        acknowledgement
    );
    let other_route = ["jj", "git", "push", "--recover", "--bookmark", "unrelated"];
    assert_eq!(
        json_output(run(&other_route, &recovery_input)),
        json!({"outcome": "unresolved", "receipt": null})
    );
    let mut forged_attempt = recovery_input.clone();
    forged_attempt["attempt"]["description"] = json!("Forged description");
    assert!(!run(&recover_push, &forged_attempt).status.success());
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), after_push);

    // The project can select a check that this Runtime cannot execute.
    // This obligation must appear in the readable preview, without an
    // admitted description or a prepared attempt.
    run_jj(&["new", "-m", "Candidate with an unresolved obligation"]);
    manifest["programs"]["jj"]["settings"]["checks"][1]["method"] =
        json!("qualification.configuration-replay");
    std::fs::write(&manifest_path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    run_jj(&["describe", "-m", "Candidate with an unresolved obligation"]);
    let historical = json_output(run(&evidence_args, &written));
    assert_eq!(historical, evidence);
    assert_eq!(
        json_output(run(&recover_push, &recovery_input)),
        acknowledgement
    );
    assert_eq!(
        json_output(run(&evidence_args, &recovered)),
        recovered_evidence
    );
    let unresolved = json_output(run(&["jj", "commit"], &Value::Null));
    assert_eq!(unresolved["review"]["open"], json!([["SWE-084"]]));
    let mut unresolved_draft = json!({
        "proposal":commit_proposal("Require the configuration replay"),
        "narration":{
            "change":"Require a configuration replay for this change.",
            "evidence":[{"obligation":"SWE-083","text":"Read the recorded changes."}],
            "open":[{"obligation":"SWE-084","text":"Run the configuration replay on this candidate."}]
        },
        "org":review_org(&unresolved),
        "context":unresolved["review"]["context"],
    });
    let preview = json_output(run(&["jj", "commit", "preview"], &unresolved_draft));
    assert!(preview["review"]["description"].is_null());
    assert!(
        preview["review"]["previewDescription"]
            .as_str()
            .unwrap()
            .contains("\n\nOpen\n- SWE-084: Run the configuration replay on this candidate.\n")
    );
    unresolved_draft["context"] = preview["review"]["context"].clone();
    let blocked = run(&["jj", "commit", "prepare"], &unresolved_draft);
    assert!(!blocked.status.success(), "{blocked:?}");
    let refusal: Value = serde_json::from_slice(&blocked.stdout).unwrap();
    assert!(refusal.get("attempt").is_none());
    assert_eq!(head(), pushed["commit"].as_str().unwrap());
    eprintln!("AITIA-LINKED-TEST: unresolved obligation preview and prepare refusal");

    manifest["programs"]["jj"]["settings"]["checks"][1]["method"] = json!("jj.recorded-change");
    std::fs::write(&manifest_path, serde_json::to_vec(&manifest).unwrap()).unwrap();
    run_jj(&["describe", "-m", "Record conflicting check methods"]);
    let conflict_cut = aitia_jj::observe_workspace(&workspace).unwrap();
    let refused = run(&["jj", "commit"], &Value::Null);
    assert_eq!(refused.status.code(), Some(1), "{refused:?}");
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr)
            .contains("Project commit checks must use distinct methods"),
        "{refused:?}"
    );
    assert_eq!(
        aitia_jj::observe_workspace(&workspace).unwrap(),
        conflict_cut
    );
    assert_eq!(head(), pushed["commit"].as_str().unwrap());

    run_jj(&["new", "-m", "Replace the project configuration"]);
    std::fs::write(&manifest_path, r#"{"schemaVersion":2}"#).unwrap();
    run_jj(&[
        "describe",
        "-m",
        "Record an unsupported project configuration",
    ]);
    let current = aitia_jj::observe_workspace(&workspace).unwrap();
    let recover = ["jj", "commit", "recover"];
    assert_eq!(json_output(run(&recover, &recovery_input)), recovered);
    assert!(!run(&recover, &json!({"approval":"first"})).status.success());
    let mut ambiguous = recovery_input;
    ambiguous["approval"] = json!("first");
    assert!(!run(&recover, &ambiguous).status.success());
    assert_eq!(aitia_jj::observe_workspace(&workspace).unwrap(), current);
}
