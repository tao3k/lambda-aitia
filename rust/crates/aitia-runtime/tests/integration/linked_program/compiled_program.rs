// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Process-level controls use the same compiled CLI and installed dependencies.
use std::{
    path::{Path, PathBuf},
    process::Command,
};

fn executable() -> PathBuf {
    // Seatbelt matches the resolved executable path. Cargo may report /tmp,
    // which resolves to /private/tmp on macOS.
    Path::new(env!("CARGO_BIN_EXE_aitia"))
        .canonicalize()
        .expect("resolve linked AITIA executable")
}

fn profile(binary: &Path, pure: bool) -> String {
    let binary = serde_json::to_string(binary).unwrap();
    let processes = if pure { "(deny process-exec)" } else { "" };
    format!(
        r##"(version 1)(allow default)
        (deny file-read* (regex #"\.(ss|ssi|scm|o[0-9]+)$"))
        (deny process-exec (regex #"/(gxi|gxc|gsc|gsi|gerbil)$"))
        {processes}(allow process-exec (literal {binary}))"##
    )
}

pub(super) fn command(arguments: &[&str]) -> Command {
    let pure = matches!(
        arguments,
        ["project-manifest"]
            | ["jj", "commit", "evidence", _]
            | ["jj", "commit", "evidence", _, "--gql"]
            | ["jj", "commit"]
            | ["jj", "commit", "preview" | "prepare"]
    );
    let mut command = Command::new("/usr/bin/sandbox-exec");
    let binary = executable();
    command.args(["-p", &profile(&binary, pure)]);
    command.arg(binary);
    command.args(arguments);
    command
}

pub(super) fn assert_controls(directory: &Path) {
    let source = directory.join("must-not-load.ssi");
    std::fs::write(&source, "Scheme interface access must be denied\n").unwrap();
    let binary = executable();
    let read = Command::new("/usr/bin/sandbox-exec")
        .args(["-p", &profile(&binary, false), "/bin/cat"])
        .arg(source)
        .output()
        .unwrap();
    assert!(
        !read.status.success(),
        "Scheme metadata control was readable"
    );
    assert!(
        String::from_utf8_lossy(&read.stderr).contains("Operation not permitted"),
        "{read:?}"
    );
    let execute = Command::new("/usr/bin/sandbox-exec")
        .args(["-p", &profile(&binary, true), "/usr/bin/true"])
        .output()
        .unwrap();
    assert!(
        !execute.status.success(),
        "pure review allowed another program"
    );
    assert!(
        String::from_utf8_lossy(&execute.stderr).contains("Operation not permitted"),
        "{execute:?}"
    );
}
