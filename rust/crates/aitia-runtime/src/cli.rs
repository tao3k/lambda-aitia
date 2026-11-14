// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use crate::MAX_REQUEST_BYTES;
use crate::cli_commit;
use crate::{AitiaProgram, with_linked_program};
use aitia_jj::{
    DescriptionOrigin, WorkspaceCut, audit_recorded_configuration, git_project_root,
    observe_project_sources, observe_recorded_sources, observe_workspace, recorded_changes,
    recorded_review_bookmarks, recorded_sysml_paths,
};
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(serde::Deserialize)]
pub(super) struct ProjectConfiguration {
    manifest: serde_json::Value,
    checks: Vec<ProjectCheck>,
    replay: Option<ReplayPlan>,
    pub(super) commit: Option<serde_json::Value>,
}

impl ProjectConfiguration {
    pub(super) fn model_check_enabled(&self) -> bool {
        self.checks.contains(&ProjectCheck::SysmlParse)
    }
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
    let usage = "usage: aitia <flow-graph|gitops-evaluate|org-contract-evaluate> < request.json\n       aitia init [directory]\n       aitia jj-observe <directory>\n       aitia project-manifest\n       aitia quint-check <generated-driver.js> <quint> <model.qnt>\n       aitia check\n       aitia jj commit\n       aitia jj commit preview < draft.json\n       aitia jj commit prepare < draft.json\n       aitia jj commit decision < signed.json\n       aitia jj commit apply < approved.json\n       aitia jj commit recover < approval.json\n       aitia jj commit evidence <revision> [--gql] < applied-or-recovered.json\n       aitia jj git push [--remote origin] --bookmark name < approved.json\n       aitia jj git push --recover [--remote origin] --bookmark name < attempt.json";
    if command == Some("jj") {
        let arguments: Vec<_> = args.collect();
        let words: Option<Vec<_>> = arguments.iter().map(|word| word.to_str()).collect();
        let words = words.ok_or_else(|| io::Error::other("JJ arguments must be UTF-8"))?;
        if let ["commit", operation @ ..] = words.as_slice() {
            return run_jj_commit(operation);
        }
        let (recover, route) = match words.as_slice() {
            ["git", "push", "--recover", route @ ..] => (true, route),
            ["git", "push", route @ ..] => (false, route),
            _ => {
                return Err(io::Error::other(
                    "usage: aitia jj <commit|git push>; see aitia --help",
                )
                .into());
            }
        };
        let (remote, bookmark) = match route {
            ["--bookmark", bookmark] => ("origin", *bookmark),
            ["--remote", remote, "--bookmark", bookmark]
            | ["--bookmark", bookmark, "--remote", remote] => (*remote, *bookmark),
            _ => {
                return Err(io::Error::other(
                    "usage: aitia jj <commit|git push>; see aitia --help",
                )
                .into());
            }
        };
        let input = read_request()?;
        let receipt = if recover {
            cli_commit::recover_push(&input, remote, bookmark)?
        } else {
            cli_commit::push(&input, remote, bookmark)?
        };
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

fn run_jj_commit(operation: &[&str]) -> Result<(), Box<dyn std::error::Error>> {
    const USAGE: &str = "usage: aitia jj commit [preview|prepare|apply|decision|recover]\n       Without an operation, print the read-only commit context.\n       aitia jj commit preview --applied < reviewed-attempt.json\n       aitia jj commit evidence <revision> [--gql] < applied-or-recovered.json";
    if let ["evidence", revision, options @ ..] = operation {
        let query = match options {
            [] => false,
            ["--gql"] => true,
            _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
        };
        let input = read_request()?;
        let result = cli_commit::evidence(revision, &input, query)?;
        writeln!(io::stdout().lock(), "{result}")?;
        return Ok(());
    }
    let command = match operation {
        [] => None,
        ["--help" | "-h"] => {
            writeln!(io::stdout().lock(), "{USAGE}")?;
            return Ok(());
        }
        [verb @ ("preview" | "prepare" | "apply" | "decision" | "recover")] => Some(*verb),
        ["preview", "--applied"] => Some("preview"),
        _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, USAGE).into()),
    };
    if matches!(command, Some("decision" | "recover")) {
        let input = read_request()?;
        let approval = if command == Some("recover") {
            match serde_json::from_str(&input)? {
                cli_commit::CommitRecovery::Attempt { attempt } => {
                    let result = cli_commit::recover_attempt(Path::new("."), &attempt)?;
                    writeln!(io::stdout().lock(), "{result}")?;
                    return Ok(());
                }
                cli_commit::CommitRecovery::Approval { approval } => Some(approval),
            }
        } else {
            None
        };
        let result = with_linked_program(|program| {
            Ok((|| {
                let (cut, config) = resolve_recorded_project(&program, Path::new("."))?;
                let project = config
                    .commit
                    .as_ref()
                    .and_then(|policy| policy["project"].as_str())
                    .ok_or_else(|| io::Error::other("No recorded commit project"))?;
                if let Some(approval) = approval.as_deref() {
                    cli_commit::recover(&program, &cut, project, approval)
                } else {
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
                }
            })())
        })??;
        writeln!(io::stdout().lock(), "{result}")?;
        return Ok(());
    }
    let preview_applied = operation == ["preview", "--applied"];
    let (draft, attempt) = if command == Some("apply") || preview_applied {
        (
            None,
            Some(serde_json::from_str::<cli_commit::Apply>(&read_request()?)?),
        )
    } else if command.is_some() {
        (
            Some(serde_json::from_str::<CommitNarration>(&read_request()?)?),
            None,
        )
    } else {
        (None, None)
    };
    let draft = attempt
        .as_ref()
        .map(|input| &input.draft)
        .or(draft.as_ref());
    let reviewed = attempt.as_ref().filter(|_| preview_applied);
    let observed = observe_project_sources(Path::new("."), MAX_REQUEST_BYTES as usize)?;
    let origin = reviewed
        .map(|input| aitia_jj::observe_description_origin(&observed.0, &input.attempt))
        .transpose()?;
    if let Some(input) = attempt.as_ref().filter(|_| command == Some("apply")) {
        input.attempt.require_expected_cut(&observed.0)?;
    }
    let result = with_linked_program(|program| {
        Ok((|| {
            let (cut, mut result, _) = nasa_commit_report(
                &program,
                observed,
                draft,
                origin.as_ref(),
                command == Some("preview"),
            )?;
            if let Some(input) = reviewed {
                result["review"]["reviewContextCurrent"] = serde_json::json!(
                    result["review"]["context"].as_str() == Some(input.draft.context.as_str())
                );
                result["review"]["matchesWrittenDescription"] = serde_json::json!(
                    result["review"]["previewDescription"].as_str()
                        == Some(input.attempt.description.as_str())
                );
            }
            let required_text = if command == Some("preview") {
                "previewDescription"
            } else {
                "description"
            };
            if draft.is_some() && result["review"][required_text].is_null() {
                writeln!(io::stdout().lock(), "{result}")?;
                return Err(io::Error::other(
                    "Commit draft lacks current admitted support or violates its Contract",
                )
                .into());
            }
            match command {
                Some("prepare") => cli_commit::prepare(&program, &cut, &mut result)?,
                None => cli_commit::attach_revision(&cut, &mut result)?,
                _ => {}
            }
            if let Some(input) = attempt.as_ref().filter(|_| command == Some("apply")) {
                result["receipt"] = cli_commit::apply(&program, &cut, &result, input)?;
            }
            Ok::<_, Box<dyn std::error::Error>>(result)
        })())
    })??;
    writeln!(io::stdout().lock(), "{result}")?;
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
    proposal: CommitProposal,
    narration: Narration,
    org: String,
    pub(super) context: String,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
struct Narration {
    change: String,
    evidence: Vec<NarrationRow>,
    open: Vec<NarrationRow>,
}

#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
struct NarrationRow {
    obligation: String,
    text: String,
}

/// Agent intent is a proposal; source documents and changed paths are Host facts.
#[derive(serde::Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct CommitProposal {
    identity: String,
    reference: String,
    r#type: String,
    scope: String,
    summary: String,
    rationale: String,
    language: String,
    #[serde(rename = "languageSource")]
    language_source: String,
}

fn compiled_policy_context() -> &'static str {
    // The bridge's archive is identified during the build. The manifest alone
    // names paths and can stay unchanged when their Scheme contents change.
    // Runtime reads neither build files nor a Scheme checkout.
    env!("AITIA_PROGRAM_CONTEXT")
}

fn observe_commit_provider(
    cut: &WorkspaceCut,
) -> Result<
    (
        Vec<aitia_jj::RecordedReviewBookmark>,
        crate::review_provider::ReviewObservation,
    ),
    aitia_jj::JjObservationError,
> {
    let bookmarks = recorded_review_bookmarks(cut)?;
    let observation = crate::review_provider::observe(&bookmarks, cut.commit_id());
    Ok((bookmarks, observation))
}

pub(super) fn nasa_commit_report(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    draft: Option<&CommitNarration>,
    origin: Option<&DescriptionOrigin>,
    preview: bool,
) -> Result<
    (
        WorkspaceCut,
        serde_json::Value,
        Vec<aitia_jj::RecordedReviewBookmark>,
    ),
    Box<dyn std::error::Error>,
> {
    let (cut, project_sources) = observed;
    if origin.is_some_and(|observed| observed.current() != &cut) {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    let source = recorded_configuration_input(&project_sources)?;
    let (review_configuration, projection) = program.resolve_project_config(&source)?;
    let configuration = decode_configuration_projection(&projection)?;
    // The JJ owner proves identical tree, parents and change identity. Read
    // those immutable inputs at the current anchor, but assess the original
    // review cut instead of silently replacing the user's reviewed context.
    let review_cut = origin.map_or(&cut, DescriptionOrigin::original);
    let policy = configuration
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile in the recorded project"))?;
    let changes = recorded_changes(&cut)?;
    let model_paths = if configuration.model_check_enabled() {
        affected_sysml_paths(&changes)
    } else {
        Vec::new()
    };
    let (model, (bookmarks, provider)) = if model_paths.is_empty() {
        (None, observe_commit_provider(&cut)?)
    } else {
        // Both observations read the recorded cut. Scheme stays on its owner
        // thread and receives the facts only after both host calls finish.
        std::thread::scope(|scope| {
            let provider = scope.spawn(|| observe_commit_provider(&cut));
            let model = observe_commit_sysml(&cut, &model_paths);
            let provider = provider
                .join()
                .map_err(|_| io::Error::other("PR observation worker panicked"))??;
            Ok::<_, Box<dyn std::error::Error>>((Some(model), provider))
        })?
    };
    let requested_paths = review_source_paths(policy)?;
    let mut sources = Vec::new();
    let mut source_errors = Vec::new();
    for (path, result) in
        observe_recorded_sources(&cut, &requested_paths, usize::try_from(MAX_REQUEST_BYTES)?)?
    {
        match result {
            Ok(text) => sources.push(serde_json::json!({"path": path, "text": text})),
            Err(error) => {
                source_errors.push(serde_json::json!({"path":path,"error":error.to_string()}))
            }
        }
    }
    let cut_value = cli_commit::review_cut_value(review_cut);
    let input_digest = cli_commit::review_input_digest(&cut_value, &project_sources, &changes)?;
    let selected_checks = commit_checks(policy)?;
    let mut execution = Vec::new();
    let mut reports = Vec::new();
    for check in selected_checks {
        if changes.is_empty() {
            break;
        }
        let report = match check["method"].as_str() {
            Some("jj.recorded-change") => serde_json::to_value(&changes)?,
            Some("jj.configuration-audit") => match origin {
                Some(observed) => serde_json::to_value(observed.configuration())?,
                None => serde_json::to_value(audit_recorded_configuration(&cut)?)?,
            },
            _ => continue,
        };
        let report_digest = crate::source_tree::sha256(&serde_json::to_vec(&report)?);
        let identity = cli_commit::check_execution_identity(check, &input_digest, &report_digest)?;
        let mut observation = serde_json::json!({
            "requirement": check["requirement"],
            "method": check["method"],
            "identity": identity,
            "inputDigest": input_digest,
            "reportDigest": report_digest,
        });
        execution.push(observation.clone());
        observation["report"] = report;
        reports.push(observation);
    }
    // Git configuration can change without advancing the JJ operation.
    if recorded_review_bookmarks(&cut)? != bookmarks {
        return Err(io::Error::other("JJ review bookmark configuration changed").into());
    }
    let mut request = serde_json::json!({
        "cut": cut_value,
        "checks": execution,
        "ruleContext": compiled_policy_context(),
        "routeContext": crate::source_tree::sha256(&serde_json::to_vec(
            &bookmarks.iter().map(|bookmark| (bookmark, &bookmark.route_identity)).collect::<Vec<_>>(),
        )?),
        "preview": preview,
        "sources": sources,
        "paths": changes.iter().map(|change| change.path.as_str()).collect::<Vec<_>>(),
        "providerBookmarks": bookmarks,
        "providerReview": provider,
        "modelCheck": model,
    });
    if let Some(draft) = draft {
        request["draft"] = serde_json::to_value(draft)?;
    }
    let mut payload_size = RequestSize(0);
    serde_json::to_writer(&mut payload_size, &request)?;
    // The rooted configuration and the remaining request share the existing
    // budget, including the former projectSources member's framing.
    if payload_size.0 + source.len() + "\"projectSources\":,".len() > MAX_REQUEST_BYTES as usize {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "AITIA input exceeds 4 MiB").into());
    }
    let review = program.nasa_draft(&review_configuration, &request)?;
    if observe_workspace(cut.workspace_root())? != cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    let result = serde_json::json!({
            "cut": cut_value,
            "policy": policy,
            "changes": changes,
            // Preserve the host-produced observations as well as their bindings.
            // A receipt identity alone cannot recover the original check report.
            "executions": reports,
            "sourceErrors": source_errors,
            "languageSources": sources,
            "proposal": draft.map(|narration| &narration.proposal),
            "recordedReviewBookmarks": request["providerBookmarks"],
            "providerReview": request["providerReview"],
            "modelCheck": request["modelCheck"],
            "review": review,
    });
    Ok((cut, result, bookmarks))
}

// Keep the request limit in serialized bytes without allocating a wire string.
struct RequestSize(usize);

impl Write for RequestSize {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0 += bytes.len();
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

#[cfg(feature = "sysml")]
fn check_sysml(cut: &WorkspaceCut) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let sources = recorded_sysml_paths(cut)?;
    if sources.is_empty() {
        return Err(
            io::Error::new(io::ErrorKind::InvalidInput, "no recorded SysML documents").into(),
        );
    }
    parse_sysml_sources(cut, &sources)
}

fn observe_commit_sysml(cut: &WorkspaceCut, paths: &[String]) -> serde_json::Value {
    match parse_sysml_sources(cut, paths) {
        Ok(report) => serde_json::json!({"paths": paths, "status": "passed", "report": report}),
        Err(error) => {
            serde_json::json!({"paths": paths, "status": "open", "detail": error.to_string()})
        }
    }
}

pub(super) fn affected_sysml_paths(changes: &[aitia_jj::RecordedPathChange]) -> Vec<String> {
    changes
        .iter()
        .filter(|change| change.path.ends_with(".sysml"))
        .map(|change| change.path.clone())
        .collect()
}

#[cfg(feature = "sysml")]
fn parse_sysml_sources(
    cut: &WorkspaceCut,
    sources: &[String],
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    crate::sysml::parse_model_report(|| crate::sysml::recorded_documents(cut, sources))
}

#[cfg(not(feature = "sysml"))]
fn check_sysml(_cut: &WorkspaceCut) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    parse_sysml_sources(_cut, &[])
}

#[cfg(not(feature = "sysml"))]
fn parse_sysml_sources(
    _cut: &WorkspaceCut,
    _sources: &[String],
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
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
    let (cut, sources) = observe_project_sources(directory, MAX_REQUEST_BYTES as usize)?;
    let config = with_linked_program(|program| Ok(validate_project_manifest(&program, &sources)))??;
    if observe_workspace(cut.workspace_root())? != cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation.into());
    }
    Ok((cut, config))
}

fn resolve_recorded_project(
    program: &AitiaProgram<'_>,
    directory: &Path,
) -> Result<(WorkspaceCut, ProjectConfiguration), Box<dyn std::error::Error>> {
    let (cut, source) = observe_project_sources(directory, MAX_REQUEST_BYTES as usize)?;
    Ok((cut, validate_project_manifest(program, &source)?))
}

pub(super) fn validate_project_manifest(
    program: &AitiaProgram<'_>,
    sources: &aitia_jj::RecordedProjectSources,
) -> Result<ProjectConfiguration, Box<dyn std::error::Error>> {
    decode_configuration_projection(
        &program.project_config_validate(&recorded_configuration_input(sources)?)?,
    )
}

fn recorded_configuration_input(
    sources: &aitia_jj::RecordedProjectSources,
) -> Result<String, Box<dyn std::error::Error>> {
    let source = serde_json::to_string(sources)?;
    if source.len() > MAX_REQUEST_BYTES as usize {
        return Err(
            io::Error::new(io::ErrorKind::InvalidData, "AITIA request exceeds 4 MiB").into(),
        );
    }
    Ok(source)
}

fn decode_configuration_projection(
    effective: &str,
) -> Result<ProjectConfiguration, Box<dyn std::error::Error>> {
    if effective == "false" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "AITIA project manifest fails its envelope Contract",
        )
        .into());
    }
    Ok(serde_json::from_str(effective)?)
}

pub(super) fn review_source_paths(policy: &serde_json::Value) -> Result<Vec<&str>, io::Error> {
    let references = policy["naming"]["references"]
        .as_array()
        .ok_or_else(|| io::Error::other("Invalid Scheme engineering reference projection"))?;
    let mut observed_paths = std::collections::BTreeSet::new();
    let language_sources = policy["naming"]["languageSources"]
        .as_array()
        .ok_or_else(|| io::Error::other("Invalid Scheme project language sources"))?;
    let paths = references
        .iter()
        .map(|reference| &reference["source"])
        .chain(language_sources.iter());
    let mut requested_paths = Vec::new();
    for source_path in paths {
        let path = source_path
            .as_str()
            .ok_or_else(|| io::Error::other("Invalid Scheme source path"))?;
        // JJ admits only regular files in this recorded tree. No workspace or
        // Agent-supplied document can replace a missing reference observation.
        if observed_paths.insert(path) {
            requested_paths.push(path);
        }
    }
    Ok(requested_paths)
}

pub(super) fn commit_checks(policy: &serde_json::Value) -> Result<&[serde_json::Value], io::Error> {
    policy["checks"]
        .as_array()
        .map(Vec::as_slice)
        .ok_or_else(|| io::Error::other("Invalid Scheme commit policy projection"))
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
