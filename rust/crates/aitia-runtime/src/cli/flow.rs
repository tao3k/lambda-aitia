// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin CLI adapter for `aitia flow ...` subcommands.

use super::{print_json, read_json_stdin, read_request};
use crate::commit::audit::run_verify_attestation_cli;
use crate::protocol::{
    DEFAULT_WORKFLOW_CASE, execute_project_protocol, execute_submit_decision_cli,
    resolve_flow_cli_invocation,
};
use crate::{HostCapabilityRegistry, with_linked_program};
use std::io::{self, Write};

const USAGE: &str = "usage: aitia flow capabilities\n       aitia flow reconcile < request.json\n       aitia flow run [--case <id>] [--workspace <path>] [--proposal-stdin]\n       aitia flow gitops [--proposal-stdin]\n       aitia flow submit-patch < proposal.json\n       aitia flow submit-decision [--case <id>] [--workspace <path>] [--execute-fenced] < decision.json\n       aitia flow verify-attestation [--workspace <path>] < audit-bundle.json";

pub(super) fn run(arguments: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let words: Vec<&str> = arguments.iter().map(String::as_str).collect();
    match words.as_slice() {
        ["--help" | "-h"] => writeln!(io::stdout().lock(), "{USAGE}").map_err(Into::into),
        ["capabilities"] => {
            print_json(&HostCapabilityRegistry::default_linked().descriptors_json())
        }
        ["reconcile"] => {
            let request = read_request()?;
            let response = with_linked_program(|p| p.workflow_reconcile(&request))?;
            writeln!(io::stdout().lock(), "{response}").map_err(Into::into)
        }
        ["run", rest @ ..] => {
            let (case_id, payload, _) = resolve_flow_cli_invocation(
                rest,
                "--proposal-stdin",
                USAGE,
                None,
                read_json_stdin,
            )?;
            print_json(&execute_project_protocol(case_id, payload.as_ref())?)
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
        ["submit-decision", rest @ ..] => print_json(&execute_submit_decision_cli(
            rest,
            USAGE,
            read_json_stdin()?,
            read_json_stdin,
        )?),
        ["verify-attestation", rest @ ..] => print_json(&run_verify_attestation_cli(
            rest,
            &read_json_stdin()?,
            USAGE,
        )?),
        _ => Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    }
}
