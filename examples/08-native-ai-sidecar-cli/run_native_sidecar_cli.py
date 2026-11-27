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
        (origin_repo / "parser.py").write_text("def parse(x):\n    return x\n", encoding="utf-8")
        run_git(origin_repo, "add", ".")
        run_git(origin_repo, "commit", "-m", "chore: initial commit")
        run_git(origin_repo, "worktree", "add", "-b", "fix/parser-guard", str(upstream_repo))
        assert (upstream_repo / ".git").is_file(), "Expected pure Git worktree (.git file)"
        assert not (upstream_repo / ".jj").exists()
        (upstream_repo / "parser.py").write_text(
            "def parse(x: str) -> str:\n    if not x.strip():\n        raise ValueError('empty')\n    return x.strip()\n",
            encoding="utf-8",
        )

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

        # 7. Stage explicit file and execute `aitia sidecar commit` in pure Git worktree!
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
