#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""RFC 0021 live example: Detached Sidecar Governance for an Uninitialized External Git Repo.

Demonstrates the TWO sanctioned AI engine connection modes (zero ad-hoc CLI/HTTP LLM wrappers):
1. `native-ai-environment`: Aitia emits ASCENT-guided obligation directives
   (`aiEngineHandoffs.nativeHostLlm`) directly into the surrounding native LLM host context.
2. `marlin-agent-core`: Aitia emits a typed Marlin Agent Core handoff frame
   (`aiEngineHandoffs.marlinAgentCore`, `lambda-aitia.marlin-audit-handoff.v1`) for full
   Marlin-orchestrated AI execution.

Also verifies:
- Zero-pollution SDLC governance over an ordinary upstream Git repo with NO `.agents/aita/`.
- Redacted Conversation Audit Transcript (`conversationDigest`) + independent human disposition.
- Five fail-closed negative controls: upstream pollution, unapproved engineBinding, stale AI
  audit after code edit, unaddressed high-severity finding, and AI self-approval.
- Dual-surface NASA commit output: clean upstream Git commit + detached Sidecar Vault
  containing the NASA Org report and wire-compatible RFC 0019 DSSE in-toto/SLSA envelope
  verified offline against a pinned TUF TrustRoot.
"""

from __future__ import annotations

import hashlib
import json
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


def execute_native_host_llm_lens(handoff: dict[str, Any], lens: str) -> dict[str, Any]:
    """Mode 1: Native AI host environment consumes Aitia's ASCENT directive in-context."""
    directive = handoff["ascentDirective"]
    assert handoff["engineBinding"] == "native-ai-environment"
    assert handoff["actionAuthorized"] is False
    assert directive["schema"] == "lambda-aitia.ascent-audit-directive.v1"

    findings: list[dict[str, Any]] = []
    open_questions: list[str] = []
    if lens == "security":
        findings.append(
            {
                "id": "SEC-001",
                "file": "src/token_parser.py",
                "lineRange": "L1-L20",
                "severity": "high",
                "evidenceExcerpt": "hmac.compare_digest(expected, provided)",
                "summary": "Verify caller passes UTF-8 normalized non-empty secret key before HMAC comparison.",
                "competingHypotheses": [
                    "Upstream middleware already rejects empty secrets before calling verify_token.",
                    "Direct library callers could pass an empty secret string unless guarded locally.",
                ],
                "reproCheck": "python3 -m unittest discover -s tests",
            }
        )
        open_questions.append("Should empty-secret rejection raise ValueError or return False in upstream API?")
    elif lens == "correctness":
        findings.append(
            {
                "id": "COR-001",
                "file": "src/token_parser.py",
                "lineRange": "L8-L14",
                "severity": "low",
                "evidenceExcerpt": "if not secret or not token: return False",
                "summary": "Fail-closed guard handles empty secret and empty token identically.",
                "competingHypotheses": [
                    "Returning False matches existing upstream boolean signature.",
                    "Callers auditing misconfiguration might prefer an explicit exception.",
                ],
                "reproCheck": "python3 -m unittest discover -s tests",
            }
        )
    return {
        "schema": "lambda-aitia.ai-audit-report.v1",
        "engineBinding": "native-ai-environment",
        "provider": "native-host-llm",
        "modelId": "host-agent-ascent-guided-v1",
        "promptTemplateDigest": sha256_prefixed(json.dumps(directive, sort_keys=True)),
        "contextDigest": directive["contextDigest"],
        "lens": lens,
        "epistemicStatus": "hypothesized",
        "findings": findings,
        "openQuestions": open_questions,
        "contradictions": [],
        "actionAuthorized": False,
    }


def execute_marlin_agent_core_lens(handoff: dict[str, Any], lens: str) -> dict[str, Any]:
    """Mode 2: Marlin Agent Core executes orchestrated AI audit over its typed handoff frame."""
    assert handoff["engineBinding"] == "marlin-agent-core"
    assert handoff["schema"] == "lambda-aitia.marlin-audit-handoff.v1"
    assert handoff["boundary"] == "marlin-agent-core"
    assert handoff["capability"] == "marlin.agent.audit-detached-diff"
    assert handoff["actionAuthorized"] is False
    directive = handoff["ascentDirective"]
    return {
        "schema": "lambda-aitia.ai-audit-report.v1",
        "engineBinding": "marlin-agent-core",
        "provider": "marlin-agent-core",
        "modelId": "marlin-orchestrated-auditor-v1",
        "promptTemplateDigest": sha256_prefixed(f"marlin:{lens}:" + json.dumps(directive, sort_keys=True)),
        "contextDigest": handoff["contextDigest"],
        "lens": lens,
        "epistemicStatus": "hypothesized",
        "findings": [],
        "openQuestions": [],
        "contradictions": [],
        "actionAuthorized": False,
    }


def main() -> None:
    import lambda_aitia_rust  # type: ignore[import-not-found]

    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        # 1. Create an ordinary EXTERNAL upstream Git repository (NO .agents/aita/, NO dev/sysml/)
        upstream_repo = root / "external-oss-repo"
        sidecar_vault = root / "aitia-sidecar-vault"
        upstream_repo.mkdir()
        sidecar_vault.mkdir()

        run_git(upstream_repo, "init", "-b", "main")
        run_git(upstream_repo, "config", "user.name", "External Contributor")
        run_git(upstream_repo, "config", "user.email", "contrib@example.org")
        (upstream_repo / "src").mkdir()
        (upstream_repo / "tests").mkdir()
        (upstream_repo / "src" / "token_parser.py").write_text(
            "def verify_token(expected: str, provided: str) -> bool:\n"
            "    return expected == provided\n",
            encoding="utf-8",
        )
        (upstream_repo / "tests" / "test_token_parser.py").write_text(
            "import unittest\n"
            "from src.token_parser import verify_token\n\n"
            "class TestTokenParser(unittest.TestCase):\n"
            "    def test_valid(self):\n"
            "        self.assertTrue(verify_token('abc', 'abc'))\n"
            "    def test_invalid(self):\n"
            "        self.assertFalse(verify_token('abc', 'xyz'))\n",
            encoding="utf-8",
        )
        run_git(upstream_repo, "add", ".")
        run_git(upstream_repo, "commit", "-m", "chore: initial upstream baseline")

        # Make a security hardening edit in the external repo (still ZERO Aitia files!)
        (upstream_repo / "src" / "token_parser.py").write_text(
            "import hmac\n\n"
            "def verify_token(expected: str, provided: str) -> bool:\n"
            "    if not expected or not provided:\n"
            "        return False\n"
            "    return hmac.compare_digest(expected.encode('utf-8'), provided.encode('utf-8'))\n",
            encoding="utf-8",
        )
        test_proc = subprocess.run(
            ["python3", "-m", "unittest", "discover", "-s", "tests"],
            cwd=upstream_repo,
            check=True,
            capture_output=True,
            text=True,
        )
        det_checks = [
            {
                "name": "upstream.unittest",
                "command": "python3 -m unittest discover -s tests",
                "passed": test_proc.returncode == 0,
                "outputDigest": sha256_prefixed(test_proc.stdout + test_proc.stderr),
            }
        ]

        # 2. Detached Sidecar Profile (stored OUTSIDE the external repo!)
        profile = {
            "schema": "lambda-aitia.sidecar-profile.v1",
            "targetRepo": "upstream-org/token-parser",
            "nasaProfile": "nasa/sdlc/npr-7150.2d",
            "requiredAuditLenses": ["correctness", "security", "api-regression", "nasa-swe146"],
            "forbiddenUpstreamPrefixes": [".agents/aita/", ".aitia/"],
            "commitConvention": "conventional-commits",
            "allowAuditTrailer": False,
            "epoch": 1,
        }
        profile_json = json.dumps(profile)

        # Negative Control 1: Upstream repository pollution MUST fail closed!
        polluted_file = upstream_repo / ".agents" / "aita" / "project.json"
        polluted_file.parent.mkdir(parents=True)
        polluted_file.write_text('{"schemaVersion": 1}\n', encoding="utf-8")
        pollution_rejected = False
        try:
            lambda_aitia_rust.capture_detached_audit_context(
                str(upstream_repo), "HEAD", profile_json, json.dumps(det_checks)
            )
        except ValueError as exc:
            pollution_rejected = "Upstream repository pollution blocked" in str(exc)
        assert pollution_rejected, "Upstream repo pollution MUST fail closed!"
        polluted_file.unlink()
        polluted_file.parent.rmdir()
        polluted_file.parent.parent.rmdir()

        # 3. Capture immutable frozen AuditContextPack with BOTH sanctioned AI handoffs
        context_json = lambda_aitia_rust.capture_detached_audit_context(
            str(upstream_repo), "HEAD", profile_json, json.dumps(det_checks)
        )
        context = json.loads(context_json)
        assert context["upstreamPollutionFree"] is True
        assert context["actionAuthorized"] is False
        handoffs = context["aiEngineHandoffs"]

        # 4. Run multi-lens audit across the TWO sanctioned AI engine bindings:
        #    - Mode 1 (Native AI Host Environment via ASCENT directive): correctness + security
        #    - Mode 2 (Marlin Agent Core handoff boundary): api-regression + nasa-swe146
        ai_reports = [
            execute_native_host_llm_lens(handoffs["nativeHostLlm"], "correctness"),
            execute_native_host_llm_lens(handoffs["nativeHostLlm"], "security"),
            execute_marlin_agent_core_lens(handoffs["marlinAgentCore"], "api-regression"),
            execute_marlin_agent_core_lens(handoffs["marlinAgentCore"], "nasa-swe146"),
        ]

        # 5. Bind redacted Conversation Audit Transcript (SWE-146 provenance without secret leaks)
        conversation = {
            "schema": "lambda-aitia.conversation-transcript.v1",
            "contextDigest": context["contextDigest"],
            "redactionMode": "redacted-summary",
            "turns": [
                {
                    "turnId": 1,
                    "role": "human",
                    "summary": "Harden token comparison against timing side channels without changing public signature.",
                    "contentDigest": sha256_prefixed("turn-1-human-request"),
                },
                {
                    "turnId": 2,
                    "role": "assistant",
                    "modelId": "host-agent-ascent-guided-v1",
                    "summary": "Replaced == with hmac.compare_digest and added empty-string fail-closed guard.",
                    "contentDigest": sha256_prefixed("turn-2-assistant-patch"),
                },
                {
                    "turnId": 3,
                    "role": "human",
                    "summary": "Reviewed SEC-001 finding; confirmed empty-input guard is in-place and unittest green.",
                    "contentDigest": sha256_prefixed("turn-3-human-review"),
                },
            ],
            "actionAuthorized": False,
        }
        conv_digest = sha256_prefixed(json.dumps(conversation, sort_keys=True, separators=(",", ":")))

        human_decision_ok = {
            "schema": "lambda-aitia.human-audit-decision.v1",
            "contextDigest": context["contextDigest"],
            "conversationDigest": conv_digest,
            "reviewerId": "maintainer@hardenedlinux.org",
            "decision": "approve-commit",
            "dispositions": [
                {
                    "findingId": "SEC-001",
                    "status": "fixed-verified",
                    "rationale": "Empty secret/token guard added at line 4 before hmac.compare_digest and verified by unittest.",
                }
            ],
            "actionAuthorized": False,
        }

        # Negative Control 2: Unapproved ad-hoc CLI/HTTP engineBinding MUST fail closed!
        rogue_reports = json.loads(json.dumps(ai_reports))
        rogue_reports[0]["engineBinding"] = "ad-hoc-cli-http-wrapper"
        rogue_binding_rejected = False
        try:
            lambda_aitia_rust.verify_ai_audit_and_conversation(
                context_json,
                json.dumps(rogue_reports),
                json.dumps(conversation),
                json.dumps(human_decision_ok),
                profile_json,
            )
        except ValueError as exc:
            rogue_binding_rejected = "sanctioned engineBinding" in str(exc)
        assert rogue_binding_rejected, "Unapproved ad-hoc CLI engineBinding MUST fail closed!"

        # Negative Control 3: Unaddressed High-severity finding MUST fail closed!
        unaddressed_decision = dict(human_decision_ok, dispositions=[])
        unaddressed_rejected = False
        try:
            lambda_aitia_rust.verify_ai_audit_and_conversation(
                context_json,
                json.dumps(ai_reports),
                json.dumps(conversation),
                json.dumps(unaddressed_decision),
                profile_json,
            )
        except ValueError as exc:
            unaddressed_rejected = "Unaddressed critical/high AI finding" in str(exc)
        assert unaddressed_rejected, "Unaddressed High finding MUST fail closed!"

        # Negative Control 4: AI self-approval (missing human approve-commit) MUST fail closed!
        ai_self_approve = dict(human_decision_ok, decision="ai-auto-approved")
        self_approve_rejected = False
        try:
            lambda_aitia_rust.verify_ai_audit_and_conversation(
                context_json,
                json.dumps(ai_reports),
                json.dumps(conversation),
                json.dumps(ai_self_approve),
                profile_json,
            )
        except ValueError as exc:
            self_approve_rejected = "did not approve commit" in str(exc)
        assert self_approve_rejected, "AI self-approval MUST fail closed!"

        # Negative Control 5: Stale AI audit after 1-line code edit MUST fail closed!
        (upstream_repo / "src" / "token_parser.py").write_text(
            "import hmac\n\n"
            "def verify_token(expected: str, provided: str) -> bool:\n"
            "    # drift after audit\n"
            "    if not expected or not provided:\n"
            "        return False\n"
            "    return hmac.compare_digest(expected.encode('utf-8'), provided.encode('utf-8'))\n",
            encoding="utf-8",
        )
        drifted_ctx_json = lambda_aitia_rust.capture_detached_audit_context(
            str(upstream_repo), "HEAD", profile_json, json.dumps(det_checks)
        )
        stale_audit_rejected = False
        try:
            lambda_aitia_rust.verify_ai_audit_and_conversation(
                drifted_ctx_json,
                json.dumps(ai_reports),
                json.dumps(conversation),
                json.dumps(human_decision_ok),
                profile_json,
            )
        except ValueError as exc:
            stale_audit_rejected = "Stale AI audit report rejected" in str(exc)
        assert stale_audit_rejected, "Stale AI audit after code edit MUST fail closed!"

        # Restore audited code snapshot
        (upstream_repo / "src" / "token_parser.py").write_text(
            "import hmac\n\n"
            "def verify_token(expected: str, provided: str) -> bool:\n"
            "    if not expected or not provided:\n"
            "        return False\n"
            "    return hmac.compare_digest(expected.encode('utf-8'), provided.encode('utf-8'))\n",
            encoding="utf-8",
        )

        # 6. Build dual-surface NASA Sidecar Commit Bundle + wire-compatible DSSE envelope
        seed_1, seed_2 = "71" * 32, "72" * 32
        receipt_bundle_json = lambda_aitia_rust.build_nasa_sidecar_receipt(
            json.dumps(
                {
                    "context": context,
                    "aiReports": ai_reports,
                    "conversation": conversation,
                    "humanDecision": human_decision_ok,
                    "profile": profile,
                    "commitProposal": {
                        "type": "fix",
                        "scope": "auth",
                        "summary": "use constant-time HMAC comparison for tokens",
                        "body": "Guard empty inputs and compare token bytes with hmac.compare_digest.",
                    },
                    "signingSeeds": [seed_1, seed_2],
                }
            )
        )
        bundle = json.loads(receipt_bundle_json)
        assert bundle["schema"] == "lambda-aitia.nasa-sidecar-commit-bundle.v1"
        assert bundle["actionAuthorized"] is False
        assert bundle["verdict"]["engineBindingsUsed"] == [
            "marlin-agent-core",
            "native-ai-environment",
        ]
        assert "Audit-Receipt:" not in bundle["upstreamCommitMessage"]
        assert ":AITIA_SUPPORT: SWE-146" in bundle["nasaOrgReport"]

        # 7. Verify the sidecar DSSE envelope offline using RFC 0019 `verify_dsse_intoto_envelope`!
        dsse_env = bundle["dsseEnvelope"]
        signer_pks = [s["keyid"].removeprefix("ed25519:") for s in dsse_env["signatures"]]
        sidecar_trust_root = {
            "schema": "lambda-aitia.tuf-trust-root.v1",
            "rootVersion": 1,
            "threshold": 2,
            "minEpoch": 1,
            "authorizedKeys": signer_pks,
            "revokedKeys": [],
        }
        dsse_verdict = json.loads(
            lambda_aitia_rust.verify_dsse_intoto_envelope(
                json.dumps(dsse_env), json.dumps(sidecar_trust_root)
            )
        )
        assert dsse_verdict["verified"] is True
        assert dsse_verdict["bundleDigest"] == bundle["receiptDigest"]
        assert dsse_verdict["actionAuthorized"] is False

        # 8. Commit ONLY clean code + clean upstream message to external repo; archive NASA bundle in Sidecar Vault
        run_git(upstream_repo, "add", "src/token_parser.py")
        run_git(upstream_repo, "commit", "-m", bundle["upstreamCommitMessage"])
        new_sha = run_git(upstream_repo, "rev-parse", "HEAD")
        assert run_git(upstream_repo, "status", "--porcelain") == ""
        assert not (upstream_repo / ".agents").exists()

        vault_entry = sidecar_vault / f"{new_sha[:12]}.nasa-sidecar.json"
        vault_entry.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")

    print(
        json.dumps(
            {
                "example": "06-detached-external-repo-audit",
                "upstreamRepoInitializedWithAitia": False,
                "sanctionedEngineBindings": bundle["verdict"]["engineBindingsUsed"],
                "upstreamPollutionRejected": pollution_rejected,
                "unapprovedCliBindingRejected": rogue_binding_rejected,
                "unaddressedHighFindingRejected": unaddressed_rejected,
                "aiSelfApprovalRejected": self_approve_rejected,
                "staleAiAuditRejected": stale_audit_rejected,
                "lensesCovered": bundle["verdict"]["lensesCovered"],
                "nasaObligationsSupported": bundle["verdict"]["nasaObligationsSupported"],
                "preservedCompetingHypotheses": bundle["verdict"]["preservedCompetingHypothesesCount"],
                "conversationRedactionMode": bundle["verdict"]["conversationRedactionMode"],
                "upstreamHeadline": bundle["upstreamCommitMessage"].splitlines()[0],
                "sidecarDsseVerified": dsse_verdict["verified"],
                "receiptDigest": bundle["receiptDigest"],
                "actionAuthorized": bundle["actionAuthorized"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
