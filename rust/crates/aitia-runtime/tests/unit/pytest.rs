// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::{PytestExit, PytestReport, PytestRun, PytestVerdict, parse_report, run_bounded};
use std::io;
use std::process::Command;
use std::time::Duration;

#[test]
fn captures_status_and_combined_output() -> io::Result<()> {
    let mut command = Command::new("/bin/sh");
    command.args(["-c", "printf out; printf err >&2; exit 7"]);
    let (exit, tail) = run_bounded(command, Duration::from_secs(2), 1024)?;
    assert!(matches!(exit, PytestExit::Exited(status) if status.code() == Some(7)));
    assert_eq!(tail, b"outerr");
    Ok(())
}

#[test]
fn bounds_timeout_and_output() {
    let mut command = Command::new("/bin/sh");
    command.args(["-c", "sleep 30 & wait"]);
    let (exit, _) = run_bounded(command, Duration::from_millis(100), 1024)
        .expect("control timed-out process group");
    assert_eq!(exit, PytestExit::TimedOut);

    let mut command = Command::new("/bin/sh");
    command.args(["-c", "printf oversized"]);
    let (exit, _) = run_bounded(command, Duration::from_secs(2), 4)
        .expect("control output-exceeded process group");
    assert_eq!(exit, PytestExit::OutputExceeded);
}

#[test]
#[ignore = "requires AITIA_PYTEST_PYTHON pointing to a Python with pytest"]
fn observes_real_pytest_and_detects_source_mutation() -> io::Result<()> {
    use crate::{capture_source_tree, run_frozen_pytest};
    use std::{fs, path::PathBuf};

    let interpreter =
        PathBuf::from(std::env::var_os("AITIA_PYTEST_PYTHON").expect("set AITIA_PYTEST_PYTHON"));
    let source = tempfile::tempdir()?;
    fs::write(source.path().join("test_frozen.py"), b"from pathlib import Path\ndef test_frozen():\n    assert Path('input.txt').read_text() == 'frozen'\ndef test_mutation():\n    Path('input.txt').write_text('mutated')\n")?;
    fs::write(source.path().join("input.txt"), b"frozen")?;
    let payload = capture_source_tree(source.path())?;
    fs::write(source.path().join("input.txt"), b"edited")?;

    let clean = run_frozen_pytest(&interpreter, &payload, &["test_frozen.py::test_frozen"])?;
    assert!(
        matches!(clean.exit, PytestExit::Exited(status) if status.success()),
        "{clean:?}"
    );
    assert!(clean.source_unchanged);
    assert_eq!(clean.verdict(), PytestVerdict::Passed);
    assert_eq!(clean.selectors, ["test_frozen.py::test_frozen"]);
    assert_eq!(
        clean.observed_source_sha256.as_ref(),
        Some(&clean.source_sha256)
    );
    let report = clean.report.expect("well-formed pytest report");
    assert_eq!((report.passed, report.failed, report.skipped), (1, 0, 0));
    assert!(report.sha256.starts_with("sha256:"));
    assert_eq!(report.sha256.len(), 71);
    let mutation = run_frozen_pytest(&interpreter, &payload, &["test_frozen.py::test_mutation"])?;
    assert!(
        matches!(mutation.exit, PytestExit::Exited(status) if status.success()),
        "{mutation:?}"
    );
    assert!(!mutation.source_unchanged);
    assert_eq!(mutation.verdict(), PytestVerdict::SourceChanged);
    assert_eq!(mutation.source_sha256, clean.source_sha256);
    assert_ne!(
        mutation.observed_source_sha256,
        clean.observed_source_sha256
    );
    assert_eq!(fs::read(source.path().join("input.txt"))?, b"edited");
    assert!(run_frozen_pytest(&interpreter, &payload, &["../test_frozen.py"]).is_err());
    assert!(run_frozen_pytest(&interpreter, &payload, &["-k"]).is_err());
    Ok(())
}

#[cfg(feature = "gitops")]
#[test]
#[ignore = "requires JJ and a Python with pytest"]
fn observes_adr_0008_at_a_recorded_cut() -> Result<(), Box<dyn std::error::Error>> {
    #[cfg(feature = "linked-program")]
    return crate::with_linked_program(|program| Ok(check_adr_0008_at_a_recorded_cut(&program)))?;
    #[cfg(not(feature = "linked-program"))]
    check_adr_0008_at_a_recorded_cut()
}

#[cfg(feature = "gitops")]
fn check_adr_0008_at_a_recorded_cut(
    #[cfg(feature = "linked-program")] program: &crate::AitiaProgram<'_>,
) -> Result<(), Box<dyn std::error::Error>> {
    use crate::run_recorded_pytest;
    use aitia_jj::{JjObservationError, observe_workspace};
    use std::path::{Path, PathBuf};

    let interpreter =
        PathBuf::from(std::env::var_os("AITIA_PYTEST_PYTHON").expect("set AITIA_PYTEST_PYTHON"));
    let jj = PathBuf::from(std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN"));
    let fixture =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../dev/qualification/job-executor");
    let workspace = tempfile::tempdir()?;
    let root = workspace.path();
    let project = "jj-qualification";
    let jj = |args: &[&str]| -> io::Result<()> {
        let result = Command::new(&jj)
            .current_dir(root)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()?;
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        Ok(())
    };
    jj(&["git", "init", "--colocate"])?;
    let paths = ["test_unique_effect.py", "worker.py"];
    for path in paths {
        std::fs::copy(fixture.join(path), root.join(path))?;
    }
    jj(&["describe", "-m", "record ADR 0008 fixtures"])?;

    // The recorded input wins over a checkout edit that would fail to import.
    std::fs::write(
        root.join("worker.py"),
        "raise RuntimeError('checkout substitution')",
    )?;
    let test = "test_unique_effect.py::test_unique_effect_after_lost_ack_and_restart";
    let fixed_selector = format!("{test}[fixed]");
    let buggy_selector = format!("{test}[buggy]");
    assert!(matches!(
        run_recorded_pytest(&interpreter, "", observe_workspace(root)?, &paths, &[&fixed_selector]),
        Err(JjObservationError::Io(error)) if error.kind() == io::ErrorKind::InvalidInput
    ));
    let fixed = run_recorded_pytest(
        &interpreter,
        project,
        observe_workspace(root)?,
        &paths,
        &[&fixed_selector],
    )?;
    let buggy = run_recorded_pytest(
        &interpreter,
        project,
        observe_workspace(root)?,
        &paths,
        &[&buggy_selector],
    )?;
    let current_fixed = fixed.current_observation()?;
    let current_buggy = buggy.current_observation()?;
    assert_eq!(fixed.cut(), buggy.cut());
    for (run, selector) in [
        (current_fixed, &fixed_selector),
        (current_buggy, &buggy_selector),
    ] {
        assert!(run.source_unchanged, "{run:?}");
        assert_eq!(run.selectors, [selector.as_str()]);
        assert_eq!(
            run.observed_source_sha256.as_ref(),
            Some(&run.source_sha256)
        );
    }
    assert_eq!(current_fixed.source_sha256, current_buggy.source_sha256);
    assert_eq!(current_fixed.verdict(), PytestVerdict::Passed);
    let report = current_fixed.report.as_ref().expect("passing report");
    assert_eq!((report.passed, report.failed, report.skipped), (1, 0, 0));
    assert!(matches!(current_buggy.exit, PytestExit::Exited(status) if status.code() == Some(1)));
    assert_eq!(current_buggy.verdict(), PytestVerdict::ProcessFailed);
    let report = current_buggy.report.as_ref().expect("failing report");
    assert_eq!((report.passed, report.failed, report.skipped), (0, 1, 0));
    let output = String::from_utf8_lossy(&current_buggy.output_tail);
    assert!(output.contains("assert 2 == 1"), "{output}");
    assert_eq!(
        report.failure_messages[0].lines().next(),
        Some("AssertionError: ADR0008 duplicate effects: expected 1, observed 2")
    );

    assert!(
        run_recorded_pytest(
            &interpreter,
            project,
            observe_workspace(root)?,
            &["../worker.py"],
            &[&fixed_selector]
        )
        .is_err()
    );
    assert!(
        run_recorded_pytest(
            &interpreter,
            project,
            observe_workspace(root)?,
            &["missing.py"],
            &[&fixed_selector]
        )
        .is_err()
    );
    let replay = std::env::var_os("AITIA_ADR_REPLAY_EVIDENCE")
        .map(|path| {
            crate::source_tree::capture_recorded_source_tree(fixed.cut(), &paths)
                .map(|bytes| (path, bytes))
        })
        .transpose()?;
    #[cfg(feature = "linked-program")]
    let (fixed_receipt, buggy_receipt) = {
        let fixed_receipt = replay_receipt(&fixed, "fixed-check", "passed");
        let buggy_receipt = replay_receipt(&buggy, "buggy-check", "failed");
        let supported = program
            .assess_recorded_pytest(
                adr_scope(root, "fixed-check", &fixed_selector),
                &fixed_receipt,
                &fixed,
            )?
            .expect("admitted fixed replay");
        let contradicted = program
            .assess_recorded_pytest(
                adr_scope(root, "buggy-check", &buggy_selector),
                &buggy_receipt,
                &buggy,
            )?
            .expect("admitted buggy replay");
        assert_eq!(supported["supported"][0][1], "fixed-check");
        assert_eq!(supported["open"], serde_json::json!([]));
        assert_eq!(supported["releaseAuthorized"], false);
        let deployment = &supported["deployment"];
        assert_eq!(
            deployment["assessment"]["scope"],
            "jj-qualification/deployment"
        );
        assert_eq!(
            deployment["assessment"]["revision"],
            fixed.cut().commit_id()
        );
        assert_eq!(deployment["assessment"]["complete"], false);
        assert_eq!(deployment["assessment"]["releaseAuthorized"], false);
        assert_eq!(deployment["assessment"]["witnesses"], serde_json::json!([]));
        assert_eq!(
            deployment["assessment"]["residualDispositions"],
            serde_json::json!([])
        );
        let conditions = deployment["conditions"].as_array().unwrap();
        let remaining = deployment["assessment"]["remaining"].as_array().unwrap();
        assert_eq!(conditions.len(), 6);
        assert_eq!(remaining.len(), conditions.len());
        for (condition, row) in conditions.iter().zip(remaining) {
            assert_eq!(condition["obligation"], row["obligation"]);
            assert_eq!(row["reason"], "admission-missing");
        }
        assert_eq!(conditions[2]["capability"], "provider-retention");
        assert_eq!(
            conditions[5]["obligation"],
            "provider-retry-contract-review"
        );
        assert_eq!(conditions[5]["method"], "human-review");
        assert_eq!(conditions[5]["capability"], "assumption-review");
        let premises = deployment["assessment"]["assumptionAssessments"]
            .as_array()
            .unwrap();
        assert_eq!(premises.len(), 1);
        assert_eq!(
            premises[0]["assumption"],
            "assumption/adr-0008-provider-retry-contract"
        );
        assert_eq!(premises[0]["owner"], "provider-owner");
        assert_eq!(premises[0]["reviewPolicy"], "human-review");
        assert_eq!(premises[0]["blocker"], "review-missing");
        assert_eq!(premises[0]["admission"], false);
        assert_eq!(contradicted["deployment"], *deployment);
        let promoted_org = fixed_receipt.replace(":END:", ":DEPLOYMENT_COMPLETE: true\n:END:");
        let promoted = program
            .assess_recorded_pytest(
                adr_scope(root, "fixed-check", &fixed_selector),
                &promoted_org,
                &fixed,
            )?
            .expect("valid replay citation");
        assert_eq!(promoted["deployment"], *deployment);
        let unknown = crate::ReplayAssessmentScope {
            deployment_profile: Some("unregistered-profile"),
            ..adr_scope(root, "fixed-check", &fixed_selector)
        };
        assert!(
            program
                .assess_recorded_pytest(unknown, &fixed_receipt, &fixed)
                .is_err()
        );

        let relabelled_receipt = fixed_receipt.replace(
            "\"PROJECT\":\"jj-qualification\"",
            "\"PROJECT\":\"another-project\"",
        );
        let relabelled_scope = crate::ReplayAssessmentScope {
            project: "another-project",
            ..adr_scope(root, "fixed-check", &fixed_selector)
        };
        assert!(
            program
                .assess_recorded_pytest(relabelled_scope, &relabelled_receipt, &fixed)?
                .is_none()
        );
        let other = tempfile::tempdir()?;
        jj(&["git", "init", "--colocate", other.path().to_str().unwrap()])?;
        assert_ne!(
            observe_workspace(other.path())?.workspace_root(),
            fixed.cut().workspace_root()
        );
        assert!(
            program
                .assess_recorded_pytest(
                    adr_scope(other.path(), "fixed-check", &fixed_selector),
                    &fixed_receipt,
                    &fixed
                )?
                .is_none()
        );

        let support = &supported["assurance"];
        assert_eq!(support["subject"], project);
        assert_eq!(support["revision"], fixed.cut().commit_id());
        assert_eq!(support["scope"], fixed_selector);
        assert_eq!(support["complete"], true, "{supported}");
        assert_eq!(support["releaseAuthorized"], false);
        assert_eq!(support["assumptionAssessments"], serde_json::json!([]));
        assert_eq!(support["challenges"], serde_json::json!([]));
        assert_eq!(support["remaining"], serde_json::json!([]));
        assert_eq!(support["witnesses"].as_array().unwrap().len(), 1);
        assert_eq!(support["witnesses"][0]["method"], "replay");
        assert_eq!(support["witnesses"][0]["tool"], "pytest");
        assert_eq!(support["witnesses"][0]["scope"], fixed_selector);
        assert_eq!(support["witnesses"][0]["capability"], "pytest");
        assert_eq!(
            support["witnesses"][0]["outcome"],
            current_fixed.report.as_ref().unwrap().sha256
        );
        assert_eq!(
            support["witnesses"][0]["inputs"],
            serde_json::json!(["artifact/recorded-replay-source"])
        );

        assert_eq!(contradicted["contradicted"][0][1], "buggy-check");
        assert_eq!(contradicted["open"], serde_json::json!([["buggy-check"]]));
        let unsupported = &contradicted["assurance"];
        assert_eq!(unsupported["complete"], false);
        assert_eq!(unsupported["witnesses"], serde_json::json!([]));
        assert_eq!(unsupported["remaining"][0]["obligation"], "buggy-check");
        assert_eq!(
            unsupported["remaining"][0]["reason"],
            "counterevidence-present"
        );
        assert_eq!(unsupported["releaseAuthorized"], false);
        let challenges = unsupported["challenges"].as_array().unwrap();
        assert_eq!(challenges.len(), 1);
        let challenge = &challenges[0];
        let report = current_buggy.report.as_ref().unwrap();
        assert_eq!(challenge["kind"], "counterexample");
        assert_eq!(challenge["revision"], buggy.cut().commit_id());
        assert_eq!(challenge["scope"], buggy_selector);
        assert_eq!(challenge["obligation"], "buggy-check");
        assert_eq!(challenge["evidenceDigest"], report.sha256);
        assert_eq!(challenge["relation"], "observed-challenge");

        for (run, org, selector, original, relabelled) in [
            (
                &fixed,
                &fixed_receipt,
                &fixed_selector,
                "fixed-check",
                "buggy-check",
            ),
            (
                &buggy,
                &buggy_receipt,
                &buggy_selector,
                "buggy-check",
                "fixed-check",
            ),
        ] {
            let substituted = org.replace(
                &format!(":OBLIGATION: {original}"),
                &format!(":OBLIGATION: {relabelled}"),
            );
            assert_ne!(&substituted, org);
            assert!(
                program
                    .assess_recorded_pytest(
                        adr_scope(root, relabelled, selector),
                        &substituted,
                        run
                    )?
                    .is_none()
            );
        }

        for invalid in [
            relabelled_receipt,
            fixed_receipt.replace("\"METHOD\":\"pytest\"", "\"METHOD\":\"proof\""),
            fixed_receipt.replace(&current_fixed.source_sha256, &"0".repeat(64)),
            fixed_receipt.replace("\"OUTCOME\":\"passed\"", "\"OUTCOME\":\"failed\""),
            fixed_receipt.replace(
                &current_fixed.report.as_ref().unwrap().sha256,
                &"0".repeat(64),
            ),
        ] {
            assert!(
                program
                    .assess_recorded_pytest(
                        adr_scope(root, "fixed-check", &fixed_selector),
                        &invalid,
                        &fixed
                    )?
                    .is_none()
            );
        }
        assert!(
            program
                .assess_recorded_pytest(
                    adr_scope(root, "fixed-check", &buggy_selector),
                    &fixed_receipt,
                    &fixed
                )?
                .is_none()
        );
        (fixed_receipt, buggy_receipt)
    };
    let stale = observe_workspace(root)?;
    jj(&["describe", "-m", "record the modified worker"])?;
    let rewritten = observe_workspace(root)?;
    assert_eq!(rewritten.change_id(), fixed.cut().change_id());
    assert_ne!(rewritten.commit_id(), fixed.cut().commit_id());
    assert_ne!(rewritten.tree_id(), fixed.cut().tree_id());
    assert!(matches!(
        fixed.current_observation(),
        Err(JjObservationError::ChangedOperation)
    ));
    assert!(matches!(
        run_recorded_pytest(&interpreter, project, stale, &paths, &[&fixed_selector]),
        Err(JjObservationError::ChangedOperation)
    ));
    assert_eq!(fixed.observation().verdict(), PytestVerdict::Passed);
    #[cfg(feature = "linked-program")]
    {
        let stale_fixed = program
            .assess_recorded_pytest(
                adr_scope(root, "fixed-check", &fixed_selector),
                &fixed_receipt,
                &fixed,
            )?
            .expect("historical fixed replay");
        let stale_buggy = program
            .assess_recorded_pytest(
                adr_scope(root, "buggy-check", &buggy_selector),
                &buggy_receipt,
                &buggy,
            )?
            .expect("historical buggy replay");
        assert_eq!(stale_fixed["revision"], rewritten.commit_id());
        assert_eq!(stale_fixed["evidenceRevision"], fixed.cut().commit_id());
        assert_eq!(stale_fixed["supported"], serde_json::json!([]));
        assert!(stale_fixed["assurance"].is_null());
        assert_eq!(
            stale_fixed["deployment"]["assessment"]["revision"],
            rewritten.commit_id()
        );
        assert_eq!(stale_fixed["deployment"]["assessment"]["complete"], false);
        assert_eq!(
            stale_fixed["deployment"]["assessment"]["remaining"]
                .as_array()
                .unwrap()
                .len(),
            6
        );
        assert_eq!(
            stale_fixed["deployment"]["assessment"]["assumptionAssessments"][0]["blocker"],
            "review-missing"
        );

        assert!(stale_buggy["assurance"].is_null());

        assert_eq!(
            stale_fixed["reopened"],
            serde_json::json!([["fixed-check"]])
        );
        assert_eq!(stale_buggy["contradicted"], serde_json::json!([]));
        assert_eq!(stale_buggy["stale"][0][1], "buggy-check");
    }

    std::fs::copy(fixture.join("worker.py"), root.join("worker.py"))?;
    jj(&["describe", "-m", "restore recorded worker bytes"])?;
    jj(&["new", "-m", "advance to the next change"])?;
    let advanced = observe_workspace(root)?;
    assert_ne!(advanced.change_id(), fixed.cut().change_id());
    assert_eq!(advanced.tree_id(), fixed.cut().tree_id());
    #[cfg(feature = "linked-program")]
    {
        let historical = program
            .assess_recorded_pytest(
                adr_scope(root, "fixed-check", &fixed_selector),
                &fixed_receipt,
                &fixed,
            )?
            .expect("history after advancing to a new change");
        assert_eq!(historical["revision"], advanced.commit_id());
        assert_eq!(historical["evidenceRevision"], fixed.cut().commit_id());
        assert_eq!(historical["stale"][0][1], "fixed-check");
        assert_eq!(historical["reopened"], serde_json::json!([["fixed-check"]]));
        assert_eq!(historical["supported"], serde_json::json!([]));
        assert!(historical["assurance"].is_null());
        let old_counterexample = program
            .assess_recorded_pytest(
                adr_scope(root, "buggy-check", &buggy_selector),
                &buggy_receipt,
                &buggy,
            )?
            .expect("counterexample history after advancing to a new change");
        assert_eq!(old_counterexample["stale"][0][1], "buggy-check");
        assert_eq!(old_counterexample["contradicted"], serde_json::json!([]));
        assert_eq!(
            old_counterexample["open"],
            serde_json::json!([["buggy-check"]])
        );
        assert_eq!(old_counterexample["reopened"], serde_json::json!([]));
        let current_run = run_recorded_pytest(
            &interpreter,
            project,
            advanced.clone(),
            &paths,
            &[&fixed_selector],
        )?;
        let current_receipt = replay_receipt(&current_run, "fixed-check", "passed");
        let current = program
            .assess_recorded_pytest(
                adr_scope(root, "fixed-check", &fixed_selector),
                &current_receipt,
                &current_run,
            )?
            .expect("new run admits support at the new cut");
        assert_eq!(current["supported"][0][1], "fixed-check");
        assert_eq!(current["reopened"], serde_json::json!([]));
        assert_eq!(current["assurance"]["revision"], advanced.commit_id());
        assert_eq!(current["assurance"]["complete"], true);
        assert_eq!(current["releaseAuthorized"], false);
    }
    if let Some((path, source)) = replay {
        assert_eq!(
            crate::source_tree::sha256(&source),
            current_fixed.source_sha256
        );
        let runs = [("fixed", current_fixed), ("buggy", current_buggy)].map(|(id, run)| {
            serde_json::json!({
                "id": id,
                "selector": run.selectors[0],
                "verdict": run.verdict().as_str(),
                "sourceSha256": run.source_sha256,
                "outputSha256": run.report.as_ref().expect("observed report").sha256,
            })
        });
        std::fs::write(
            path,
            serde_json::to_vec(&serde_json::json!({
                "project": fixed.project(),
                "before": fixed.cut(),
                "rewritten": rewritten,
                "advanced": advanced,
                "source": source,
                "runs": runs,
            }))?,
        )?;
    }
    Ok(())
}

#[cfg(feature = "linked-program")]
fn adr_scope<'a>(
    workspace: &'a std::path::Path,
    obligation: &'a str,
    selector: &'a str,
) -> crate::ReplayAssessmentScope<'a> {
    crate::ReplayAssessmentScope {
        project: "jj-qualification",
        workspace,
        obligation,
        selector,
        deployment_profile: Some("adr-0008"),
    }
}

#[cfg(feature = "linked-program")]
fn replay_receipt(run: &crate::RecordedPytestRun, obligation: &str, outcome: &str) -> String {
    let cut = run.cut();
    let process = run.observation();
    let report = process.report.as_ref().unwrap();
    let parents = serde_json::to_string(cut.parent_ids()).unwrap();
    let fields = [
        ("PROJECT", run.project()),
        ("WORKSPACE", cut.workspace_name()),
        ("CHANGE", cut.change_id()),
        ("OPERATION", cut.operation_id()),
        ("COMMIT", cut.commit_id()),
        ("TREE", cut.tree_id()),
        ("PARENTS", &parents),
        ("PRODUCER", "aitia-runtime/pytest"),
        ("ID", &report.sha256),
        ("OBLIGATION", obligation),
        ("OUTCOME", outcome),
        ("METHOD", "pytest"),
        ("SELECTOR", &process.selectors[0]),
        ("SOURCE_SHA256", &process.source_sha256),
        ("REPORT_SHA256", &report.sha256),
    ];
    serde_json::to_string(
        &fields
            .into_iter()
            .collect::<std::collections::BTreeMap<_, _>>(),
    )
    .unwrap()
}

#[test]
fn checks_junit_structure_and_case_outcomes() {
    let report = parse_report(br#"<testsuites><testsuite><testcase/><testcase><failure/></testcase><testcase><skipped/></testcase><testcase><error/></testcase></testsuite></testsuites>"#).unwrap();
    assert_eq!((report.passed, report.failed, report.skipped), (1, 2, 1));
    assert_eq!(report.errors, 1);
    for malformed in [
        "<other/>",
        "<testsuite/><testsuite/>",
        "<testsuite><testcase></testsuite>",
        "<testsuite><testcase><failure/><skipped/></testcase></testsuite>",
        "<testsuites><testcase/></testsuites>",
        "<!DOCTYPE testsuite><testsuite/>",
        "<testsuite/>tail",
        "<testsuite><testcase duplicate='a' duplicate='b'/></testsuite>",
    ] {
        assert!(parse_report(malformed.as_bytes()).is_none(), "{malformed}");
    }
}

#[test]
fn local_verdict_requires_current_source_success_and_passing_report() {
    use std::os::unix::process::ExitStatusExt;
    use std::process::ExitStatus;

    let mut run = PytestRun {
        exit: PytestExit::Exited(ExitStatus::from_raw(0)),
        output_tail: vec![],
        source_unchanged: true,
        source_sha256: "source".into(),
        observed_source_sha256: Some("source".into()),
        selectors: vec![],
        report: None,
    };
    assert_eq!(run.verdict(), PytestVerdict::ReportUnavailable);
    let report = PytestReport {
        sha256: "report".into(),
        passed: 0,
        failed: 0,
        errors: 0,
        skipped: 0,
        failure_messages: Vec::new(),
    };
    run.report = Some(report.clone());
    assert_eq!(run.verdict(), PytestVerdict::NoTests);
    run.report = Some(PytestReport {
        skipped: 1,
        ..report.clone()
    });
    assert_eq!(run.verdict(), PytestVerdict::NoPassingTests);
    run.report = Some(PytestReport {
        passed: 1,
        skipped: 1,
        ..report.clone()
    });
    assert_eq!(run.verdict(), PytestVerdict::Skipped);
    run.report = Some(PytestReport {
        passed: 1,
        failed: 1,
        ..report.clone()
    });
    assert_eq!(run.verdict(), PytestVerdict::ProcessFailed);
    run.report = Some(PytestReport {
        passed: 1,
        ..report
    });
    assert_eq!(run.verdict(), PytestVerdict::Passed);
    run.observed_source_sha256 = None;
    assert_eq!(run.verdict(), PytestVerdict::SourceUnavailable);
    run.exit = PytestExit::TimedOut;
    assert_eq!(run.verdict(), PytestVerdict::TimedOut);
    run.exit = PytestExit::OutputExceeded;
    assert_eq!(run.verdict(), PytestVerdict::OutputExceeded);
}
