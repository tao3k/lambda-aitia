// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bounded pytest process observation over frozen source.

use crate::source_tree::sha256;
use crate::{FrozenWorkspace, capture_source_tree, decode_source_tree};
use quick_xml::{Reader, events::Event};
use rustix::event::{PollFd, PollFlags, Timespec, poll};
use rustix::fs::{Mode, OFlags, open};
use rustix::io::Errno;
use rustix::process::{Pid, Signal, kill_process_group};
use std::fs::File;
use std::io::{self, Read};
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

const OUTPUT_TAIL: usize = 8192;
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);
const DEFAULT_OUTPUT_LIMIT: usize = 8 * 1024 * 1024;
const POLL_NANOS: i64 = 100_000_000;

/// Process outcome of a bounded pytest execution.
#[derive(Debug, PartialEq, Eq)]
pub enum PytestExit {
    Exited(ExitStatus),
    TimedOut,
    OutputExceeded,
}

/// Execution receipt for a frozen-source pytest run.
#[derive(Debug)]
pub struct PytestRun {
    pub exit: PytestExit,
    pub output_tail: Vec<u8>,
    pub source_unchanged: bool,
    pub source_sha256: String,
    pub observed_source_sha256: Option<String>,
    pub selectors: Vec<String>,
    pub report: Option<PytestReport>,
}

/// Local disposition of an observed run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PytestVerdict {
    SourceUnavailable,
    SourceChanged,
    TimedOut,
    OutputExceeded,
    ProcessFailed,
    ReportUnavailable,
    NoTests,
    NoPassingTests,
    Skipped,
    Passed,
}

impl PytestVerdict {
    #[must_use]
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SourceUnavailable => "source-unavailable",
            Self::SourceChanged => "source-changed",
            Self::TimedOut => "timed-out",
            Self::OutputExceeded => "output-exceeded",
            Self::ProcessFailed => "process-failed",
            Self::ReportUnavailable => "report-unavailable",
            Self::NoTests => "no-tests",
            Self::NoPassingTests => "no-passing-tests",
            Self::Skipped => "skipped",
            Self::Passed => "passed",
        }
    }
}

impl PytestRun {
    /// A pass requires unchanged source, a successful process, and a report
    /// containing passing cases with no failures or skips.
    #[must_use]
    pub fn verdict(&self) -> PytestVerdict {
        let status = match self.exit {
            PytestExit::TimedOut => return PytestVerdict::TimedOut,
            PytestExit::OutputExceeded => return PytestVerdict::OutputExceeded,
            PytestExit::Exited(status) => status,
        };
        if self.observed_source_sha256.is_none() {
            return PytestVerdict::SourceUnavailable;
        }
        if !self.source_unchanged {
            return PytestVerdict::SourceChanged;
        }
        match &self.report {
            Some(report)
                if report.passed == 0
                    && report.failed == 0
                    && report.skipped == 0
                    && (status.success() || status.code() == Some(5)) =>
            {
                PytestVerdict::NoTests
            }
            _ if !status.success() => PytestVerdict::ProcessFailed,
            None => PytestVerdict::ReportUnavailable,
            Some(report) if report.failed != 0 => PytestVerdict::ProcessFailed,
            Some(report) if report.passed == 0 => PytestVerdict::NoPassingTests,
            Some(report) if report.skipped != 0 => PytestVerdict::Skipped,
            Some(_) => PytestVerdict::Passed,
        }
    }
}

/// Counts observed in a bounded, well-formed pytest JUnit report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PytestReport {
    pub sha256: String,
    pub passed: usize,
    pub failed: usize,
    pub skipped: usize,
}

/// Execute named pytest tests from an isolated copy of a frozen source tree.
///
/// The result describes a process observation. The caller owns the
/// interpreter and the surrounding execution and admission policy.
///
/// # Errors
///
/// Rejects relative or missing interpreters, selectors outside the snapshot,
/// invalid source, and failures to control or observe the process.
pub fn run_frozen_pytest(
    interpreter: &Path,
    payload: &[u8],
    selectors: &[&str],
) -> io::Result<PytestRun> {
    if !interpreter.is_absolute() || !interpreter.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "expected an absolute Python interpreter path",
        ));
    }
    let files = decode_source_tree(payload)?;
    if selectors.is_empty()
        || selectors.iter().any(|selector| {
            let path = selector.split("::").next().unwrap_or_default();
            selector.starts_with('-')
                || selector.contains('\0')
                || files.binary_search_by_key(&path, |file| file.path).is_err()
        })
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "pytest selector must name a file in frozen source",
        ));
    }

    let workspace = FrozenWorkspace::prepare(payload)?;
    let report_dir = tempfile::Builder::new()
        .prefix("aitia-pytest-report-")
        .tempdir()?;
    let report_path = report_dir.path().join("junit.xml");
    let mut command = Command::new(interpreter);
    command
        .args([
            "-m",
            "pytest",
            "-q",
            "-s",
            "-p",
            "no:cacheprovider",
            "--junitxml",
        ])
        .arg(&report_path)
        .arg("--")
        .args(selectors)
        .current_dir(workspace.root())
        .env_remove("PYTHONPATH")
        .env_remove("PYTEST_ADDOPTS")
        .env_remove("PYTEST_PLUGINS")
        .env("PYTEST_DISABLE_PLUGIN_AUTOLOAD", "1")
        .env("PYTHONDONTWRITEBYTECODE", "1");

    let (exit, output_tail) = run_bounded(command, DEFAULT_TIMEOUT, DEFAULT_OUTPUT_LIMIT)?;
    let source_sha256 = sha256(payload);
    let (source_unchanged, observed_source_sha256) = capture_source_tree(workspace.root())
        .map_or((false, None), |after| {
            (after == payload, Some(sha256(&after)))
        });
    Ok(PytestRun {
        exit,
        output_tail,
        source_unchanged,
        source_sha256,
        observed_source_sha256,
        selectors: selectors
            .iter()
            .map(|selector| (*selector).to_owned())
            .collect(),
        report: read_report(&report_path),
    })
}

fn read_report(path: &Path) -> Option<PytestReport> {
    let flags = OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW | OFlags::NONBLOCK;
    let file = File::from(open(path, flags, Mode::empty()).ok()?);
    if !file.metadata().ok()?.is_file() {
        return None;
    }
    let mut bytes = Vec::new();
    file.take(DEFAULT_OUTPUT_LIMIT as u64 + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > DEFAULT_OUTPUT_LIMIT {
        return None;
    }
    parse_report(&bytes)
}

#[derive(Clone, Copy)]
enum CaseOutcome {
    Passed,
    Failed,
    Skipped,
}

fn parse_report(bytes: &[u8]) -> Option<PytestReport> {
    let mut reader = Reader::from_str(std::str::from_utf8(bytes).ok()?);
    reader.config_mut().expand_empty_elements = true;
    let mut report = PytestReport {
        sha256: String::new(),
        passed: 0,
        failed: 0,
        skipped: 0,
    };
    let mut root_seen = false;
    let mut depth = 0_usize;
    let mut suite_depth = None;
    let mut case = None;
    loop {
        match reader.read_event().ok()? {
            Event::Start(start) => {
                let name = start.name();
                let name = name.as_ref();
                for attribute in start.attributes() {
                    attribute.ok()?.unescape_value().ok()?;
                }
                if depth == 0 {
                    if root_seen || !matches!(name, b"testsuites" | b"testsuite") {
                        return None;
                    }
                    root_seen = true;
                }
                depth += 1;
                match name {
                    b"testsuite" if depth <= 2 && suite_depth.is_none() => {
                        suite_depth = Some(depth)
                    }
                    b"testsuite" => return None,
                    b"testcase" if suite_depth == Some(depth - 1) && case.is_none() => {
                        case = Some((depth, CaseOutcome::Passed));
                    }
                    b"testcase" => return None,
                    b"failure" | b"error" | b"skipped" => match &mut case {
                        Some((case_depth, outcome @ CaseOutcome::Passed))
                            if *case_depth + 1 == depth =>
                        {
                            *outcome = if name == b"skipped" {
                                CaseOutcome::Skipped
                            } else {
                                CaseOutcome::Failed
                            };
                        }
                        _ => return None,
                    },
                    _ => {}
                }
            }
            Event::End(_) => {
                if case.is_some_and(|(case_depth, _)| case_depth == depth) {
                    match case.take()?.1 {
                        CaseOutcome::Passed => report.passed += 1,
                        CaseOutcome::Failed => report.failed += 1,
                        CaseOutcome::Skipped => report.skipped += 1,
                    }
                }
                if suite_depth == Some(depth) {
                    suite_depth = None;
                }
                depth = depth.checked_sub(1)?;
            }
            Event::Text(text) if depth == 0 && !text.iter().all(u8::is_ascii_whitespace) => {
                return None;
            }
            Event::DocType(_) => return None,
            Event::CData(_) | Event::GeneralRef(_) if depth == 0 => return None,
            Event::Eof => break,
            _ => {}
        }
    }
    if !root_seen || depth != 0 {
        return None;
    }
    report.sha256 = sha256(bytes);
    Some(report)
}

fn run_bounded(
    mut command: Command,
    timeout: Duration,
    output_limit: usize,
) -> io::Result<(PytestExit, Vec<u8>)> {
    let (reader, writer) = UnixStream::pair()?;
    let stderr: OwnedFd = writer.try_clone()?.into();
    let stdout: OwnedFd = writer.into();
    let mut child = command
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(Stdio::from(stdout))
        .stderr(Stdio::from(stderr))
        .spawn()?;
    // Command retains its copies of the output descriptors until dropped.
    drop(command);
    let observed = observe(&mut child, reader, timeout, output_limit);
    if !matches!(observed, Ok((PytestExit::Exited(_), _))) {
        stop_group(&mut child)?;
    }
    observed
}

fn observe(
    child: &mut Child,
    mut reader: UnixStream,
    timeout: Duration,
    output_limit: usize,
) -> io::Result<(PytestExit, Vec<u8>)> {
    let started = Instant::now();
    let mut buffer = [0; OUTPUT_TAIL];
    let mut tail = Vec::with_capacity(OUTPUT_TAIL);
    let mut total = 0;
    let mut eof = false;
    loop {
        if eof {
            if let Some(status) = child.try_wait()? {
                return Ok((PytestExit::Exited(status), tail));
            }
        }
        let remaining = timeout.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return Ok((PytestExit::TimedOut, tail));
        }
        let nanos = i64::try_from(remaining.as_nanos())
            .unwrap_or(i64::MAX)
            .min(POLL_NANOS);
        let delay = Timespec {
            tv_sec: 0,
            tv_nsec: nanos as _,
        };
        let mut fd = [PollFd::new(&reader, PollFlags::IN)];
        let fds = if eof { &mut fd[..0] } else { &mut fd[..] };
        match poll(fds, Some(&delay)) {
            Ok(0) | Err(Errno::INTR) => continue,
            Ok(_) => {}
            Err(error) => return Err(error.into()),
        }
        let count = reader.read(&mut buffer)?;
        eof = count == 0;
        total += count;
        let discard = (tail.len() + count).saturating_sub(OUTPUT_TAIL);
        tail.drain(..discard);
        tail.extend_from_slice(&buffer[..count]);
        if total > output_limit {
            return Ok((PytestExit::OutputExceeded, tail));
        }
    }
}

fn stop_group(child: &mut Child) -> io::Result<()> {
    let pid = Pid::from_child(child);
    let started = Instant::now();
    let signal = loop {
        let signal = kill_process_group(pid, Signal::KILL);
        if signal != Err(Errno::PERM) || started.elapsed() >= Duration::from_millis(200) {
            break signal;
        }
        // Darwin may deny a signal while the group leader is exiting.
        // Reap it when available, then verify that the group can be stopped.
        child.try_wait()?;
        std::thread::sleep(Duration::from_millis(5));
    };
    match signal {
        Ok(()) | Err(Errno::SRCH) => {}
        Err(error) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error.into());
        }
    }
    child.wait()?;
    Ok(())
}

#[cfg(test)]
#[path = "../tests/unit/pytest.rs"]
mod tests;
