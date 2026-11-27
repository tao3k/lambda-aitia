// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin CLI workflow driver for `aitia sidecar <capture|assess|verify-formal|receipt|commit>`
//! (RFC 0025), providing Environment 1 (`native-ai-environment`) with a single-binary,
//! zero-`GERBIL_LOADPATH` interface for pure Git repositories and Git worktrees (no `.jj`
//! and no `.agents/aita/`) over the exact same Scheme/POO `gerbil-ascent` + DE formal
//! verification + NASA/DSSE core used by RFC 0024's Marlin gRPC gateway.

use super::{Result, defense_audit, err, formal_evidence, sidecar};
use crate::MAX_REQUEST_BYTES;
use serde_json::{Value, json};
use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const SIDECAR_USAGE: &str = "usage: aitia sidecar capture --repo <dir> [--base <ref>] [--profile <file>] [--checks <file>]\n       aitia sidecar audit-diff --repo <dir> [--staged] [--base <ref>] [--rule-pack <file>]... [--funflow-receipts <file>] [--format json|agent-feedback|sarif]\n       aitia sidecar assess < assessment-request.json\n       aitia sidecar verify-formal --context-digest <sha256:...> < formal-evidence.json\n       aitia sidecar receipt [--repo <dir>] [--vault-dir <dir>] < receipt-spec.json\n       aitia sidecar commit --repo <dir> --vault-dir <dir> < receipt-spec.json";

fn read_bounded_stdin() -> Result<String> {
    let mut text = String::new();
    let bytes = io::stdin()
        .lock()
        .take(MAX_REQUEST_BYTES + 1)
        .read_to_string(&mut text)?;
    if bytes as u64 > MAX_REQUEST_BYTES {
        return Err(err("AITIA sidecar CLI request exceeds 4 MiB"));
    }
    Ok(text)
}

fn canonicalize_or_parent(path: &Path) -> Result<PathBuf> {
    if path.exists() {
        return Ok(fs::canonicalize(path)?);
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let canon_parent = canonicalize_or_parent(parent)?;
    match path.file_name() {
        Some(name) => Ok(canon_parent.join(name)),
        None => Ok(canon_parent),
    }
}

fn ensure_vault_outside_repo(vault_dir: &Path, repo_dir: &Path) -> Result<()> {
    let canon_repo = fs::canonicalize(repo_dir)?;
    let canon_vault = canonicalize_or_parent(vault_dir)?;
    if canon_vault == canon_repo || canon_vault.starts_with(&canon_repo) {
        return Err(err(
            "Vault-outside-repo violation: sidecar vault must live outside external upstream repo",
        ));
    }
    Ok(())
}

fn run_git_cmd(repo_dir: &Path, args: &[&str], stdin_data: Option<&str>) -> Result<String> {
    let mut cmd = Command::new("git");
    cmd.args(args).current_dir(repo_dir);
    if stdin_data.is_some() {
        cmd.stdin(Stdio::piped());
    }
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd
        .spawn()
        .map_err(|e| err(format!("Failed to execute git {:?}: {e}", args)))?;
    if let Some(input) = stdin_data
        && let Some(mut stdin) = child.stdin.take()
    {
        stdin.write_all(input.as_bytes())?;
    }
    let output = child.wait_with_output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(err(format!("git {:?} failed: {}", args, stderr.trim())));
    }
    String::from_utf8(output.stdout).map_err(|_| err("git output contained non-UTF-8 bytes"))
}

fn archive_bundle_to_vault(
    vault_dir: &Path,
    bundle: &Value,
    prefix: &str,
) -> Result<(PathBuf, PathBuf)> {
    fs::create_dir_all(vault_dir)?;
    let bundle_file = vault_dir.join(format!("{prefix}.nasa-sidecar.json"));
    let org_file = vault_dir.join(format!("{prefix}.nasa-audit.org"));
    fs::write(
        &bundle_file,
        format!("{}\n", serde_json::to_string_pretty(bundle)?),
    )?;
    if let Some(org_text) = bundle["nasaOrgReport"].as_str() {
        fs::write(&org_file, org_text)?;
    }
    Ok((bundle_file, org_file))
}

fn parse_repo_and_vault(args: &[String]) -> Result<(Option<String>, Option<String>)> {
    let mut repo_dir: Option<String> = None;
    let mut vault_dir: Option<String> = None;
    let mut i = 0usize;
    while i < args.len() {
        match args[i].as_str() {
            "--repo" => {
                i += 1;
                repo_dir = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--vault-dir" => {
                i += 1;
                vault_dir = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            _ => return Err(err(SIDECAR_USAGE)),
        }
        i += 1;
    }
    Ok((repo_dir, vault_dir))
}

fn run_capture(args: &[String]) -> Result<String> {
    let mut repo_dir: Option<String> = None;
    let mut base_ref = "HEAD".to_owned();
    let mut profile_path: Option<String> = None;
    let mut checks_path: Option<String> = None;
    let mut i = 0usize;
    while i < args.len() {
        match args[i].as_str() {
            "--repo" => {
                i += 1;
                repo_dir = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--base" => {
                i += 1;
                base_ref = args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned();
            }
            "--profile" => {
                i += 1;
                profile_path = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--checks" => {
                i += 1;
                checks_path = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            _ => return Err(err(SIDECAR_USAGE)),
        }
        i += 1;
    }
    let repo = repo_dir.ok_or_else(|| err("sidecar capture requires --repo <dir>"))?;
    let profile_json = match profile_path {
        Some(path) => fs::read_to_string(&path)?,
        None => defense_audit::default_sidecar_profile_json(Path::new(&repo)),
    };
    let checks_json = match checks_path {
        Some(path) => fs::read_to_string(&path)?,
        None => "[]".to_owned(),
    };
    sidecar::capture_detached_audit_context_json(
        Path::new(&repo),
        &base_ref,
        &profile_json,
        &checks_json,
    )
}

fn run_audit_diff(args: &[String]) -> Result<(String, bool)> {
    let mut repo_dir: Option<String> = None;
    let mut base_ref = "HEAD".to_owned();
    let mut staged_only = false;
    let mut format = "json".to_owned();
    let mut rule_pack_paths: Vec<String> = Vec::new();
    let mut funflow_receipts_path: Option<String> = None;
    let mut i = 0usize;
    while i < args.len() {
        match args[i].as_str() {
            "--repo" => {
                i += 1;
                repo_dir = Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--base" => {
                i += 1;
                base_ref = args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned();
            }
            "--staged" => staged_only = true,
            "--rule-pack" => {
                i += 1;
                rule_pack_paths.push(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--funflow-receipts" => {
                i += 1;
                funflow_receipts_path =
                    Some(args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned());
            }
            "--format" => {
                i += 1;
                format = args.get(i).ok_or_else(|| err(SIDECAR_USAGE))?.to_owned();
            }
            _ => return Err(err(SIDECAR_USAGE)),
        }
        i += 1;
    }
    let repo = repo_dir.ok_or_else(|| err("sidecar audit-diff requires --repo <dir>"))?;
    let mut rule_packs = Vec::new();
    for path in &rule_pack_paths {
        let val: Value = serde_json::from_str(&fs::read_to_string(path)?)?;
        if let Some(arr) = val.as_array() {
            rule_packs.extend(arr.iter().cloned());
        } else {
            rule_packs.push(val);
        }
    }
    let funflow_receipts: Vec<Value> = match funflow_receipts_path {
        Some(path) => {
            let val: Value = serde_json::from_str(&fs::read_to_string(&path)?)?;
            match val {
                Value::Array(arr) => arr,
                other => vec![other],
            }
        }
        None => Vec::new(),
    };
    let report = defense_audit::audit_git_repo_defense_with_packs(
        Path::new(&repo),
        &base_ref,
        staged_only,
        &rule_packs,
        &funflow_receipts,
        None,
    )?;
    let passed = report["passed"].as_bool().unwrap_or(false);
    let rendered = match format.as_str() {
        "json" => serde_json::to_string(&report)?,
        "agent-feedback" => serde_json::to_string(&report["repairPacket"])?,
        "sarif" => serde_json::to_string(&report["sarif"])?,
        _ => {
            return Err(err(
                "Invalid --format (expected json, agent-feedback, or sarif)",
            ));
        }
    };
    Ok((rendered, passed))
}

fn run_verify_formal(args: &[String]) -> Result<String> {
    let expected_ctx = match args {
        [flag, digest] if flag == "--context-digest" => digest.as_str(),
        _ => return Err(err(SIDECAR_USAGE)),
    };
    let payload = read_bounded_stdin()?;
    formal_evidence::verify_de_formal_evidence_json(&payload, expected_ctx)
}

fn run_receipt(args: &[String]) -> Result<String> {
    let (repo_dir, vault_dir) = parse_repo_and_vault(args)?;
    let spec_json = read_bounded_stdin()?;
    if let (Some(vault), Some(repo)) = (vault_dir.as_deref(), repo_dir.as_deref()) {
        ensure_vault_outside_repo(Path::new(vault), Path::new(repo))?;
    }
    let raw_bundle = sidecar::build_nasa_sidecar_receipt_json(&spec_json)?;
    let Some(vault) = vault_dir else {
        return Ok(raw_bundle);
    };
    let mut bundle: Value = serde_json::from_str(&raw_bundle)?;
    let digest = bundle["receiptDigest"]
        .as_str()
        .ok_or_else(|| err("Sidecar receipt missing receiptDigest"))?;
    let short_id: String = digest
        .strip_prefix("sha256:")
        .unwrap_or(digest)
        .chars()
        .take(16)
        .collect();
    let (bundle_file, org_file) = archive_bundle_to_vault(Path::new(&vault), &bundle, &short_id)?;
    if let Some(obj) = bundle.as_object_mut() {
        obj.insert(
            "vaultArtifacts".to_owned(),
            json!({
                "bundlePath": bundle_file.to_string_lossy(),
                "orgReportPath": org_file.to_string_lossy(),
                "vaultOutsideRepoVerified": repo_dir.is_some(),
                "actionAuthorized": false,
            }),
        );
    }
    Ok(serde_json::to_string(&bundle)?)
}

fn run_sidecar_commit(args: &[String]) -> Result<String> {
    let (repo_opt, vault_opt) = parse_repo_and_vault(args)?;
    let repo_str = repo_opt.ok_or_else(|| err("sidecar commit requires --repo <dir>"))?;
    let vault_str = vault_opt.ok_or_else(|| err("sidecar commit requires --vault-dir <dir>"))?;
    let repo_path = Path::new(&repo_str);
    let vault_path = Path::new(&vault_str);
    ensure_vault_outside_repo(vault_path, repo_path)?;

    let spec_json = read_bounded_stdin()?;
    let spec: Value = serde_json::from_str(&spec_json)?;
    let expected_base = spec["context"]["baseCommit"]
        .as_str()
        .ok_or_else(|| err("sidecar commit spec missing context.baseCommit"))?;
    let live_head = run_git_cmd(repo_path, &["rev-parse", "HEAD"], None)?
        .trim()
        .to_owned();
    if live_head != expected_base {
        return Err(err(format!(
            "Stale external repo HEAD `{live_head}` does not match audited baseCommit `{expected_base}`"
        )));
    }

    let staged_out = run_git_cmd(repo_path, &["diff", "--cached", "--name-only"], None)?;
    let staged_files: Vec<&str> = staged_out
        .lines()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    if staged_files.is_empty() {
        return Err(err(
            "sidecar commit requires pre-staged changes in the external Git index (stage explicit paths first)",
        ));
    }
    let forbidden: Vec<String> = spec["profile"]
        .get("forbiddenUpstreamPrefixes")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .filter(|v: &Vec<String>| !v.is_empty())
        .unwrap_or_else(|| vec![".agents/aita/".to_owned(), ".aitia/".to_owned()]);
    for path in &staged_files {
        for prefix in &forbidden {
            if path.starts_with(prefix) {
                return Err(err(format!(
                    "Upstream repository pollution blocked in staged index: `{path}` matches `{prefix}`"
                )));
            }
        }
    }
    let staged_defense = defense_audit::audit_git_repo_defense(repo_path, "HEAD", true)?;
    if staged_defense["passed"].as_bool() != Some(true) {
        return Err(err(format!(
            "DE G2 staged diff anti-defensive-programming gate refused commit ({} findings): {}",
            staged_defense["totalFindings"].as_u64().unwrap_or(0),
            staged_defense["repairPacket"]
        )));
    }

    let raw_bundle = sidecar::build_nasa_sidecar_receipt_json(&spec_json)?;
    let mut bundle: Value = serde_json::from_str(&raw_bundle)?;
    let commit_msg = bundle["upstreamCommitMessage"]
        .as_str()
        .ok_or_else(|| err("Sidecar receipt missing upstreamCommitMessage"))?;
    let _ = run_git_cmd(repo_path, &["commit", "-F", "-"], Some(commit_msg))?;
    let new_sha = run_git_cmd(repo_path, &["rev-parse", "HEAD"], None)?
        .trim()
        .to_owned();
    let short_sha: String = new_sha.chars().take(12).collect();
    let (bundle_file, org_file) = archive_bundle_to_vault(vault_path, &bundle, &short_sha)?;
    if let Some(obj) = bundle.as_object_mut() {
        obj.insert("upstreamCommitSha".to_owned(), json!(new_sha));
        obj.insert(
            "vaultArtifacts".to_owned(),
            json!({
                "bundlePath": bundle_file.to_string_lossy(),
                "orgReportPath": org_file.to_string_lossy(),
                "vaultOutsideRepoVerified": true,
                "actionAuthorized": false,
            }),
        );
    }
    Ok(serde_json::to_string(&bundle)?)
}

/// Dispatch `aitia sidecar <capture|assess|verify-formal|receipt|commit>` (RFC 0025).
///
/// # Errors
/// Fails closed on invalid arguments, upstream repo pollution, vault-inside-repo
/// violation, unstaged/stale external Git index, vacuous formal evidence, or Scheme ASCENT errors.
pub(crate) fn run_sidecar_cli(args: &[String]) -> Result<()> {
    let output = match args.first().map(String::as_str) {
        None | Some("--help" | "-h") => {
            writeln!(io::stdout().lock(), "{SIDECAR_USAGE}")?;
            return Ok(());
        }
        Some("capture") => run_capture(&args[1..])?,
        Some("audit-diff") => {
            let (out, passed) = run_audit_diff(&args[1..])?;
            writeln!(io::stdout().lock(), "{out}")?;
            if !passed {
                return Err(err(
                    "DE G2 anti-defensive-programming diff audit refused patch (see repairPacket)",
                ));
            }
            return Ok(());
        }
        Some("assess") => {
            if args.len() != 1 {
                return Err(err(SIDECAR_USAGE));
            }
            sidecar::assess_sidecar_audit_ascent_json(&read_bounded_stdin()?)?
        }
        Some("verify-formal") => run_verify_formal(&args[1..])?,
        Some("receipt") => run_receipt(&args[1..])?,
        Some("commit") => run_sidecar_commit(&args[1..])?,
        Some(_) => return Err(err(SIDECAR_USAGE)),
    };
    writeln!(io::stdout().lock(), "{output}")?;
    Ok(())
}

fn parse_review_text_input(raw: &str) -> Result<Value> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(json!({}));
    }
    if trimmed.starts_with('(') {
        return Ok(json!({ "planSexp": trimmed }));
    }
    serde_json::from_str(trimmed).map_err(|e| {
        err(format!(
            "Invalid JSON or `(aitia-review-plan ...)` S-expression for `aitia review` (pass empty input to discover templates): {e}"
        ))
    })
}

/// Zero-flag progressive FunFlow Choice single entrypoint for LLMs:
///   `aitia review`                 -> discover current epistemic frontier + DSL grammar & S-expr template
///   `aitia review <repo-dir>`      -> discover current epistemic frontier in `<repo-dir>`
///   `aitia review <plan.sexp|json>` -> execute & validate an LLM-authored declarative plan file
///   `aitia review < plan.sexp|json` -> execute & validate piped S-expr or JSON plan
///
/// Never requires memorizing CLI flags; returns self-healing templates on invalid choices.
pub(crate) fn run_review_cli(args: &[String]) -> Result<()> {
    if args.first().map(String::as_str) == Some("--tool-schema") {
        let schema = defense_audit::get_review_tool_schema_json(None)?;
        writeln!(
            io::stdout().lock(),
            "{}",
            serde_json::to_string_pretty(&schema)?
        )?;
        return Ok(());
    }
    let mut req: Value = if !io::stdin().is_terminal() {
        parse_review_text_input(&read_bounded_stdin()?)?
    } else {
        json!({})
    };
    if let Some(first) = args.first()
        && first != "--help"
        && first != "-h"
        && !first.starts_with('-')
    {
        let p = Path::new(first);
        if p.is_file() {
            let file_text = fs::read_to_string(p)?;
            req = parse_review_text_input(&file_text)?;
        } else if let Some(obj) = req.as_object_mut() {
            obj.entry("repo".to_owned()).or_insert_with(|| json!(first));
        }
    }
    let out = defense_audit::run_review_flow_step_json(&req, None)?;
    writeln!(
        io::stdout().lock(),
        "{}",
        serde_json::to_string_pretty(&out)?
    )?;
    Ok(())
}
