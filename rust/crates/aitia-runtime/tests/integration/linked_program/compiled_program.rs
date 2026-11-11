// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Process-level controls use the same compiled CLI and installed dependencies.
use std::{path::Path, process::Command};

fn profile(pure: bool) -> String {
    let binary = serde_json::to_string(env!("CARGO_BIN_EXE_aitia")).unwrap();
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
        arguments.first().copied(),
        Some("commit-context" | "commit-description" | "commit-prepare")
    );
    let mut command = Command::new("/usr/bin/sandbox-exec");
    command.args(["-p", &profile(pure), env!("CARGO_BIN_EXE_aitia")]);
    command.args(arguments);
    command
}

pub(super) fn assert_controls(directory: &Path) {
    let source = directory.join("must-not-load.ssi");
    std::fs::write(&source, "Scheme interface access must be denied\n").unwrap();
    let read = Command::new("/usr/bin/sandbox-exec")
        .args(["-p", &profile(false), "/bin/cat"])
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
        .args(["-p", &profile(true), "/usr/bin/true"])
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
