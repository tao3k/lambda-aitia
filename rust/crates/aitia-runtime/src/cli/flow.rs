// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin CLI adapter for `aitia flow ...` subcommands.

use super::{print_json, read_json_stdin, read_request};
use crate::protocol::{DEFAULT_WORKFLOW_CASE, execute_project_protocol};
use crate::{HostCapabilityRegistry, with_linked_program};
use std::io::{self, Write};

const USAGE: &str = "usage: aitia flow capabilities\n       aitia flow reconcile < request.json\n       aitia flow run [--case <id>] [--proposal-stdin]\n       aitia flow gitops [--proposal-stdin]\n       aitia flow submit-patch < proposal.json\n       aitia flow submit-decision < decision.json";

pub(super) fn run(arguments: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let words: Vec<&str> = arguments.iter().map(String::as_str).collect();
    match words.as_slice() {
        ["--help" | "-h"] => writeln!(io::stdout().lock(), "{USAGE}").map_err(Into::into),
        ["capabilities"] => {
            print_json(&HostCapabilityRegistry::default_linked().descriptors_json())
        }
        ["reconcile"] => {
            let request = read_request()?;
            let response = with_linked_program(|program| program.workflow_reconcile(&request))?;
            writeln!(io::stdout().lock(), "{response}").map_err(Into::into)
        }
        ["run", rest @ ..] => {
            let (case_id, overlay) = parse_run_args(rest)?;
            print_json(&execute_project_protocol(case_id, overlay.as_ref())?)
        }
        ["gitops"] | ["gitops", "--proposal-stdin"] => {
            let overlay = (words.len() == 2).then(read_json_stdin).transpose()?;
            print_json(
                &execute_project_protocol(DEFAULT_WORKFLOW_CASE, overlay.as_ref())?["reconciliation"],
            )
        }
        ["submit-patch"] => {
            let overlay = serde_json::json!({ "proposal": read_json_stdin()?, "reconcile": false });
            print_json(
                &execute_project_protocol(DEFAULT_WORKFLOW_CASE, Some(&overlay))?["reconciliation"],
            )
        }
        ["submit-decision"] => {
            let mut decision = read_json_stdin()?;
            let obj = decision.as_object_mut().ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidInput, "expected JSON object")
            })?;
            if let Some(approved) = obj.remove("approved") {
                obj.entry("approvalLive").or_insert(approved);
            }
            print_json(&execute_project_protocol(
                DEFAULT_WORKFLOW_CASE,
                Some(&decision),
            )?)
        }
        _ => Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    }
}

fn parse_run_args<'a>(
    rest: &'a [&'a str],
) -> Result<(&'a str, Option<serde_json::Value>), Box<dyn std::error::Error>> {
    let (case_id, read_stdin) = match rest {
        [] => (DEFAULT_WORKFLOW_CASE, false),
        ["--proposal-stdin"] => (DEFAULT_WORKFLOW_CASE, true),
        ["--case", id] => (*id, false),
        ["--case", id, "--proposal-stdin"] | ["--proposal-stdin", "--case", id] => (*id, true),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    Ok((case_id, read_stdin.then(read_json_stdin).transpose()?))
}
