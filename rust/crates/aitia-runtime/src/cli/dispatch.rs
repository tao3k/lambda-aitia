// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Top-level CLI argument dispatch and bounded stdin/stdout helpers.

use super::{flow, jj};
use crate::{AitiaProgram, MAX_REQUEST_BYTES, checks, project, with_linked_program};
use std::io::{self, Read, Write};
use std::path::Path;

const USAGE: &str = "usage: aitia <flow-graph|gitops-evaluate|org-contract-evaluate> < request.json\n       aitia flow reconcile < request.json\n       aitia flow gitops [--proposal-stdin]\n       aitia init [directory]\n       aitia jj-observe <directory>\n       aitia project-manifest\n       aitia quint-check [--json] <generated-driver.js> <quint> <model.qnt>\n       aitia check\n       aitia jj commit\n       aitia jj commit preview < draft.json\n       aitia jj commit prepare < draft.json\n       aitia jj commit decision < signed.json\n       aitia jj commit apply < approved.json\n       aitia jj commit recover < approval.json\n       aitia jj commit evidence <revision> [--gql] < applied-or-recovered.json\n       aitia jj git push [--remote origin] --bookmark name < approved.json\n       aitia jj git push --recover [--remote origin] --bookmark name < attempt.json";

/// Run the process CLI and return its application-level diagnostic.
pub fn run_cli() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args_os().skip(1);
    let command = args.next();
    let command = command.as_deref().and_then(std::ffi::OsStr::to_str);
    match command {
        Some("flow") => flow::run(&utf8_args(args, "flow")?),
        Some("jj") => jj::run(&utf8_args(args, "JJ")?),
        Some("serve-marlin-grpc") => crate::commit::grpc_gateway::run_serve_marlin_grpc_cli(
            &utf8_args(args, "serve-marlin-grpc")?,
        ),
        Some("sidecar") => {
            crate::commit::sidecar_cli::run_sidecar_cli(&utf8_args(args, "sidecar")?)
        }
        Some("review") => crate::commit::sidecar_cli::run_review_cli(&utf8_args(args, "review")?),
        Some("check") => {
            ensure_no_extra_args(args)?;
            let (receipt, matched) =
                with_linked_program(|program| Ok(checks::check_recorded_project(&program)))??;
            print_json(&receipt)?;
            if !matched {
                return Err(
                    io::Error::other("Assurance replay differs from the declared cases").into(),
                );
            }
            Ok(())
        }
        Some("project-manifest") => {
            ensure_no_extra_args(args)?;
            print_json(&project::project_manifest_receipt(Path::new("."))?)
        }
        Some("quint-check") => run_quint_cli(args.collect()),
        Some("init") => {
            let directory = args.next();
            ensure_no_extra_args(args)?;
            let path =
                project::init_project(directory.as_deref().map_or(Path::new("."), Path::new))?;
            writeln!(io::stdout().lock(), "{path}").map_err(Into::into)
        }
        Some("jj-observe") => {
            let (Some(workspace), None) = (args.next(), args.next()) else {
                return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into());
            };
            let cut = aitia_jj::observe_workspace(Path::new(&workspace))?;
            let mut stdout = io::stdout().lock();
            serde_json::to_writer(&mut stdout, &cut)?;
            writeln!(stdout).map_err(Into::into)
        }
        _ => run_program_op(command, args.next().is_some()),
    }
}

fn run_quint_cli(rest: Vec<std::ffi::OsString>) -> Result<(), Box<dyn std::error::Error>> {
    let (json_output, positional) = match rest.as_slice() {
        [flag, driver, quint, model] if flag == "--json" => (true, (driver, quint, model)),
        [driver, quint, model] => (false, (driver, quint, model)),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    let outcome = checks::run_quint_check(positional.0, positional.1, positional.2)?;
    if json_output {
        print_json(&outcome.observation)?;
    }
    if !outcome.source_unchanged {
        return Err(io::Error::other("Quint inputs changed during verification").into());
    }
    if !outcome.status.success() {
        return Err(io::Error::other(format!("Quint execution failed: {}", outcome.status)).into());
    }
    Ok(())
}

fn run_program_op(
    command: Option<&str>,
    has_extra: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if has_extra {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into());
    }
    let operation: fn(&AitiaProgram<'_>, &str) -> _ = match command {
        Some("--help" | "-h") => {
            return writeln!(io::stdout().lock(), "{USAGE}").map_err(Into::into);
        }
        Some("flow-graph") => |program, request| program.flow_graph(request),
        Some("gitops-evaluate") => |program, request| program.gitops_evaluate(request),
        Some("org-contract-evaluate") => |program, request| program.org_contract_evaluate(request),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    let request = read_request()?;
    let response = with_linked_program(|program| operation(&program, &request))?;
    writeln!(io::stdout().lock(), "{response}").map_err(Into::into)
}

fn utf8_args(
    args: impl Iterator<Item = std::ffi::OsString>,
    label: &str,
) -> Result<Vec<String>, io::Error> {
    args.map(|word| {
        word.into_string()
            .map_err(|_| io::Error::other(format!("{label} arguments must be UTF-8")))
    })
    .collect()
}

fn ensure_no_extra_args(
    mut args: impl Iterator<Item = std::ffi::OsString>,
) -> Result<(), io::Error> {
    if args.next().is_some() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE));
    }
    Ok(())
}

pub(super) fn read_request() -> Result<String, io::Error> {
    let mut request = String::new();
    let bytes = io::stdin()
        .lock()
        .take(MAX_REQUEST_BYTES + 1)
        .read_to_string(&mut request)?;
    if bytes as u64 > MAX_REQUEST_BYTES {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AITIA request exceeds 4 MiB",
        ));
    }
    Ok(request)
}

pub(super) fn read_json_stdin() -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    Ok(serde_json::from_str(&read_request()?)?)
}

pub(super) fn print_json(value: &serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
    writeln!(io::stdout().lock(), "{}", serde_json::to_string(value)?).map_err(Into::into)
}
