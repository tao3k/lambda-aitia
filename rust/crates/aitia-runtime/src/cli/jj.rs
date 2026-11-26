// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin CLI adapter for `aitia jj ...` subcommands.

use super::{print_json, read_request};
use crate::commit::{self, CommitOutcome};
use std::io::{self, Write};

const JJ_USAGE: &str = "usage: aitia jj <commit|git push>; see aitia --help";
const COMMIT_USAGE: &str = "usage: aitia jj commit [preview|prepare|apply|decision|recover]\n       Without an operation, print the read-only commit context.\n       aitia jj commit preview --applied < reviewed-attempt.json\n       aitia jj commit evidence <revision> [--gql] < applied-or-recovered.json";

pub(super) fn run(arguments: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let words: Vec<&str> = arguments.iter().map(String::as_str).collect();
    if let ["commit", operation @ ..] = words.as_slice() {
        return run_commit(operation);
    }
    let (recover, route) = match words.as_slice() {
        ["git", "push", "--recover", route @ ..] => (true, route),
        ["git", "push", route @ ..] => (false, route),
        _ => return Err(io::Error::other(JJ_USAGE).into()),
    };
    let (remote, bookmark) = match route {
        ["--bookmark", bookmark] => ("origin", *bookmark),
        ["--remote", remote, "--bookmark", bookmark]
        | ["--bookmark", bookmark, "--remote", remote] => (*remote, *bookmark),
        _ => return Err(io::Error::other(JJ_USAGE).into()),
    };
    let input = read_request()?;
    let receipt = if recover {
        commit::recover_push(&input, remote, bookmark)?
    } else {
        commit::push(&input, remote, bookmark)?
    };
    print_json(&receipt)
}

fn run_commit(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    if let ["evidence", revision, options @ ..] = operation {
        let query = match options {
            [] => false,
            ["--gql"] => true,
            _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, COMMIT_USAGE).into()),
        };
        return print_json(&commit::evidence(revision, &read_request()?, query)?);
    }
    let command = match operation {
        [] => None,
        ["--help" | "-h"] => {
            return writeln!(io::stdout().lock(), "{COMMIT_USAGE}").map_err(Into::into);
        }
        [verb @ ("preview" | "prepare" | "apply" | "decision" | "recover")] => Some(*verb),
        ["preview", "--applied"] => Some("preview"),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, COMMIT_USAGE).into()),
    };
    if let Some(verb @ ("decision" | "recover")) = command {
        let result = commit::execute_decision_or_recover(verb, &read_request()?)?;
        return print_json(&result);
    }
    let preview_applied = operation == ["preview", "--applied"];
    let input = (command.is_some() || preview_applied)
        .then(read_request)
        .transpose()?;
    match commit::execute_commit_action(command, preview_applied, input.as_deref())? {
        CommitOutcome::Accepted(result) => print_json(&result),
        CommitOutcome::RejectedDraft(result) => {
            print_json(&result)?;
            Err(io::Error::other(
                "Commit draft lacks current admitted support or violates its Contract",
            )
            .into())
        }
    }
}
