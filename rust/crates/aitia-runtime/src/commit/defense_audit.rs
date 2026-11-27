// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Native, zero-dependency 7-language AI Anti-Defensive-Programming Diff-Delta Auditor
//! (aligned with `@deterministic-engineering/agent-defense-audit` C1/C2/G1/G2/G5 contracts).
//!
//! Audits BOTH unstaged (`git diff`) and staged (`git diff --cached`) unified diffs across
//! Rust, Go, C, C++, TypeScript/JavaScript, Python, and Gerbil Scheme, emitting structured
//! `AgentRepairPacket` directives, SARIF 2.1.0 reports, and FunFlow/ASCENT observability
//! summaries. Never grants execution authority (`actionAuthorized: false`).

use super::{Result, err};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

const REPAIR_PACKET_SCHEMA: &str = "lambda-aitia.de-g2-repair-packet.v1";

struct C2Spec {
    anti_pattern_id: &'static str,
    c2_replacement: &'static str,
    anti_evasion_warning: &'static str,
}

struct G2Finding {
    id: String,
    file: String,
    language: &'static str,
    surface: &'static str,
    line: usize,
    hallucination_class: &'static str,
    rule: &'static str,
    detail: String,
    excerpt: String,
}

fn detect_language(path: &str) -> Option<&'static str> {
    let lower = path.to_ascii_lowercase();
    if lower.ends_with(".rs") {
        Some("rust")
    } else if lower.ends_with(".go") {
        Some("go")
    } else if lower.ends_with(".ts")
        || lower.ends_with(".tsx")
        || lower.ends_with(".js")
        || lower.ends_with(".jsx")
    {
        Some("typescript")
    } else if lower.ends_with(".py") {
        Some("python")
    } else if lower.ends_with(".ss") || lower.ends_with(".scm") {
        Some("scheme")
    } else if lower.ends_with(".c") || lower.ends_with(".h") {
        Some("c")
    } else if lower.ends_with(".cc") || lower.ends_with(".cpp") || lower.ends_with(".hpp") {
        Some("cpp")
    } else {
        None
    }
}

fn c2_spec_for(hclass: &str, rule: &str) -> C2Spec {
    if rule.starts_with("diff-deleted-") {
        return C2Spec {
            anti_pattern_id: "g2.silent-obligation-deletion",
            c2_replacement: "Preserve existing assertions, Band-5 floors, and @countermodel witnesses; removing an obligation requires an admitted replacement witness in the same change.",
            anti_evasion_warning: "Do NOT evade by wrapping assertions inside conditional guards, test.skip, #[ignore], or silent deletion.",
        };
    }
    match hclass {
        "silent-fallback" => C2Spec {
            anti_pattern_id: "c1.silent-fallback-on-defect",
            c2_replacement: "Return a typed epistemic boundary error separating SetupDefect, PendingMethod, Conflict, Refuted, and Proven instead of swallowing failures into default/empty values.",
            anti_evasion_warning: "Do NOT evade by adding eprintln!/console.error/logging before returning null/0/[]/Ok(())/default.",
        },
        "floor-weakening" => C2Spec {
            anti_pattern_id: "c1.global-purge-on-negative-change",
            c2_replacement: "Restore monotonic Band-5 verification floors and unconditional assertions; fix the underlying defect rather than suppressing or skipping checks.",
            anti_evasion_warning: "Do NOT evade via @ts-ignore, #[ignore], #define NDEBUG, pytest.mark.skip, or test.skip.",
        },
        "redundant-defensive-glue" => C2Spec {
            anti_pattern_id: "c1.redundant-internal-revalidation",
            c2_replacement: "Parse once into sealed types at the single trust boundary; remove no-op catch-rethrow glue or prove necessity with DE F3 Quint guard-probe.",
            anti_evasion_warning: "Do NOT rename or reorder redundant catch-rethrow blocks without an executable counterexample.",
        },
        _ => C2Spec {
            anti_pattern_id: "c1.unknown-as-violation",
            c2_replacement: "Execute the real verification oracle or emit explicit PendingMethod; never return TODO/stub-backed positive verdicts.",
            anti_evasion_warning: "Do NOT evade by removing the TODO comment while keeping an ungrounded constant true/verified:true stub.",
        },
    }
}

fn is_assertion_or_obligation_line(trimmed: &str) -> bool {
    let patterns = [
        "assert!(",
        "assert_eq!(",
        "assert_ne!(",
        "assert ",
        "self.assert",
        "expect(",
        "check-equal?",
        "(check ",
        "@countermodel",
        "requireCountermodels",
    ];
    patterns.iter().any(|p| trimmed.contains(p))
}

fn inspect_added_line(
    file: &str,
    lang: &'static str,
    surface: &'static str,
    line_no: usize,
    raw: &str,
    out: &mut Vec<G2Finding>,
) {
    let trimmed = raw.trim();
    if trimmed.is_empty()
        || trimmed.starts_with("//")
        || trimmed.starts_with('#') && !trimmed.starts_with("#[") && !trimmed.starts_with("#define")
        || trimmed.starts_with(";;")
    {
        return;
    }
    let lower = trimmed.to_ascii_lowercase();
    let mut push = |hclass: &'static str, rule: &'static str, detail: String| {
        let id = format!("G2-{:03}", out.len() + 1);
        out.push(G2Finding {
            id,
            file: file.to_owned(),
            language: lang,
            surface,
            line: line_no,
            hallucination_class: hclass,
            rule,
            detail,
            excerpt: trimmed.chars().take(140).collect(),
        });
    };

    // 1. Silent fallback patterns
    let silent_rule: Option<(&'static str, &'static str)> = match lang {
        "rust"
            if trimmed.contains(".unwrap_or_default()")
                || trimmed.contains(".ok().unwrap_or(")
                || trimmed.contains("Err(_) => Ok(())")
                || trimmed.contains("Err(_) => return Ok(())")
                || trimmed.contains("Err(_) => {}") =>
        {
            Some((
                "rust-silent-fallback",
                "Rust error/option defect silently collapsed into default or Ok(())",
            ))
        }
        "python"
            if (trimmed.starts_with("except:") || trimmed.starts_with("except "))
                && (trimmed.ends_with(": pass")
                    || trimmed.contains("return None")
                    || trimmed.contains("return False")
                    || trimmed.contains("return 0")
                    || trimmed.contains("return []")) =>
        {
            Some((
                "python-silent-except-fallback",
                "Python exception swallowed via pass or default return value",
            ))
        }
        "typescript"
            if (trimmed.contains("catch")
                && (trimmed.contains("{}") || trimmed.contains("{ }")))
                || (trimmed.contains("catch")
                    && (trimmed.contains("return null")
                        || trimmed.contains("return undefined")
                        || trimmed.contains("return []")
                        || trimmed.contains("return 0"))) =>
        {
            Some((
                "ts-silent-catch-fallback",
                "TypeScript/JS catch block silently swallows defect into empty/default value",
            ))
        }
        "go" if trimmed.contains("if err != nil")
            && (trimmed.contains("return nil")
                || trimmed.contains("{}")
                || trimmed.contains("{ }")) =>
        {
            Some((
                "go-silent-err-swallow",
                "Go error branch swallows non-nil error without propagation",
            ))
        }
        "scheme"
            if trimmed.contains("(with-catch (lambda (_)")
                && (trimmed.contains("#f)") || trimmed.contains("'())")) =>
        {
            Some((
                "scheme-silent-catch-fallback",
                "Gerbil Scheme with-catch silently collapses error into #f or empty list",
            ))
        }
        "c" | "cpp" if trimmed.contains("catch (...)") && trimmed.contains("{}") => Some((
            "cpp-silent-catch-all",
            "C++ catch(...) block silently discards exception",
        )),
        _ => None,
    };
    if let Some((rule, detail)) = silent_rule {
        push("silent-fallback", rule, detail.to_owned());
    }

    // 2. Floor weakening / suppression escapes
    if trimmed.contains("@ts-ignore")
        || trimmed.contains("@ts-expect-error")
        || trimmed.contains("#[ignore]")
        || trimmed.contains("#define NDEBUG")
        || trimmed.contains("test.skip(")
        || trimmed.contains("it.skip(")
        || trimmed.contains("pytest.mark.skip")
        || trimmed.contains("unittest.skip")
        || trimmed.contains("allowGlobalPurge: true")
        || trimmed.contains("allowGlobalPurge = true")
        || trimmed.contains("requireCountermodels: false")
        || trimmed.contains("requireCountermodels = false")
    {
        push(
            "floor-weakening",
            "verification-floor-suppression",
            "Verification check or Band-5 floor suppressed/weakened in added diff line".to_owned(),
        );
    }

    // 3. Redundant defensive glue (no-op catch-rethrow / identity error wrap)
    if (trimmed.contains("catch") && trimmed.contains("throw "))
        || (trimmed.contains("except ") && trimmed.ends_with(": raise"))
        || trimmed.contains("Err(e) => return Err(e)")
        || trimmed.contains("Err(e) => Err(e)")
    {
        push(
            "redundant-defensive-glue",
            "noop-catch-rethrow",
            "No-op error catch-and-rethrow glue adds defensive noise without boundary refinement"
                .to_owned(),
        );
    }

    // 4. Fabricated evidence (TODO/stub/placeholder paired with positive verdict)
    let has_stub = lower.contains("todo")
        || lower.contains("fixme")
        || lower.contains("stub")
        || lower.contains("placeholder");
    let has_positive = lower.contains("verified: true")
        || lower.contains("verified = true")
        || lower.contains("passed: true")
        || lower.contains("passed = true")
        || lower.contains("admissible: true")
        || lower.contains("return true")
        || lower.contains("ok(true)");
    if has_stub && has_positive {
        push(
            "fabricated-evidence",
            "stub-positive-verdict",
            "TODO/stub-backed hardcoded positive verdict fabricates verification evidence"
                .to_owned(),
        );
    }
}

fn parse_hunk_new_start(header: &str) -> usize {
    header
        .split('+')
        .nth(1)
        .and_then(|s| s.split([',', ' ']).next())
        .and_then(|n| n.parse::<usize>().ok())
        .unwrap_or(1)
}

fn flush_hunk_assertion_balance(
    file: &str,
    lang: &'static str,
    surface: &'static str,
    deleted: &[(usize, String)],
    added_count: usize,
    out: &mut Vec<G2Finding>,
) {
    if deleted.len() > added_count {
        for (line_no, excerpt) in deleted.iter().take(deleted.len() - added_count) {
            let id = format!("G2-{:03}", out.len() + 1);
            out.push(G2Finding {
                id,
                file: file.to_owned(),
                language: lang,
                surface,
                line: *line_no,
                hallucination_class: "floor-weakening",
                rule: "diff-deleted-assertion",
                detail: "Assertion or formal obligation deleted without replacement in diff hunk"
                    .to_owned(),
                excerpt: excerpt.chars().take(140).collect(),
            });
        }
    }
}

fn audit_unified_diff_text(diff_text: &str, surface: &'static str) -> Vec<G2Finding> {
    let mut findings = Vec::new();
    let mut current_file = String::new();
    let mut current_lang: Option<&'static str> = None;
    let mut new_line = 1usize;
    let mut deleted_assertions: Vec<(usize, String)> = Vec::new();
    let mut added_assertions = 0usize;

    for line in diff_text.lines() {
        if let Some(rest) = line.strip_prefix("+++ b/") {
            if let Some(lang) = current_lang {
                flush_hunk_assertion_balance(
                    &current_file,
                    lang,
                    surface,
                    &deleted_assertions,
                    added_assertions,
                    &mut findings,
                );
            }
            deleted_assertions.clear();
            added_assertions = 0;
            current_file = rest.trim().to_owned();
            current_lang = detect_language(&current_file);
            continue;
        }
        if line.starts_with("@@ ") {
            if let Some(lang) = current_lang {
                flush_hunk_assertion_balance(
                    &current_file,
                    lang,
                    surface,
                    &deleted_assertions,
                    added_assertions,
                    &mut findings,
                );
            }
            deleted_assertions.clear();
            added_assertions = 0;
            new_line = parse_hunk_new_start(line);
            continue;
        }
        let Some(lang) = current_lang else {
            continue;
        };
        if let Some(added) = line.strip_prefix('+')
            && !line.starts_with("+++")
        {
            if is_assertion_or_obligation_line(added.trim()) {
                added_assertions += 1;
            }
            inspect_added_line(&current_file, lang, surface, new_line, added, &mut findings);
            new_line += 1;
        } else if let Some(removed) = line.strip_prefix('-')
            && !line.starts_with("---")
        {
            let trimmed = removed.trim();
            if is_assertion_or_obligation_line(trimmed) {
                deleted_assertions.push((new_line, trimmed.to_owned()));
            }
        } else if !line.starts_with('\\') {
            new_line += 1;
        }
    }
    if let Some(lang) = current_lang {
        flush_hunk_assertion_balance(
            &current_file,
            lang,
            surface,
            &deleted_assertions,
            added_assertions,
            &mut findings,
        );
    }
    findings
}

fn run_git_diff(repo_dir: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(repo_dir)
        .output()
        .map_err(|e| err(format!("Failed to execute git {:?}: {e}", args)))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(err(format!("git {:?} failed: {}", args, stderr.trim())));
    }
    String::from_utf8(output.stdout).map_err(|_| err("git diff output contained non-UTF-8 bytes"))
}

fn findings_to_json(findings: &[G2Finding]) -> Vec<Value> {
    findings
        .iter()
        .map(|f| {
            let spec = c2_spec_for(f.hallucination_class, f.rule);
            json!({
                "id": f.id,
                "file": f.file,
                "language": f.language,
                "surface": f.surface,
                "line": f.line,
                "hallucinationClass": f.hallucination_class,
                "rule": f.rule,
                "detail": f.detail,
                "excerpt": f.excerpt,
                "remediation": {
                    "antiPatternId": spec.anti_pattern_id,
                    "c2Replacement": spec.c2_replacement,
                    "requiredFiveTuple": [
                        "obligation",
                        "owner",
                        "scoped_failure",
                        "witness",
                        "affected_consumer"
                    ],
                    "antiEvasionWarning": spec.anti_evasion_warning,
                    "f3GuardProbeRecommended": f.hallucination_class == "redundant-defensive-glue",
                },
            })
        })
        .collect()
}

fn build_sarif(findings: &[G2Finding]) -> Value {
    let results: Vec<Value> = findings
        .iter()
        .map(|f| {
            let spec = c2_spec_for(f.hallucination_class, f.rule);
            json!({
                "ruleId": format!("{}/{}", f.hallucination_class, f.rule),
                "level": "error",
                "message": { "text": format!("{} ({}): {}", f.detail, spec.anti_pattern_id, spec.c2_replacement) },
                "locations": [{
                    "physicalLocation": {
                        "artifactLocation": { "uri": f.file },
                        "region": { "startLine": f.line.max(1) }
                    }
                }]
            })
        })
        .collect();
    json!({
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{
            "tool": {
                "driver": {
                    "name": "lambda-aitia/de-g2-diff-auditor",
                    "version": "0.1.0"
                }
            },
            "results": results
        }]
    })
}

/// Audit a Git repository or Git worktree's unstaged (`git diff`) and/or staged
/// (`git diff --cached`) changes for AI Anti-Defensive-Programming G2 defects.
///
/// Returns a structured JSON Value containing `passed`, `decision`, `countsByClass`,
/// `stagedFindingsCount`, `unstagedFindingsCount`, `g2Findings` (directly consumable by
/// Scheme `sidecar-audit.ss`), `repairPacket` (`AgentRepairPacket`), and `actionAuthorized: false`.
pub(crate) fn audit_git_repo_defense(
    repo_dir: &Path,
    base_ref: &str,
    staged_only: bool,
) -> Result<Value> {
    let mut all_findings = Vec::new();
    let staged_diff = run_git_diff(repo_dir, &["diff", "--cached", "--unified=3"])?;
    let staged_findings = audit_unified_diff_text(&staged_diff, "staged");
    let staged_count = staged_findings.len();
    all_findings.extend(staged_findings);

    let mut unstaged_count = 0usize;
    if !staged_only {
        let unstaged_diff = run_git_diff(repo_dir, &["diff", "--unified=3"])?;
        let unstaged_findings = audit_unified_diff_text(&unstaged_diff, "unstaged");
        unstaged_count = unstaged_findings.len();
        all_findings.extend(unstaged_findings);
        if staged_diff.is_empty() && unstaged_diff.is_empty() && base_ref != "HEAD" {
            let ref_diff = run_git_diff(repo_dir, &["diff", "--unified=3", base_ref])?;
            let ref_findings = audit_unified_diff_text(&ref_diff, "base-ref");
            unstaged_count = ref_findings.len();
            all_findings.extend(ref_findings);
        }
    }

    let mut counts: BTreeMap<&'static str, usize> = BTreeMap::from([
        ("silent-fallback", 0),
        ("floor-weakening", 0),
        ("redundant-defensive-glue", 0),
        ("fabricated-evidence", 0),
    ]);
    let mut diff_deleted_count = 0usize;
    for f in &all_findings {
        *counts.entry(f.hallucination_class).or_insert(0) += 1;
        if f.rule.starts_with("diff-deleted-") {
            diff_deleted_count += 1;
        }
    }
    let findings_json = findings_to_json(&all_findings);
    let passed = all_findings.is_empty();
    let decision = if passed { "ADMIT" } else { "REFUSE" };
    let repair_packet = json!({
        "schema": REPAIR_PACKET_SCHEMA,
        "schemaVersion": "1.0.0",
        "decision": decision,
        "boundedRetryPolicy": {
            "maxRepairAttempts": 3,
            "onBudgetExhausted": "EscalateToHuman",
            "forbidFloorWeakening": true,
            "forbidUnwitnessedObligationDeletion": true,
        },
        "totalFindings": all_findings.len(),
        "findings": findings_json,
        "actionAuthorized": false,
    });
    let report_digest =
        crate::source_tree::sha256(serde_json::to_string(&repair_packet)?.as_bytes());
    Ok(json!({
        "schema": "lambda-aitia.de-g2-diff-audit.v1",
        "passed": passed,
        "decision": decision,
        "stagedOnly": staged_only,
        "baseRef": base_ref,
        "stagedFindingsCount": staged_count,
        "unstagedFindingsCount": unstaged_count,
        "diffDeletedAssertionsCount": diff_deleted_count,
        "totalFindings": all_findings.len(),
        "countsByClass": counts,
        "g2Findings": findings_json,
        "repairPacket": repair_packet,
        "sarif": build_sarif(&all_findings),
        "reportDigest": report_digest,
        "actionAuthorized": false,
    }))
}
