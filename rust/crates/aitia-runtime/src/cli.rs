// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use crate::{AitiaProgram, with_linked_program};
use aitia_jj::{
    WorkspaceCut, git_project_root, observe_project_manifest, observe_workspace,
    recorded_sysml_paths,
};
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(serde::Deserialize)]
struct ProjectConfiguration {
    manifest: serde_json::Value,
    checks: Vec<ProjectCheck>,
}

#[derive(serde::Deserialize, PartialEq, Eq)]
enum ProjectCheck {
    #[serde(rename = "sysml.parse")]
    SysmlParse,
}

const MAX_REQUEST_BYTES: u64 = 4 * 1024 * 1024;

/// Run the process CLI and return its application-level diagnostic.
pub fn run_cli() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args_os().skip(1);
    let command = args.next();
    let command = command.as_deref().and_then(std::ffi::OsStr::to_str);
    let usage = "usage: aitia <flow-graph|gitops-evaluate|org-contract-evaluate> < request.json\n       aitia init [directory]\n       aitia jj-observe <directory>\n       aitia project-manifest\n       aitia quint-check <generated-driver.js> <quint> <model.qnt>\n       aitia check";
    if command == Some("check") {
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        let (cut, configuration) = recorded_project(Path::new("."))?;
        let sysml = if configuration.checks.contains(&ProjectCheck::SysmlParse) {
            check_sysml(&cut)?
        } else {
            serde_json::Value::Null
        };
        let receipt = serde_json::json!({"cut": cut, "checks": {"sysml": sysml}});
        writeln!(io::stdout().lock(), "{receipt}")?;
        return Ok(());
    }
    if command == Some("project-manifest") {
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        let (cut, configuration) = recorded_project(Path::new("."))?;
        let sysml = if configuration.checks.contains(&ProjectCheck::SysmlParse) {
            recorded_sysml_paths(&cut)?
        } else {
            Vec::new()
        };
        let receipt = serde_json::json!({
            "cut": cut, "manifest": configuration.manifest, "inputs": {"sysml": sysml}
        });
        writeln!(io::stdout().lock(), "{receipt}")?;
        return Ok(());
    }
    if command == Some("quint-check") {
        let (Some(driver), Some(quint), Some(model), None) =
            (args.next(), args.next(), args.next(), args.next())
        else {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        };
        let status = Command::new("timeout")
            .args(["--signal=TERM", "--kill-after=3s", "60s", "node"])
            .arg(fs::canonicalize(driver)?)
            .arg(fs::canonicalize(quint)?)
            .arg(fs::canonicalize(model)?)
            .stdin(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(io::Error::other(format!("Quint execution failed: {status}")).into());
        }
        return Ok(());
    }
    if command == Some("init") {
        let directory = args.next();
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        return init_project(directory.as_deref().map_or(Path::new("."), Path::new));
    }
    if command == Some("jj-observe") {
        let (Some(workspace), None) = (args.next(), args.next()) else {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        };
        let cut = observe_workspace(Path::new(&workspace))?;
        let mut stdout = io::stdout().lock();
        serde_json::to_writer(&mut stdout, &cut)?;
        writeln!(stdout)?;
        return Ok(());
    }
    let operation: fn(&AitiaProgram<'_>, &str) -> _ = match (command, args.next()) {
        (Some("--help" | "-h"), None) => {
            writeln!(io::stdout().lock(), "{usage}")?;
            return Ok(());
        }
        (Some("flow-graph"), None) => |program, request| program.flow_graph(request),
        (Some("gitops-evaluate"), None) => |program, request| program.gitops_evaluate(request),
        (Some("org-contract-evaluate"), None) => {
            |program, request| program.org_contract_evaluate(request)
        }
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into()),
    };

    // The existing transport admits at most 4 MiB. Read one extra byte to
    // distinguish an oversized request from one that exactly fills the limit.
    let mut request = String::new();
    let bytes = io::stdin()
        .lock()
        .take(MAX_REQUEST_BYTES + 1)
        .read_to_string(&mut request)?;
    if bytes as u64 > MAX_REQUEST_BYTES {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "AITIA request exceeds 4 MiB").into(),
        );
    }
    let response = with_linked_program(|program| operation(&program, &request))?;
    writeln!(io::stdout().lock(), "{response}")?;
    Ok(())
}

#[cfg(feature = "sysml")]
fn check_sysml(cut: &WorkspaceCut) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let sources = recorded_sysml_paths(cut)?;
    if sources.is_empty() {
        return Err(
            io::Error::new(io::ErrorKind::InvalidInput, "no recorded SysML documents").into(),
        );
    }
    let connection = opensysml::Connection::connect()?;
    let model = crate::parse_recorded_sysml(&connection, cut, &sources)?;
    Ok(serde_json::json!({"documents": model.documents(), "modelHash": model.hash()}))
}

#[cfg(not(feature = "sysml"))]
fn check_sysml(_cut: &WorkspaceCut) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    Err(io::Error::other(
        "SysML parsing is enabled in project configuration but unavailable in this build",
    )
    .into())
}

fn recorded_project(
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    let (cut, source) = observe_project_manifest(directory)?;
    if source.len() > MAX_REQUEST_BYTES as usize {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "AITIA request exceeds 4 MiB").into(),
        );
    }
    let effective = with_linked_program(|program| program.project_config_validate(&source))?;
    if effective == "false" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AITIA project manifest fails its envelope Contract",
        )
        .into());
    }
    let configuration = serde_json::from_str(&effective)?;
    Ok((cut, configuration))
}

fn init_project(directory: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let root = git_project_root(directory)?;
    let mut config = root;
    for component in [".agents", "aita"] {
        config.push(component);
        match fs::create_dir(&config) {
            Ok(()) => {}
            Err(error)
                if error.kind() == io::ErrorKind::AlreadyExists
                    && fs::symlink_metadata(&config)?.file_type().is_dir() => {}
            Err(error) => return Err(error.into()),
        }
    }
    let manifest = config.join("project.json");
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&manifest)
    {
        Ok(mut file) => file.write_all(b"{\"schemaVersion\":1}\n")?,
        Err(error)
            if error.kind() == io::ErrorKind::AlreadyExists
                && fs::symlink_metadata(&manifest)?.file_type().is_file() => {}
        Err(error) => return Err(error.into()),
    }
    writeln!(io::stdout().lock(), ".agents/aita/project.json")?;
    Ok(())
}
