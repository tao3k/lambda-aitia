// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use crate::cli_commit;
use crate::linked::MAX_REQUEST_BYTES;
use crate::{AitiaProgram, with_linked_program};
use aitia_jj::{
    WorkspaceCut, audit_recorded_configuration, git_project_root, observe_project_manifest,
    observe_workspace, read_recorded_file, recorded_changes, recorded_sysml_paths,
};
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(serde::Deserialize)]
struct ProjectConfiguration {
    manifest: serde_json::Value,
    checks: Vec<ProjectCheck>,
    replay: Option<ReplayPlan>,
    commit: Option<serde_json::Value>,
}

#[derive(serde::Deserialize)]
struct ReplayPlan {
    project: String,
    profile: String,
    paths: Vec<String>,
    cases: Vec<ReplayCase>,
}

#[derive(serde::Deserialize)]
struct ReplayCase {
    obligation: String,
    selector: String,
    expected: String,
}

#[derive(serde::Deserialize, PartialEq, Eq)]
enum ProjectCheck {
    #[serde(rename = "sysml.parse")]
    SysmlParse,
    #[serde(rename = "assurance.replay")]
    AssuranceReplay,
}

/// Run the process CLI and return its application-level diagnostic.
pub fn run_cli() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args_os().skip(1);
    let command = args.next();
    let command = command.as_deref().and_then(std::ffi::OsStr::to_str);
    let usage = "usage: aitia <flow-graph|gitops-evaluate|org-contract-evaluate> < request.json\n       aitia init [directory]\n       aitia jj-observe <directory>\n       aitia project-manifest\n       aitia quint-check <generated-driver.js> <quint> <model.qnt>\n       aitia check\n       aitia commit-context\n       aitia commit-description < draft.json\n       aitia commit-prepare < draft.json\n       aitia commit-decision < signed.json\n       aitia commit-apply < approved.json\n       aitia commit-recover < approval.json\n       aitia jj git push [--remote origin] --bookmark name < approved.json";
    if command == Some("jj") {
        let arguments: Vec<_> = args.collect();
        let words: Option<Vec<_>> = arguments.iter().map(|word| word.to_str()).collect();
        let words = words.ok_or_else(|| io::Error::other("JJ arguments must be UTF-8"))?;
        let (remote, bookmark) = match words.as_slice() {
            ["git", "push", "--bookmark", bookmark] => ("origin", *bookmark),
            ["git", "push", "--remote", remote, "--bookmark", bookmark]
            | ["git", "push", "--bookmark", bookmark, "--remote", remote] => (*remote, *bookmark),
            _ => {
                return Err(io::Error::other(
                    "usage: aitia jj git push [--remote origin] --bookmark name < approved.json",
                )
                .into());
            }
        };
        let input = read_request()?;
        let receipt = with_linked_program(|program| {
            Ok(cli_commit::push(&program, &input, remote, bookmark))
        })??;
        writeln!(io::stdout().lock(), "{receipt}")?;
        return Ok(());
    }
    if command == Some("check") {
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        let (receipt, matched) =
            with_linked_program(|program| Ok(check_recorded_project(&program)))??;
        writeln!(io::stdout().lock(), "{receipt}")?;
        if !matched {
            return Err(
                io::Error::other("Assurance replay differs from the declared cases").into(),
            );
        }
        return Ok(());
    }
    if matches!(command, Some("commit-decision" | "commit-recover")) {
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        let input = read_request()?;
        let result = with_linked_program(|program| {
            Ok((|| {
                let (cut, config) = resolve_recorded_project(&program, Path::new("."))?;
                let project = config
                    .commit
                    .as_ref()
                    .and_then(|policy| policy["project"].as_str())
                    .ok_or_else(|| io::Error::other("No recorded commit project"))?;
                if command == Some("commit-decision") {
                    if config
                        .commit
                        .as_ref()
                        .is_none_or(|policy| policy["governance"] != "signed")
                    {
                        return Err(io::Error::other(
                            "This project does not use signed commit approvals",
                        )
                        .into());
                    }
                    cli_commit::record(&program, &cut, project, &input)
                } else {
                    cli_commit::recover(&program, &cut, project, &input)
                }
            })())
        })??;
        writeln!(io::stdout().lock(), "{result}")?;
        return Ok(());
    }
    if matches!(
        command,
        Some("commit-context" | "commit-description" | "commit-prepare" | "commit-apply")
    ) {
        if args.next().is_some() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into());
        }
        let mut apply = None;
        let draft = match command {
            Some("commit-context") => None,
            Some("commit-apply") => {
                apply = Some(serde_json::from_str::<cli_commit::Apply>(&read_request()?)?);
                None
            }
            _ => Some(serde_json::from_str::<CommitNarration>(&read_request()?)?),
        };
        let draft = apply.as_ref().map(|input| &input.draft).or(draft.as_ref());
        let result = with_linked_program(|program| {
            Ok((|| {
                let (cut, mut result) = nasa_commit_report(&program, draft)?;
                if draft.is_some() && result["review"]["description"].is_null() {
                    writeln!(io::stdout().lock(), "{result}")?;
                    return Err(io::Error::other(
                        "Commit draft lacks current admitted support or violates its Contract",
                    )
                    .into());
                }
                match command {
                    Some("commit-prepare") => cli_commit::prepare(&program, &cut, &mut result)?,
                    Some("commit-context") => cli_commit::attach_revision(&cut, &mut result)?,
                    _ => {}
                }
                if let Some(input) = &apply {
                    result["receipt"] = cli_commit::apply(&program, &cut, &result, input)?;
                }
                Ok::<_, Box<dyn std::error::Error>>(result)
            })())
        })??;
        writeln!(io::stdout().lock(), "{result}")?;
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

    let request = read_request()?;
    let response = with_linked_program(|program| operation(&program, &request))?;
    writeln!(io::stdout().lock(), "{response}")?;
    Ok(())
}

fn read_request() -> Result<String, io::Error> {
    // The existing transport admits at most 4 MiB. Read one extra byte to
    // distinguish an oversized request from one that exactly fills the limit.
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

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct CommitNarration {
    title: String,
    body: String,
    org: String,
    pub(super) context: String,
}

pub(super) fn nasa_commit_report(
    program: &AitiaProgram<'_>,
    draft: Option<&CommitNarration>,
) -> Result<(WorkspaceCut, serde_json::Value), Box<dyn std::error::Error>> {
    let (cut, configuration) = resolve_recorded_project(program, Path::new("."))?;
    let policy = configuration
        .commit
        .ok_or_else(|| io::Error::other("No commit profile in the recorded project"))?;
    let manifest = read_recorded_file(&cut, ".agents/aita/project.json")?;
    let changes = recorded_changes(&cut)?;
    let cut_value = serde_json::json!({
        "workspace": cut.workspace_name(),
        "change": cut.change_id(),
        "operation": cut.operation_id(),
        "commit": cut.commit_id(),
        "tree": cut.tree_id(),
        "parents": cut.parent_ids(),
    });
    let input_digest = crate::source_tree::sha256(&serde_json::to_vec(&serde_json::json!([
        cut_value, manifest, changes
    ]))?);
    let selected_checks = policy["checks"]
        .as_array()
        .ok_or_else(|| io::Error::other("Invalid Scheme commit policy projection"))?;
    let mut execution = Vec::new();
    for check in selected_checks {
        if changes.is_empty() {
            break;
        }
        let report_digest = match check["method"].as_str() {
            Some("jj.recorded-change") => {
                crate::source_tree::sha256(&serde_json::to_vec(&changes)?)
            }
            Some("jj.configuration-audit") => {
                let observed = audit_recorded_configuration(&cut)?;
                crate::source_tree::sha256(&serde_json::to_vec(&observed)?)
            }
            _ => continue,
        };
        let identity = crate::source_tree::sha256(&serde_json::to_vec(&serde_json::json!([
            check,
            input_digest,
            report_digest,
        ]))?);
        execution.push(serde_json::json!({
            "requirement": check["requirement"],
            "method": check["method"],
            "identity": identity,
            "inputDigest": input_digest,
            "reportDigest": report_digest,
        }));
    }
    let mut request = serde_json::json!({
        "manifest": manifest,
        "cut": cut_value,
        "checks": execution,
    });
    if let Some(draft) = draft {
        request["draft"] = serde_json::to_value(draft)?;
    }
    let review: serde_json::Value =
        serde_json::from_str(&program.nasa_draft(&request.to_string())?)?;
    if observe_workspace(cut.workspace_root())? != cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    Ok((
        cut,
        serde_json::json!({
            "cut": cut_value,
            "policy": policy,
            "changes": changes,
            "review": review,
        }),
    ))
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

fn check_recorded_project(
    program: &AitiaProgram<'_>,
) -> Result<(serde_json::Value, bool), Box<dyn std::error::Error>> {
    let (cut, configuration) = resolve_recorded_project(program, Path::new("."))?;
    let sysml = if configuration.checks.contains(&ProjectCheck::SysmlParse) {
        check_sysml(&cut)?
    } else {
        serde_json::Value::Null
    };
    let mut checks = serde_json::json!({ "sysml": sysml });
    let mut matched = true;
    if configuration
        .checks
        .contains(&ProjectCheck::AssuranceReplay)
    {
        let plan = configuration
            .replay
            .ok_or_else(|| io::Error::other("Missing replay plan"))?;
        let (report, replay_matched) = check_assurance_replay(program, &cut, &plan)?;
        checks["assurance"] = report;
        matched = replay_matched;
    }
    Ok((serde_json::json!({ "cut": cut, "checks": checks }), matched))
}

fn check_assurance_replay(
    program: &AitiaProgram<'_>,
    cut: &WorkspaceCut,
    plan: &ReplayPlan,
) -> Result<(serde_json::Value, bool), Box<dyn std::error::Error>> {
    let interpreter = std::env::var_os("AITIA_PYTEST_PYTHON").ok_or_else(|| {
        io::Error::other("Set AITIA_PYTEST_PYTHON to an absolute Python interpreter with pytest")
    })?;
    let paths: Vec<_> = plan.paths.iter().map(String::as_str).collect();
    let mut results = Vec::with_capacity(plan.cases.len());
    let mut matched = true;
    for case in &plan.cases {
        let run = crate::run_recorded_pytest(
            Path::new(&interpreter),
            &plan.project,
            cut.clone(),
            &paths,
            &[&case.selector],
        )?;
        let assessment = program.assess_pytest_replay(
            crate::ReplayAssessmentScope {
                project: &plan.project,
                workspace: cut.workspace_root(),
                obligation: &case.obligation,
                selector: &case.selector,
                deployment_profile: Some(&plan.profile),
            },
            None,
            &run,
        )?;
        let field = match case.expected.as_str() {
            "passed" => "supported",
            "failed" => "contradicted",
            _ => return Err(io::Error::other("Unknown expected replay outcome").into()),
        };
        let case_matched = assessment.as_ref().is_some_and(|value| {
            value["revision"] == cut.commit_id()
                && value[field].as_array().is_some_and(|rows| {
                    rows.iter().any(|row| {
                        row.get(1).and_then(serde_json::Value::as_str) == Some(&case.obligation)
                    })
                })
        });
        matched &= case_matched;
        results.push(serde_json::json!({
            "obligation": case.obligation,
            "expected": case.expected,
            "matched": case_matched,
            "assessment": assessment,
        }));
    }
    Ok((
        serde_json::json!({"profile": plan.profile, "cases": results}),
        matched,
    ))
}

fn recorded_project(
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    with_linked_program(|program| Ok(resolve_recorded_project(&program, directory)))?
}

fn resolve_recorded_project(
    program: &AitiaProgram<'_>,
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    let (cut, source) = observe_project_manifest(directory)?;
    if source.len() > MAX_REQUEST_BYTES as usize {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "AITIA request exceeds 4 MiB").into(),
        );
    }
    let effective = program.project_config_validate(&source)?;
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
