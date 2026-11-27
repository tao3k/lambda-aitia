#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""RFC 0025 live example: Native AI Host External Sidecar CLI Workflow (`aitia sidecar ...`).

Demonstrates Environment 1 (`native-ai-environment`) end-to-end using ONLY the single
linked `aitia` CLI binary with ZERO `GERBIL_LOADPATH` and ZERO Python FFI imports:
  1. `aitia sidecar capture` freezes an external uninitialized Git repository diff.
  2. `aitia sidecar assess` invokes the live Scheme/POO 4-fragment `gerbil-ascent` engine
     to emit `ascentDirective` + `formalLibraryGuidance` (`upstream-library-reuse` +
     `ephemeral-ai-overlay`).
  3. `aitia sidecar verify-formal` rejects vacuous ephemeral AI overlays and accepts
     verified dual-mode formal evidence.
  4. `aitia sidecar receipt --repo <repo> --vault-dir <vault>` enforces vault-outside-repo
     confinement (refusing vaults inside the upstream repo!) and archives the NASA Org
     report + DSSEv1 PAE bundle strictly outside the external Git tree.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
from typing import Any


def sha256_prefixed(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def run_git(repo_dir: pathlib.Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=repo_dir,
        check=True,
        capture_output=True,
        text=True,
    )
    return proc.stdout.strip()


def run_cli(
    cli: str,
    args: list[str],
    stdin_payload: dict[str, Any] | None = None,
    expect_ok: bool = True,
) -> tuple[int, str, str]:
    proc = subprocess.run(
        [cli, *args],
        input=None if stdin_payload is None else json.dumps(stdin_payload),
        capture_output=True,
        text=True,
        check=False,
    )
    if expect_ok:
        assert proc.returncode == 0, f"Command {args} failed ({proc.returncode}): {proc.stderr}"
    return proc.returncode, proc.stdout, proc.stderr


def main() -> None:
    cli = os.environ.get("AITIA_BIN")
    if not cli:
        cli = str(
            pathlib.Path(__file__).resolve().parents[2]
            / "rust"
            / "target"
            / "debug"
            / "aitia"
        )
    assert pathlib.Path(cli).is_file(), f"Missing linked aitia binary at {cli}"

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        origin_repo = root / "upstream-oss-origin"
        upstream_repo = root / "upstream-oss-worktree"
        external_vault = root / "external-sidecar-vault"
        profile_file = root / "sidecar-profile.json"
        origin_repo.mkdir()

        # Create a pure Git worktree (where `.git` is a file, zero `.jj`, zero `.agents/aita/`)
        run_git(origin_repo, "init", "-b", "main")
        run_git(origin_repo, "config", "user.name", "Native AI Contributor")
        run_git(origin_repo, "config", "user.email", "native-ai@example.org")
        (origin_repo / "parser.py").write_text(
            "def parse(x):\n    assert x is not None\n    return x\n",
            encoding="utf-8",
        )
        run_git(origin_repo, "add", ".")
        run_git(origin_repo, "commit", "-m", "chore: initial commit")
        run_git(origin_repo, "worktree", "add", "-b", "fix/parser-guard", str(upstream_repo))
        assert (upstream_repo / ".git").is_file(), "Expected pure Git worktree (.git file)"
        assert not (upstream_repo / ".jj").exists()

        # 0. Inject real AI anti-defensive-programming defects into BOTH unstaged diff & staged index:
        #    - deleted `assert` (`diff-deleted-assertion` / `floor-weakening`)
        #    - `except Exception: pass` (`silent-fallback`)
        #    - `# TODO stub: return True` (`fabricated-evidence`)
        (upstream_repo / "parser.py").write_text(
            "def parse(x: str) -> str:\n"
            "    try:\n"
            "        return x.strip()\n"
            "    except Exception: pass\n"
            "def verify_ok() -> bool:\n"
            "    return True  # TODO stub verified: true\n",
            encoding="utf-8",
        )
        rc_diff_bad, out_diff_bad, _ = run_cli(
            cli,
            ["sidecar", "audit-diff", "--repo", str(upstream_repo), "--format", "json"],
            expect_ok=False,
        )
        assert rc_diff_bad != 0
        diff_report = json.loads(out_diff_bad)
        assert diff_report["passed"] is False
        assert diff_report["engineOwner"] == "scheme-poo-ascent-framework"
        assert diff_report["coreFloorPreserved"] is True
        assert diff_report["vcsObservation"]["vcsBackend"] == "gix"
        assert diff_report["vcsObservation"]["isLinkedWorktree"] is True
        assert diff_report["temporalCausality"]["acyclic"] is True
        assert len(diff_report["causalTrajectory"]) == 4
        assert diff_report["unstagedFindingsCount"] >= 3
        assert diff_report["countsByClass"]["silent-fallback"] >= 1
        assert diff_report["countsByClass"]["floor-weakening"] >= 1
        assert diff_report["countsByClass"]["fabricated-evidence"] >= 1
        assert diff_report["diffDeletedAssertionsCount"] >= 1
        assert diff_report["repairPacket"]["decision"] == "REFUSE"

        # 0b. Verify composable Scheme POO Subdomain Rule-Pack (`--rule-pack`) adds domain-specific
        #     checks with ZERO Rust edits while strictly preserving the DE G2 core floor!
        custom_pack_path = root / "subdomain-pack.json"
        custom_pack_path.write_text(
            json.dumps(
                {
                    "packId": "marlin-custom-subdomain",
                    "subdomain": "marlin-kernel",
                    "sourceMode": "ephemeral-ai-proposed",
                    "rules": [
                        {
                            "ruleId": "forbid-verify-ok-stub",
                            "hallucinationClass": "subdomain-invariant-violation",
                            "languages": ["python"],
                            "tokensAll": ["def verify_ok"],
                            "detail": "Subdomain pack forbids unverified stub helper `verify_ok`",
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        rc_pack, out_pack, _ = run_cli(
            cli,
            [
                "sidecar",
                "audit-diff",
                "--repo",
                str(upstream_repo),
                "--rule-pack",
                str(custom_pack_path),
                "--format",
                "json",
            ],
            expect_ok=False,
        )
        assert rc_pack != 0
        pack_report = json.loads(out_pack)
        assert pack_report["rulePacksApplied"] == ["de-g2-core", "marlin-custom-subdomain"]
        assert pack_report["coreFloorPreserved"] is True
        assert pack_report["countsByClass"]["subdomain-invariant-violation"] >= 1
        assert pack_report["countsByClass"]["silent-fallback"] >= 1

        # 0c. Verify zero-config `aitia sidecar capture` works without `--profile`!
        _, zero_cfg_cap_out, _ = run_cli(
            cli,
            ["sidecar", "capture", "--repo", str(upstream_repo)],
        )
        zero_cfg_cap = json.loads(zero_cfg_cap_out)
        assert zero_cfg_cap["funflowObservability"]["vcsBackend"] == "gix"
        assert zero_cfg_cap["funflowObservability"]["engineOwner"] == "scheme-poo-ascent-framework"
        assert zero_cfg_cap["actionAuthorized"] is False

        # 0d. Verify single-source-of-truth `aitia review --tool-schema` and ZERO-FLAG
        #     single-entry FunFlow Choice `aitia review <dir>` + self-healing choice!
        _, schema_out, _ = run_cli(cli, ["review", "--tool-schema"])
        tool_schema = json.loads(schema_out)
        assert tool_schema["schema"] == "lambda-aitia.model-tool-definition.v1"
        assert tool_schema["name"] == "aitia_review_step"
        assert tool_schema["readOnly"] is True
        assert tool_schema["actionAuthorized"] is False

        _, rev_discover_out, _ = run_cli(cli, ["review", str(upstream_repo)])
        rev_discover = json.loads(rev_discover_out)
        assert rev_discover["schema"] == "lambda-aitia.funflow-choice-frontier.v1"
        assert rev_discover["singleEntrypoint"] == "aitia review"
        assert rev_discover["sharedPrefix"]["fencedEffectsForbidden"] is True
        assert rev_discover["fencedTailAdmitted"] is False
        assert rev_discover["worldCount"] >= 2
        assert rev_discover["actionAuthorized"] is False
        assert len(rev_discover["recommendedFormalModels"]) >= 1
        choice_ids = [c["choiceId"] for c in rev_discover["choices"]]
        assert "repair-diff-defects" in choice_ids
        assert "compose-subdomain-rule-pack" in choice_ids
        # Self-healing feedback on unknown choice name
        _, rev_bad_out, _ = run_cli(
            cli,
            ["review"],
            stdin_payload={"repo": str(upstream_repo), "choice": "typo-choice"},
        )
        rev_bad = json.loads(rev_bad_out)
        assert rev_bad["choiceAccepted"] is False
        assert "selfHealingHint" in rev_bad
        assert "repair-diff-defects" in rev_bad["selfHealingHint"]["validChoiceIds"]
        assert "dslGrammar" in rev_discover and "sexpPlanTemplate" in rev_discover

        # 0e. Verify declarative `(aitia-review-plan ...)` S-expr file drives native ASCENT
        #     `relational-choice-solve` convergence (2 competing worlds -> 1 unique-deduction),
        #     omits bulky teaching kit on Turn 2 valid plans, and rejects forbidden
        #     `disable-core-floor` AND cyclic `(depends-on ...)` with 0 surviving worlds!
        plan_file = root / "scenario-plan.sexp"
        plan_file.write_text(
            f'(aitia-review-plan\n'
            f'  (scenario "worktree-parser-audit")\n'
            f'  (repo "{upstream_repo}")\n'
            f'  (depends-on "audit-diff" "verify-formal")\n'
            f'  (open-branches "hyp-missing-assert" "hyp-external-test-moved")\n'
            f'  (probes\n'
            f'    (probe "hyp-missing-assert" supports "parser.py deleted assert without replacement")\n'
            f'    (probe "hyp-external-test-moved" refutes "no other test file exists in worktree")))\n',
            encoding="utf-8",
        )
        _, rev_plan_out, _ = run_cli(cli, ["review", str(plan_file)])
        rev_plan = json.loads(rev_plan_out)
        assert rev_plan["planValidation"]["validated"] is True
        assert rev_plan["planValidation"]["acyclic"] is True
        assert rev_plan["planValidation"]["zeroEvalDatumParser"] is True
        assert "dslGrammar" not in rev_plan and "sexpPlanTemplate" not in rev_plan
        assert rev_plan["ascentChoiceSolution"]["choiceStatus"] == "unique-deduction"
        assert rev_plan["ascentChoiceSolution"]["worldCount"] == 1
        assert rev_plan["ascentChoiceSolution"]["worlds"][0]["reviewBranch"] == "hyp-missing-assert"
        assert rev_plan["ascentChoiceSolution"]["worlds"][0]["dispatchDecision"] == "repair-mechanical-defects"

        cyclic_plan = root / "cyclic-plan.sexp"
        cyclic_plan.write_text(
            f'(aitia-review-plan (repo "{upstream_repo}") (depends-on "a" "b") (depends-on "b" "a"))\n',
            encoding="utf-8",
        )
        _, rev_cyc_out, _ = run_cli(cli, ["review", str(cyclic_plan)])
        rev_cyc = json.loads(rev_cyc_out)
        assert rev_cyc["planValidation"]["validated"] is False
        assert rev_cyc["planValidation"]["acyclic"] is False
        assert rev_cyc["ascentChoiceSolution"]["choiceStatus"] == "unsatisfiable"
        assert rev_cyc["ascentChoiceSolution"]["worldCount"] == 0
        assert "dslGrammar" in rev_cyc

        evil_plan = root / "evil-plan.sexp"
        evil_plan.write_text(
            f'(aitia-review-plan (repo "{upstream_repo}") (disable-core-floor #t))\n',
            encoding="utf-8",
        )
        _, rev_evil_out, _ = run_cli(cli, ["review", str(evil_plan)])
        rev_evil = json.loads(rev_evil_out)
        assert rev_evil["planValidation"]["validated"] is False
        assert rev_evil["planValidation"]["coreFloorIntact"] is False
        assert rev_evil["ascentChoiceSolution"]["choiceStatus"] == "unsatisfiable"
        assert rev_evil["ascentChoiceSolution"]["worldCount"] == 0

        # Stage the defective file and verify `--staged` + `--format agent-feedback` + `--format sarif`
        run_git(upstream_repo, "add", "parser.py")
        rc_staged_bad, out_staged_fb, _ = run_cli(
            cli,
            [
                "sidecar",
                "audit-diff",
                "--repo",
                str(upstream_repo),
                "--staged",
                "--format",
                "agent-feedback",
            ],
            expect_ok=False,
        )
        assert rc_staged_bad != 0
        fb_pkt = json.loads(out_staged_fb)
        assert fb_pkt["schema"] == "lambda-aitia.de-g2-repair-packet.v1"
        assert fb_pkt["decision"] == "REFUSE"
        assert fb_pkt["actionAuthorized"] is False

        rc_sarif, out_sarif, _ = run_cli(
            cli,
            ["sidecar", "audit-diff", "--repo", str(upstream_repo), "--staged", "--format", "sarif"],
            expect_ok=False,
        )
        assert rc_sarif != 0
        sarif_doc = json.loads(out_sarif)
        assert sarif_doc["version"] == "2.1.0" and len(sarif_doc["runs"][0]["results"]) >= 3

        # Unstage and replace with clean, non-defensive-hallucination code preserving the assertion!
        run_git(upstream_repo, "reset", "HEAD", "parser.py")
        (upstream_repo / "parser.py").write_text(
            "def parse(x: str) -> str:\n"
            "    assert x is not None\n"
            "    if not x.strip():\n"
            "        raise ValueError('empty')\n"
            "    return x.strip()\n",
            encoding="utf-8",
        )
        _, clean_diff_out, _ = run_cli(
            cli,
            ["sidecar", "audit-diff", "--repo", str(upstream_repo)],
        )
        clean_diff = json.loads(clean_diff_out)
        assert clean_diff["passed"] is True and clean_diff["totalFindings"] == 0

        profile = {
            "schema": "lambda-aitia.sidecar-profile.v1",
            "targetRepo": "upstream-org/parser-lib",
            "nasaProfile": "nasa/sdlc/npr-7150.2d",
            "requiredAuditLenses": ["correctness", "security"],
            "forbiddenUpstreamPrefixes": [".agents/aita/", ".aitia/"],
            "commitConvention": "conventional-commits",
            "allowAuditTrailer": False,
            "epoch": 1,
        }
        profile_file.write_text(json.dumps(profile, indent=2), encoding="utf-8")

        # 1. `aitia sidecar capture`
        _, cap_out, _ = run_cli(
            cli,
            [
                "sidecar",
                "capture",
                "--repo",
                str(upstream_repo),
                "--base",
                "HEAD",
                "--profile",
                str(profile_file),
            ],
        )
        ctx = json.loads(cap_out)
        assert ctx["upstreamPollutionFree"] is True
        assert ctx["actionAuthorized"] is False
        assert ctx["defenseAudit"]["passed"] is True
        assert ctx["funflowObservability"]["schema"] == "lambda-aitia.funflow-observability-packet.v1"
        assert ctx["funflowObservability"]["nextFrontier"] == "assess-ascent-and-dispatch-ai-lenses"
        ctx_digest = ctx["contextDigest"]

        # 2. `aitia sidecar assess` (Stage 1 pre-audit -> live Scheme gerbil-ascent)
        _, pre_out, _ = run_cli(
            cli,
            ["sidecar", "assess"],
            stdin_payload={
                "targetRepo": profile["targetRepo"],
                "nasaProfile": profile["nasaProfile"],
                "contextDigest": ctx_digest,
                "changedPaths": ctx["changedFiles"],
                "requiredLenses": profile["requiredAuditLenses"],
                "aiReports": [],
                "conversationBound": False,
                "humanApproved": False,
                "dispositions": [],
            },
        )
        pre = json.loads(pre_out)
        assert pre["admissible"] is False
        assert pre["openObligations"] == ["SWE-087", "SWE-146"]
        assert pre["ascentDirective"]["engineBinding"] == "native-ai-environment"
        assert pre["formalLibraryGuidance"]["generalCaseMode"] == "upstream-library-reuse"
        assert pre["formalLibraryGuidance"]["specialCaseMode"] == "ephemeral-ai-overlay"

        # 3. `aitia sidecar verify-formal` (Negative Control: vacuous overlay MUST fail!)
        resolver_digest = sha256_prefixed("de-resolver-cli-v1")
        vacuous_fe = {
            "schema": "lambda-aitia.de-formal-evidence.v1",
            "actionAuthorized": False,
            "pendingOracles": [],
            "g2Findings": [],
            "guardProbes": [],
            "formalModels": [
                {
                    "modelId": "ParserOverlay.qnt",
                    "mode": "ephemeral-ai-overlay",
                    "libraryPackage": "@deterministic-engineering/quint-models",
                    "resolverDigest": resolver_digest,
                    "contextDigest": ctx_digest,
                    "countermodelVerified": False,
                    "proofClean": True,
                    "passed": True,
                    "storedInSidecarVault": True,
                }
            ],
        }
        rc_vac, _, err_vac = run_cli(
            cli,
            ["sidecar", "verify-formal", "--context-digest", ctx_digest],
            stdin_payload=vacuous_fe,
            expect_ok=False,
        )
        assert rc_vac != 0 and "MR05 @countermodel" in err_vac

        # Valid dual-mode formal evidence (`upstream-library-reuse` + `ephemeral-ai-overlay`)
        formal_models = [
            {
                "modelId": "InputSanitizationBounds",
                "mode": "upstream-library-reuse",
                "libraryPackage": "@deterministic-engineering/lean-models",
                "resolverDigest": resolver_digest,
                "contextDigest": ctx_digest,
                "countermodelVerified": False,
                "proofClean": True,
                "passed": True,
                "storedInSidecarVault": True,
            },
            {
                "modelId": "ParserOverlay.qnt",
                "mode": "ephemeral-ai-overlay",
                "libraryPackage": "@deterministic-engineering/quint-models",
                "resolverDigest": resolver_digest,
                "contextDigest": ctx_digest,
                "countermodelVerified": True,
                "proofClean": True,
                "passed": True,
                "storedInSidecarVault": True,
            },
        ]
        formal_evidence_ok = {
            "schema": "lambda-aitia.de-formal-evidence.v1",
            "actionAuthorized": False,
            "pendingOracles": [],
            "g2Findings": [],
            "guardProbes": [{"probeId": "non-empty-strip-guard", "verdict": "essential"}],
            "formalModels": formal_models,
        }
        _, fv_out, _ = run_cli(
            cli,
            ["sidecar", "verify-formal", "--context-digest", ctx_digest],
            stdin_payload=formal_evidence_ok,
        )
        fv = json.loads(fv_out)
        assert fv["verified"] is True
        assert fv["upstreamReuseCount"] == 1
        assert fv["ephemeralOverlayCount"] == 1

        # 4. `aitia sidecar assess` (Stage 2 post-audit -> Proven!)
        ai_reports = [
            {
                "schema": "lambda-aitia.ai-audit-report.v1",
                "engineBinding": "native-ai-environment",
                "provider": "native-host-llm",
                "modelId": "host-agent-ascent-v1",
                "promptTemplateDigest": sha256_prefixed("native-cli-prompt"),
                "contextDigest": ctx_digest,
                "lens": lens,
                "epistemicStatus": "hypothesized",
                "findings": [],
                "openQuestions": [],
                "contradictions": [],
                "actionAuthorized": False,
            }
            for lens in ["correctness", "security"]
        ]
        _, post_out, _ = run_cli(
            cli,
            ["sidecar", "assess"],
            stdin_payload={
                "targetRepo": profile["targetRepo"],
                "nasaProfile": profile["nasaProfile"],
                "contextDigest": ctx_digest,
                "changedPaths": ctx["changedFiles"],
                "requiredLenses": profile["requiredAuditLenses"],
                "aiReports": ai_reports,
                "conversationBound": True,
                "humanApproved": True,
                "dispositions": [],
                "guardProbes": formal_evidence_ok["guardProbes"],
                "formalModels": formal_models,
                "coordinatorClaimedAdmit": True,
            },
        )
        post = json.loads(post_out)
        assert post["admissible"] is True
        assert post["epistemicStatus"] == "Proven"
        assert post["funflowTrace"]["schema"] == "lambda-aitia.funflow-ascent-trace.v1"
        assert post["funflowTrace"]["derivedCounts"]["admittedFormalModels"] == 2
        assert post["supportedObligations"] == ["SWE-083", "SWE-084", "SWE-087", "SWE-146"]

        # 5. `aitia sidecar receipt` — Negative Control: vault INSIDE upstream repo MUST fail closed!
        conversation = {
            "schema": "lambda-aitia.conversation-transcript.v1",
            "contextDigest": ctx_digest,
            "redactionMode": "redacted-summary",
            "turns": [
                {
                    "turnId": 1,
                    "role": "human",
                    "summary": "Reject empty whitespace inputs fail-closed via native CLI workflow.",
                    "contentDigest": sha256_prefixed("native-turn-1"),
                }
            ],
            "actionAuthorized": False,
        }
        conv_digest = sha256_prefixed(json.dumps(conversation, sort_keys=True, separators=(",", ":")))
        receipt_spec = {
            "context": ctx,
            "aiReports": ai_reports,
            "conversation": conversation,
            "humanDecision": {
                "schema": "lambda-aitia.human-audit-decision.v1",
                "contextDigest": ctx_digest,
                "conversationDigest": conv_digest,
                "reviewerId": "maintainer@hardenedlinux.org",
                "decision": "approve-commit",
                "dispositions": [],
                "actionAuthorized": False,
            },
            "profile": profile,
            "formalEvidence": formal_evidence_ok,
            "commitProposal": {
                "type": "fix",
                "scope": "parser",
                "summary": "reject empty whitespace input fail-closed",
            },
            "signingSeeds": ["91" * 32, "92" * 32],
        }
        rc_inside, _, err_inside = run_cli(
            cli,
            [
                "sidecar",
                "receipt",
                "--repo",
                str(upstream_repo),
                "--vault-dir",
                str(upstream_repo / ".aitia-vault"),
            ],
            stdin_payload=receipt_spec,
            expect_ok=False,
        )
        assert rc_inside != 0 and "Vault-outside-repo violation" in err_inside

        # 6. `aitia sidecar commit` — Negative Control: unstaged index MUST fail closed!
        rc_unstaged, _, err_unstaged = run_cli(
            cli,
            [
                "sidecar",
                "commit",
                "--repo",
                str(upstream_repo),
                "--vault-dir",
                str(external_vault),
            ],
            stdin_payload=receipt_spec,
            expect_ok=False,
        )
        assert rc_unstaged != 0 and "pre-staged changes" in err_unstaged

        # 7. Negative Control: sneaking a silent-fallback into staged index right before commit MUST fail!
        (upstream_repo / "parser.py").write_text(
            "def parse(x: str) -> str:\n"
            "    assert x is not None\n"
            "    try:\n"
            "        return x.strip()\n"
            "    except Exception: pass\n",
            encoding="utf-8",
        )
        run_git(upstream_repo, "add", "parser.py")
        rc_sneak, _, err_sneak = run_cli(
            cli,
            [
                "sidecar",
                "commit",
                "--repo",
                str(upstream_repo),
                "--vault-dir",
                str(external_vault),
            ],
            stdin_payload=receipt_spec,
            expect_ok=False,
        )
        assert rc_sneak != 0 and "DE G2 staged diff anti-defensive-programming gate refused commit" in err_sneak

        # 8. Restore clean audited code, stage explicit file, and execute `aitia sidecar commit`!
        (upstream_repo / "parser.py").write_text(
            "def parse(x: str) -> str:\n"
            "    assert x is not None\n"
            "    if not x.strip():\n"
            "        raise ValueError('empty')\n"
            "    return x.strip()\n",
            encoding="utf-8",
        )
        run_git(upstream_repo, "add", "parser.py")
        _, commit_out, _ = run_cli(
            cli,
            [
                "sidecar",
                "commit",
                "--repo",
                str(upstream_repo),
                "--vault-dir",
                str(external_vault),
            ],
            stdin_payload=receipt_spec,
        )
        bundle = json.loads(commit_out)
        assert bundle["actionAuthorized"] is False
        assert bundle["upstreamCommitSha"] == run_git(upstream_repo, "rev-parse", "HEAD")
        va = bundle["vaultArtifacts"]
        assert va["vaultOutsideRepoVerified"] is True
        assert pathlib.Path(va["bundlePath"]).is_file()
        assert pathlib.Path(va["orgReportPath"]).is_file()
        assert not (upstream_repo / ".aitia-vault").exists()
        assert not (upstream_repo / ".agents").exists()
        assert run_git(upstream_repo, "status", "--porcelain") == ""

    print(
        json.dumps(
            {
                "example": "08-native-ai-sidecar-cli",
                "pureGitWorktreeNoJj": True,
                "zeroGerbilLoadpathCliOnly": True,
                "unstagedAndStagedG2DefectsCaught": True,
                "sarif210AndRepairPacketEmitted": True,
                "stagedSilentFallbackCommitBlocked": True,
                "funflowTraceEmitted": True,
                "preAuditOpenObligations": pre["openObligations"],
                "postAuditEpistemicStatus": post["epistemicStatus"],
                "vacuousOverlayCliRejected": True,
                "vaultInsideUpstreamRepoRejected": True,
                "unstagedCommitRejected": True,
                "sidecarCommitExecutedInWorktree": True,
                "upstreamCommitSha": bundle["upstreamCommitSha"],
                "externalVaultArchived": True,
                "upstreamRepoClean": True,
                "receiptDigest": bundle["receiptDigest"],
                "actionAuthorized": False,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
