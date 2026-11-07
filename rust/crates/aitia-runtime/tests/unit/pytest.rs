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

#[test]
fn checks_junit_structure_and_case_outcomes() {
    let report = parse_report(br#"<testsuites><testsuite><testcase/><testcase><failure/></testcase><testcase><skipped/></testcase><testcase><error/></testcase></testsuite></testsuites>"#).unwrap();
    assert_eq!((report.passed, report.failed, report.skipped), (1, 2, 1));
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
        skipped: 0,
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
