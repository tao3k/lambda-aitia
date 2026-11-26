// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Generic Scheme-driven 5-state Mixed-Initiative inversion-of-control protocol
//! driver over [`crate::HostCapabilityRegistry`].

use crate::{
    AitiaProgram, HostCapabilityRegistry, MAX_REQUEST_BYTES, commit, project, with_linked_program,
};
use aitia_jj::{WorkspaceCut, observe_project_sources};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};

const MAX_PROTOCOL_ROUNDS: usize = 8;

/// Default Scheme workflow case identifier for GitOps commit reconciliation.
pub const DEFAULT_WORKFLOW_CASE: &str = "aitia/case/gitops-commit";

/// Scheme workflow case identifier for Multi-Repository GitOps wave orchestration.
pub const MULTI_REPO_WORKFLOW_CASE: &str = "aitia/case/multi-repo-gitops";

/// Return the JSON envelope listing all registered host capabilities and effect classes.
///
/// # Errors
/// Returns an error if serialization fails.
pub fn host_capabilities_json() -> Result<String, String> {
    serde_json::to_string(&HostCapabilityRegistry::default_linked().descriptors_json())
        .map_err(|error| error.to_string())
}

/// Validate and dispatch a JSON array of Scheme-emitted host capability frames.
///
/// Fails closed on unknown capabilities, effect-class mismatches, or missing fence tokens.
///
/// # Errors
/// Returns an error string on invalid JSON or failed capability validation/execution.
pub fn dispatch_host_frames_json(frames_json: &str) -> Result<String, String> {
    let frames: Vec<Value> =
        serde_json::from_str(frames_json).map_err(|error| error.to_string())?;
    let registry = HostCapabilityRegistry::default_linked();
    let pairs = registry
        .dispatch_protocol_frames(&frames)
        .map_err(|error| error.to_string())?;
    let mut receipts = serde_json::Map::new();
    for (key, payload) in pairs {
        receipts.insert(key, payload);
    }
    serde_json::to_string(&json!({
        "receipts": receipts,
        "actionAuthorized": false,
    }))
    .map_err(|error| error.to_string())
}

/// Parse CLI flags (`--case`, `--workspace`, and one boolean switch) and resolve the effective
/// workflow case identifier plus merged manifest/overlay payload for `aitia flow`.
///
/// # Errors
/// Fails closed on unrecognized flags or unreadable workspace topology files.
pub(crate) fn resolve_flow_cli_invocation<'a>(
    mut rest: &'a [&'a str],
    switch: &str,
    usage: &str,
    mut overlay: Option<Value>,
    read_stdin: impl FnOnce() -> Result<Value, Box<dyn std::error::Error>>,
) -> Result<(&'a str, Option<Value>, bool), Box<dyn std::error::Error>> {
    let (mut case_id, mut workspace, mut switch_set) = (DEFAULT_WORKFLOW_CASE, None, false);
    while !rest.is_empty() {
        match rest {
            ["--case", id, tail @ ..] => {
                case_id = id;
                rest = tail;
            }
            ["--workspace", path, tail @ ..] => {
                workspace = Some(*path);
                rest = tail;
            }
            [flag, tail @ ..] if *flag == switch => {
                switch_set = true;
                rest = tail;
            }
            _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, usage).into()),
        }
    }
    if switch == "--proposal-stdin" && switch_set && overlay.is_none() {
        overlay = Some(read_stdin()?);
    }
    match workspace {
        Some(path) => Ok((
            MULTI_REPO_WORKFLOW_CASE,
            Some(load_workspace_manifest(Path::new(path), overlay.as_ref())?),
            switch_set,
        )),
        None => Ok((case_id, overlay, switch_set)),
    }
}

/// Load a declarative multi-repository workspace topology from a SysML v2 file (`*.sysml`)
/// or JSON manifest, merging any optional runtime overlay (such as per-repo `draft`s or
/// `approvalLive`) by `repoId`.
///
/// # Errors
/// Fails closed if the workspace file cannot be read or parsed, or if a `.sysml` workspace is
/// supplied to a build without the `sysml` feature.
pub fn load_workspace_manifest(
    path: &Path,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    let is_sysml = path
        .extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("sysml"));
    let mut manifest = if is_sysml {
        #[cfg(feature = "sysml")]
        {
            crate::sysml::project_workspace_manifest_from_sysml(path)?
        }
        #[cfg(not(feature = "sysml"))]
        {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "SysML workspace projection requires the `sysml` feature",
            )
            .into());
        }
    } else {
        let mut parsed: Value = serde_json::from_str(&std::fs::read_to_string(path)?)?;
        if let Some(obj) = parsed.as_object_mut() {
            obj.entry("caseId".to_owned())
                .or_insert_with(|| json!(MULTI_REPO_WORKFLOW_CASE));
        }
        parsed
    };
    if let Some(extra) = overlay.and_then(Value::as_object) {
        merge_workspace_overlay(&mut manifest, extra);
    }
    Ok(manifest)
}

fn merge_workspace_overlay(manifest: &mut Value, extra: &serde_json::Map<String, Value>) {
    if let Some(root) = manifest.as_object_mut() {
        for (key, value) in extra {
            if key != "repos" {
                root.insert(key.clone(), value.clone());
            }
        }
    }
    let Some(extra_repos) = extra.get("repos").and_then(Value::as_array) else {
        return;
    };
    let Some(base_repos) = manifest.get_mut("repos").and_then(Value::as_array_mut) else {
        return;
    };
    for patch in extra_repos {
        let Some(patch_obj) = patch.as_object() else {
            continue;
        };
        let Some(rid) = patch_obj.get("repoId").and_then(Value::as_str) else {
            continue;
        };
        if let Some(target) = base_repos
            .iter_mut()
            .filter_map(Value::as_object_mut)
            .find(|repo| repo.get("repoId").and_then(Value::as_str) == Some(rid))
        {
            for (k, v) in patch_obj {
                if k != "repoId" {
                    target.insert(k.clone(), v.clone());
                }
            }
        }
    }
}

/// Execute the Scheme-driven 5-state workflow protocol (planning / read-only probes only).
///
/// # Errors
/// Returns an error if workspace observation, Scheme configuration projection,
/// capability dispatch, or the protocol round budget fails.
pub fn execute_project_protocol(
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    if case_id == MULTI_REPO_WORKFLOW_CASE {
        let req = overlay.ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "Multi-repo protocol requires a JSON manifest on stdin",
            )
        })?;
        return execute_multi_repo_protocol(req, false);
    }
    execute_project_protocol_inner(case_id, overlay, false)
}

/// Execute the Scheme-driven multi-repository GitOps 5-state IoC protocol in one linked session.
///
/// Automatically observes each repository directory's recorded project configuration, dispatches
/// Scheme-emitted `HostRead` frames across all repositories via [`HostCapabilityRegistry`], and
/// only executes `FencedEffect` frames when `execute_fenced` is explicitly `true`.
///
/// # Errors
/// Fails closed if any repository configuration cannot be projected, frame dispatch fails, or
/// the protocol round budget is exceeded.
pub fn execute_multi_repo_protocol(
    request: &Value,
    execute_fenced: bool,
) -> Result<Value, Box<dyn std::error::Error>> {
    let req = request.clone();
    with_linked_program(|program| Ok(drive_multi_repo_protocol(&program, &req, execute_fenced)))?
}

/// Drive the multi-repository 5-state IoC protocol using an already-live [`AitiaProgram`] session.
///
/// # Errors
/// Fails closed if the manifest is malformed, a repository configuration fails projection,
/// capability dispatch fails, evidence verification fails, or the protocol round budget is exceeded.
pub fn drive_multi_repo_protocol(
    program: &AitiaProgram<'_>,
    request: &Value,
    execute_fenced: bool,
) -> Result<Value, Box<dyn std::error::Error>> {
    let mut state = request.clone();
    let root_obj = state.as_object_mut().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Multi-repo request must be a JSON object",
        )
    })?;
    root_obj
        .entry("caseId".to_owned())
        .or_insert_with(|| json!(MULTI_REPO_WORKFLOW_CASE));
    root_obj
        .entry("project".to_owned())
        .or_insert_with(|| json!("multi-repo-workspace"));
    root_obj
        .entry("receipts".to_owned())
        .or_insert_with(|| json!({}));

    let verified_decision = match root_obj.get("humanDecision").cloned() {
        Some(raw) if !raw.is_null() => {
            Some(commit::governance::verify_signed_human_decision(&raw)?)
        }
        _ => None,
    };
    let trust_root = root_obj.get("trustRoot").cloned().filter(|v| !v.is_null());
    if let Some(raw_bundle) = root_obj.get("priorAttestationBundle").cloned()
        && !raw_bundle.is_null()
    {
        let verified_keys = commit::attestation::verify_release_attestation_bundle_with_trust_root(
            &raw_bundle,
            trust_root.as_ref(),
        )?;
        root_obj.insert("attestedVerificationKeys".to_owned(), json!(verified_keys));
    }
    let emit_attestation = root_obj
        .get("emitAttestation")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let attestation_seed = root_obj
        .get("attestationSigningSeed")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let attestation_seeds: Vec<String> = root_obj
        .get("attestationSigningSeeds")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let attestation_epoch = root_obj
        .get("attestationEpoch")
        .and_then(Value::as_u64)
        .unwrap_or(1);
    let checkpoint_path = root_obj
        .get("checkpointPath")
        .and_then(Value::as_str)
        .map(PathBuf::from);
    let (resumed_receipt_count, mut applied_decisions) = match checkpoint_path.as_deref() {
        Some(path) => load_multi_repo_checkpoint(path, root_obj)?,
        None => (0usize, Vec::new()),
    };
    if let Some(decision) = verified_decision.as_ref()
        && let Some(did) = decision["decisionId"].as_str()
    {
        if applied_decisions.iter().any(|existing| existing == did) {
            return Err(io::Error::other(format!(
                "Signed human decision `{did}` was already applied in checkpoint"
            ))
            .into());
        }
        applied_decisions.push(did.to_owned());
    }
    if resumed_receipt_count > 0 {
        mark_applied_repos_for_reconcile(&mut state);
    }

    let archived_reviews = hydrate_multi_repo_entries(
        program,
        state
            .as_object_mut()
            .ok_or_else(|| io::Error::other("multi-repo state must be a JSON object"))?,
        execute_fenced,
    )?;
    let repo_count = state["repos"].as_array().map_or(1, Vec::len);
    let registry = HostCapabilityRegistry::default_linked();
    let max_rounds = MAX_PROTOCOL_ROUNDS.max(repo_count.saturating_mul(4).saturating_add(4));
    for _ in 0..max_rounds {
        let req = serde_json::to_string(&state)?;
        let mut step: Value = serde_json::from_str(&program.workflow_protocol_step(&req)?)?;
        let state_name = step["state"].as_str().map(str::to_owned);
        let should_dispatch = state_name.as_deref() == Some("need-host-frames")
            || (execute_fenced && state_name.as_deref() == Some("need-fenced-frames"));
        if !should_dispatch {
            if execute_fenced {
                attach_multi_repo_evidence_lineages(
                    program,
                    &mut step,
                    &state["receipts"],
                    archived_reviews,
                )?;
            }
            if let Some(decision) = verified_decision {
                step["verifiedHumanDecision"] = decision;
            }
            if emit_attestation && state_name.as_deref() == Some("quiescent") {
                step["releaseAttestation"] = if !attestation_seeds.is_empty() {
                    let seed_refs: Vec<&str> =
                        attestation_seeds.iter().map(String::as_str).collect();
                    commit::attestation::mint_release_attestation_bundle_with_quorum(
                        &step,
                        &seed_refs,
                        attestation_epoch,
                    )?
                } else {
                    commit::attestation::mint_release_attestation_bundle(
                        &step,
                        attestation_seed.as_deref(),
                    )?
                };
            }
            if let Some(path) = checkpoint_path.as_deref() {
                let persisted = persist_multi_repo_checkpoint(
                    path,
                    &state["receipts"],
                    &applied_decisions,
                    state_name.as_deref().unwrap_or("unknown"),
                )?;
                step["checkpoint"] = json!({
                    "schema": "lambda-aitia.multi-repo-checkpoint.v1",
                    "path": path.to_string_lossy(),
                    "resumedReceiptCount": resumed_receipt_count,
                    "persistedReceiptCount": persisted,
                    "appliedDecisions": applied_decisions,
                });
            }
            return Ok(step);
        }
        let raw_frames = step["frames"]
            .as_array()
            .ok_or_else(|| io::Error::other("Scheme protocol step missing frames array"))?;
        let map = state["receipts"]
            .as_object_mut()
            .ok_or_else(|| io::Error::other("protocol receipts must be an object"))?;
        for (key, payload) in registry.dispatch_protocol_frames(raw_frames)? {
            map.insert(key, payload);
        }
        if let Some(path) = checkpoint_path.as_deref() {
            let _ = persist_multi_repo_checkpoint(
                path,
                &state["receipts"],
                &applied_decisions,
                state_name.as_deref().unwrap_or("in-progress"),
            )?;
        }
        mark_applied_repos_for_reconcile(&mut state);
    }
    Err(io::Error::other("multi-repo workflow protocol exceeded host frame round budget").into())
}

fn load_multi_repo_checkpoint(
    path: &Path,
    root_obj: &mut serde_json::Map<String, Value>,
) -> Result<(usize, Vec<String>), Box<dyn std::error::Error>> {
    if let Ok(meta) = std::fs::symlink_metadata(path) {
        if !meta.file_type().is_file() {
            return Err(
                io::Error::other("Multi-repo checkpoint path must be a regular file").into(),
            );
        }
    } else {
        return Ok((0, Vec::new()));
    }
    let parsed: Value = serde_json::from_str(&std::fs::read_to_string(path)?)?;
    if parsed.get("schema").and_then(Value::as_str) != Some("lambda-aitia.multi-repo-checkpoint.v1")
    {
        return Err(io::Error::other("Unsupported multi-repo checkpoint schema").into());
    }
    let mut resumed = 0usize;
    if let (Some(saved), Some(target)) = (
        parsed.get("completedReceipts").and_then(Value::as_object),
        root_obj.get_mut("receipts").and_then(Value::as_object_mut),
    ) {
        for (key, value) in saved {
            if !target.contains_key(key) {
                target.insert(key.clone(), value.clone());
                resumed += 1;
            }
        }
    }
    let decisions = parsed
        .get("appliedDecisions")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    Ok((resumed, decisions))
}

fn persist_multi_repo_checkpoint(
    path: &Path,
    receipts: &Value,
    applied_decisions: &[String],
    last_state: &str,
) -> Result<usize, Box<dyn std::error::Error>> {
    if let Ok(meta) = std::fs::symlink_metadata(path)
        && !meta.file_type().is_file()
    {
        return Err(io::Error::other("Multi-repo checkpoint path must be a regular file").into());
    }
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        std::fs::create_dir_all(parent)?;
    }
    let count = receipts.as_object().map_or(0, serde_json::Map::len);
    let doc = json!({
        "schema": "lambda-aitia.multi-repo-checkpoint.v1",
        "lastState": last_state,
        "completedReceipts": receipts,
        "appliedDecisions": applied_decisions,
        "actionAuthorized": false,
    });
    let tmp = path.with_extension("checkpoint.tmp");
    std::fs::write(&tmp, serde_json::to_vec_pretty(&doc)?)?;
    std::fs::rename(&tmp, path)?;
    Ok(count)
}

fn hydrate_multi_repo_entries(
    program: &AitiaProgram<'_>,
    root_obj: &mut serde_json::Map<String, Value>,
    execute_fenced: bool,
) -> Result<BTreeMap<String, (PathBuf, Value)>, Box<dyn std::error::Error>> {
    let mut archived_reviews = BTreeMap::new();
    let receipts_snapshot = root_obj
        .get("receipts")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let Some(repos) = root_obj.get_mut("repos").and_then(Value::as_array_mut) else {
        return Ok(archived_reviews);
    };
    for repo in repos.iter_mut() {
        let Some(repo_obj) = repo.as_object_mut() else {
            continue;
        };
        let already_applied = repo_obj
            .get("repoId")
            .and_then(Value::as_str)
            .is_some_and(|rid| {
                receipts_snapshot
                    .get(format!("repo:{rid}:gitops.jj.apply-description"))
                    .is_some_and(|v| !v.is_null())
            });
        let needs_hydrate = repo_obj.get("naming").is_none()
            || repo_obj.get("requestedPaths").is_none()
            || (execute_fenced
                && !already_applied
                && repo_obj.get("draft").is_some()
                && repo_obj.get("fencedCommitSpec").is_none());
        if !needs_hydrate {
            continue;
        }
        let Some(dir_str) = repo_obj
            .get("directory")
            .and_then(Value::as_str)
            .map(str::to_owned)
        else {
            continue;
        };
        let dir_path = PathBuf::from(&dir_str);
        if !dir_path.join(".jj").exists() {
            continue;
        }
        let observed = observe_project_sources(&dir_path, usize::try_from(MAX_REQUEST_BYTES)?)?;
        let (_, projection) =
            program.resolve_project_config(&project::recorded_configuration_input(&observed.1)?)?;
        let cfg = project::decode_configuration_projection(&projection)?;
        if let Some(policy) = cfg.commit.as_ref() {
            repo_obj
                .entry("project".to_owned())
                .or_insert_with(|| policy["project"].clone());
            repo_obj
                .entry("profile".to_owned())
                .or_insert_with(|| policy["profile"].clone());
            repo_obj
                .entry("checks".to_owned())
                .or_insert_with(|| policy["checks"].clone());
            repo_obj
                .entry("naming".to_owned())
                .or_insert_with(|| policy["naming"].clone());
            repo_obj
                .entry("modelCheckEnabled".to_owned())
                .or_insert_with(|| json!(cfg.model_check_enabled()));
            if repo_obj.get("requestedPaths").is_none() {
                repo_obj.insert(
                    "requestedPaths".to_owned(),
                    json!(project::review_source_paths(policy)?),
                );
            }
        }
        if execute_fenced
            && !already_applied
            && repo_obj.get("draft").is_some()
            && repo_obj.get("fencedCommitSpec").is_none()
        {
            let overlay_val = Value::Object(repo_obj.clone());
            let (_, fenced_spec, proposal_json, review_report) =
                verify_fenced_commit_draft(program, observed, Some(&overlay_val))?;
            repo_obj.insert("fencedCommitSpec".to_owned(), fenced_spec);
            if repo_obj
                .get("proposals")
                .and_then(Value::as_array)
                .is_none_or(Vec::is_empty)
            {
                repo_obj.insert("proposals".to_owned(), json!([proposal_json]));
            }
            repo_obj.insert("reconcile".to_owned(), json!(false));
            if let Some(rid) = repo_obj.get("repoId").and_then(Value::as_str) {
                archived_reviews.insert(rid.to_owned(), (dir_path, review_report));
            }
        } else if already_applied
            && repo_obj
                .get("proposals")
                .and_then(Value::as_array)
                .is_none_or(Vec::is_empty)
            && let Some(prop) = repo_obj
                .get("draft")
                .and_then(|d| d.get("proposal"))
                .cloned()
        {
            repo_obj.insert("proposals".to_owned(), json!([prop]));
        }
    }
    Ok(archived_reviews)
}

fn mark_applied_repos_for_reconcile(state: &mut Value) {
    let receipts_snapshot = state["receipts"].clone();
    if let Some(repos) = state.get_mut("repos").and_then(Value::as_array_mut) {
        for repo in repos.iter_mut() {
            if let Some(rid) = repo.get("repoId").and_then(Value::as_str) {
                let apply_key = format!("repo:{rid}:gitops.jj.apply-description");
                if receipts_snapshot.get(&apply_key).is_some() {
                    repo["reconcile"] = json!(true);
                }
            }
        }
    }
}

fn attach_multi_repo_evidence_lineages(
    program: &AitiaProgram<'_>,
    step: &mut Value,
    receipts: &Value,
    archived_reviews: BTreeMap<String, (PathBuf, Value)>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut lineages = serde_json::Map::new();
    for (rid, (dir_path, mut archive)) in archived_reviews {
        let apply_key = format!("repo:{rid}:gitops.jj.apply-description");
        let Some(receipt) = receipts.get(&apply_key).filter(|value| !value.is_null()) else {
            continue;
        };
        let revision = receipt["resulting_commit"]
            .as_str()
            .ok_or_else(|| {
                io::Error::other(format!(
                    "Applied commit receipt for repo `{rid}` missing resulting_commit"
                ))
            })?
            .to_owned();
        archive["receipt"] = receipt.clone();
        let evidence = commit::evidence_with_program_in(
            program,
            &dir_path,
            &revision,
            &serde_json::to_string(&archive)?,
            true,
        )?;
        lineages.insert(rid, evidence);
    }
    if !lineages.is_empty() {
        step["repoEvidenceLineages"] = Value::Object(lineages);
    }
    Ok(())
}

/// Execute the Scheme-driven 5-state workflow protocol with explicit opt-in fenced execution.
///
/// Any `FencedEffect` frame is only dispatched after Scheme's own `commit_review_report`
/// verifies the caller-supplied reviewed `draft` against the exact current JJ cut, and
/// every mutation goes strictly through [`HostCapabilityRegistry::dispatch_protocol_frames`].
///
/// # Errors
/// Fails closed if the reviewed draft is missing/invalid, governance requires signed
/// approvals, fenced dispatch fails, or post-apply evidence verification fails.
pub fn execute_project_protocol_fenced(
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    if case_id == MULTI_REPO_WORKFLOW_CASE {
        let req = overlay.ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "Multi-repo fenced protocol requires a JSON manifest on stdin",
            )
        })?;
        return execute_multi_repo_protocol(req, true);
    }
    execute_project_protocol_inner(case_id, overlay, true)
}

/// Drive the Scheme-owned single-repository 5-state IoC protocol against `directory` using an
/// already-live [`AitiaProgram`] session, attaching `evidenceLineage` after fenced quiescence.
///
/// # Errors
/// Fails closed if workspace observation, Scheme configuration projection, reviewed draft
/// verification, capability dispatch, or post-apply evidence verification fails.
pub fn drive_single_repo_protocol(
    program: &AitiaProgram<'_>,
    directory: &Path,
    case_id: &str,
    overlay: Option<&Value>,
    execute_fenced: bool,
) -> Result<Value, Box<dyn std::error::Error>> {
    let observed = observe_project_sources(directory, usize::try_from(MAX_REQUEST_BYTES)?)?;
    let (mut result, archived_review) =
        drive_scheme_protocol_inner(program, observed, case_id, overlay, execute_fenced)?;
    if execute_fenced
        && result["state"].as_str() == Some("quiescent")
        && let (Some(mut archive), Some(receipt)) = (
            archived_review,
            result.get("appliedReceipt").filter(|v| !v.is_null()),
        )
    {
        let revision = receipt["resulting_commit"]
            .as_str()
            .ok_or_else(|| io::Error::other("Applied commit receipt missing resulting_commit"))?
            .to_owned();
        archive["receipt"] = receipt.clone();
        let evidence = commit::evidence_with_program_in(
            program,
            directory,
            &revision,
            &serde_json::to_string(&archive)?,
            true,
        )?;
        result["evidenceLineage"] = evidence;
    }
    Ok(result)
}

fn execute_project_protocol_inner(
    case_id: &str,
    overlay: Option<&Value>,
    execute_fenced: bool,
) -> Result<Value, Box<dyn std::error::Error>> {
    with_linked_program(|program| {
        Ok(drive_single_repo_protocol(
            &program,
            Path::new("."),
            case_id,
            overlay,
            execute_fenced,
        ))
    })?
}

/// Drive the 5-state Scheme protocol loop (read-only probes only) for an already-initialized [`AitiaProgram`].
///
/// # Errors
/// Fails closed if project configuration projection, Scheme step evaluation,
/// host frame dispatch, or the round budget fails.
pub fn drive_scheme_protocol(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&Value>,
) -> Result<Value, Box<dyn std::error::Error>> {
    let (step, _) = drive_scheme_protocol_inner(program, observed, case_id, overlay, false)?;
    Ok(step)
}

fn verify_fenced_commit_draft(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    overlay: Option<&Value>,
) -> Result<(WorkspaceCut, Value, Value, Value), Box<dyn std::error::Error>> {
    let extra = overlay.ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Fenced execution requires a JSON decision payload with a reviewed `draft`",
        )
    })?;
    if extra.get("approvalLive").and_then(Value::as_bool) != Some(true) {
        return Err(io::Error::other("Fenced execution requires `approvalLive: true`").into());
    }
    let raw_draft = extra.get("draft").ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "Fenced execution requires a reviewed `draft` object",
        )
    })?;
    let draft: commit::CommitNarration = serde_json::from_value(raw_draft.clone())?;
    let (cut, review_report, _) =
        commit::commit_review_report(program, observed, Some(&draft), None, false)?;
    if review_report["policy"]["governance"] != "default" {
        return Err(io::Error::other(
            "Signed governance projects require explicit signed approval via `aitia jj commit`",
        )
        .into());
    }
    let description = review_report["review"]["description"]
        .as_str()
        .ok_or_else(|| {
            io::Error::other("Commit draft lacks current admitted support or violates its Contract")
        })?;
    let review_context = review_report["review"]["context"]
        .as_str()
        .ok_or_else(|| io::Error::other("Missing verified commit review context"))?;
    let binding = commit::proposal_binding(&draft.proposal)?;
    let fenced_spec = json!({
        "expectedCommit": cut.commit_id(),
        "expectedOperation": cut.operation_id(),
        "description": description,
        "reviewContext": review_context,
        "proposalBinding": binding,
    });
    let proposal_json = serde_json::to_value(&draft.proposal)?;
    Ok((cut, fenced_spec, proposal_json, review_report))
}

fn drive_scheme_protocol_inner(
    program: &AitiaProgram<'_>,
    observed: (WorkspaceCut, aitia_jj::RecordedProjectSources),
    case_id: &str,
    overlay: Option<&Value>,
    execute_fenced: bool,
) -> Result<(Value, Option<Value>), Box<dyn std::error::Error>> {
    let (_, projection) =
        program.resolve_project_config(&project::recorded_configuration_input(&observed.1)?)?;
    let cfg = project::decode_configuration_projection(&projection)?;
    let (cut, verified_fenced) = if execute_fenced {
        let (cut, fenced_spec, proposal_json, review_report) =
            verify_fenced_commit_draft(program, observed, overlay)?;
        (cut, Some((fenced_spec, proposal_json, review_report)))
    } else {
        (observed.0, None)
    };
    let policy = cfg
        .commit
        .as_ref()
        .ok_or_else(|| io::Error::other("No commit profile"))?;
    let project = policy["project"]
        .as_str()
        .ok_or_else(|| io::Error::other("No commit project"))?;
    let mut state = json!({
        "caseId": case_id,
        "project": project,
        "profile": policy["profile"],
        "checks": policy["checks"],
        "directory": cut.workspace_root().to_string_lossy().into_owned(),
        "requestedPaths": project::review_source_paths(policy)?,
        "modelCheckEnabled": cfg.model_check_enabled(),
        "naming": policy["naming"],
        "receipts": {},
        "proposals": [],
        "observations": [],
        "approvalLive": false,
        "reconcile": true,
    });
    const OVERLAY_FIELDS: &[&str] = &[
        "profile",
        "proposals",
        "proposal",
        "observations",
        "approvalLive",
        "reconcile",
        "includePrObservation",
        "forbiddenScopes",
        "candidateOffers",
        "repairRound",
        "maxRepairRounds",
        "pushTarget",
        "pythonCheck",
        "changeId",
        "designAlternatives",
        "extraObligations",
        "observedObligations",
        "requirementsTraced",
        "verified",
        "retirementClear",
        "releasePublished",
        "refutedDesigns",
        "requiredDesign",
    ];
    if let Some(extra) = overlay {
        for &field in OVERLAY_FIELDS {
            if let Some(value) = extra.get(field) {
                state[field] = value.clone();
            }
        }
    }
    let mut archived_review = None;
    if let Some((fenced_spec, proposal_json, review_report)) = verified_fenced {
        state["fencedCommitSpec"] = fenced_spec;
        if state["proposals"]
            .as_array()
            .is_none_or(|rows| rows.is_empty())
        {
            state["proposals"] = json!([proposal_json]);
        }
        state["reconcile"] = json!(false);
        archived_review = Some(review_report);
    }
    let registry = HostCapabilityRegistry::default_linked();
    for _ in 0..MAX_PROTOCOL_ROUNDS {
        let req = serde_json::to_string(&state)?;
        let step: Value = serde_json::from_str(&program.workflow_protocol_step(&req)?)?;
        let state_name = step["state"].as_str();
        let should_dispatch = state_name == Some("need-host-frames")
            || (execute_fenced && state_name == Some("need-fenced-frames"));
        if !should_dispatch {
            return Ok((step, archived_review));
        }
        let raw_frames = step["frames"]
            .as_array()
            .ok_or_else(|| io::Error::other("Scheme protocol step missing frames array"))?;
        let map = state["receipts"]
            .as_object_mut()
            .ok_or_else(|| io::Error::other("protocol receipts must be an object"))?;
        for (key, payload) in registry.dispatch_protocol_frames(raw_frames)? {
            map.insert(key, payload);
        }
        if state["receipts"]
            .get("gitops.jj.apply-description")
            .is_some()
        {
            state["reconcile"] = json!(true);
        }
    }
    Err(io::Error::other("workflow protocol exceeded host frame round budget").into())
}
