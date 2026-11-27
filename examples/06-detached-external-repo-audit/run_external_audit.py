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

        # 3b. RFC 0022: Invoke LIVE linked Scheme/POO `gerbil-ascent` engine via persistent
        #     `Session` (keeps the Gerbil runtime alive across multi-stage audit rounds!).
        session = lambda_aitia_rust.Session()
        try:
            scheme_pre = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": [],
                            "conversationBound": False,
                            "humanApproved": False,
                            "dispositions": [],
                        }
                    )
                )
            )
            assert scheme_pre["schema"] == "lambda-aitia.scheme-ascent-sidecar-assessment.v1"
            assert scheme_pre["admissible"] is False
            assert scheme_pre["actionAuthorized"] is False
            assert scheme_pre["nextHandoffMode"] == "dispatch-ai-audit-lenses"
            assert scheme_pre["missingLenses"] == [
                "api-regression",
                "correctness",
                "nasa-swe146",
                "security",
            ]
            assert scheme_pre["openObligations"] == ["SWE-087", "SWE-146"]
            assert scheme_pre["marlinHandoff"]["boundary"] == "marlin-agent-core"
            assert scheme_pre["ascentDirective"]["engineBinding"] == "native-ai-environment"

            # 4. Run multi-lens audit across the TWO sanctioned AI engine bindings driven by
            #    Scheme ASCENT's derived handoffs:
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

            # 5b. RFC 0023: Deterministic Engineering Formal Library Reuse (`upstream-library-reuse`)
            #     + Project-Specific Ephemeral AI Overlay (`ephemeral-ai-overlay`) + Controls 6–9!
            resolver_digest = sha256_prefixed("de-quint-lean-resolvers-pinned-v1")
            upstream_quint_model = {
                "modelId": "oauth-token-lifecycle",
                "mode": "upstream-library-reuse",
                "libraryPackage": "@deterministic-engineering/quint-models",
                "resolverDigest": resolver_digest,
                "contextDigest": context["contextDigest"],
                "countermodelVerified": True,
                "proofClean": True,
                "passed": True,
                "storedInSidecarVault": True,
            }
            upstream_lean_model = {
                "modelId": "SubprocessEnvScrubAndAuthTiming",
                "mode": "upstream-library-reuse",
                "libraryPackage": "@deterministic-engineering/lean-models",
                "resolverDigest": resolver_digest,
                "contextDigest": context["contextDigest"],
                "countermodelVerified": False,
                "proofClean": True,
                "passed": True,
                "storedInSidecarVault": True,
            }
            ephemeral_ai_overlay = {
                "modelId": "TokenParserTimingOverlay.qnt",
                "mode": "ephemeral-ai-overlay",
                "libraryPackage": "@deterministic-engineering/quint-models",
                "resolverDigest": resolver_digest,
                "contextDigest": context["contextDigest"],
                "countermodelVerified": True,
                "proofClean": True,
                "passed": True,
                "storedInSidecarVault": True,
            }
            essential_guard_probes = [
                {"probeId": "empty-secret-guard", "verdict": "essential"},
            ]

            # Negative Control 6: Vacuous `ephemeral-ai-overlay` missing MR05 @countermodel MUST fail closed!
            vacuous_overlay = dict(ephemeral_ai_overlay, countermodelVerified=False)
            scheme_vacuous = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": ai_reports,
                            "conversationBound": True,
                            "humanApproved": True,
                            "dispositions": human_decision_ok["dispositions"],
                            "formalModels": [vacuous_overlay],
                        }
                    )
                )
            )
            assert scheme_vacuous["admissible"] is False
            assert "de-vacuous-ephemeral-overlay" in scheme_vacuous["blockers"]
            vacuous_overlay_rejected = False
            try:
                lambda_aitia_rust.verify_de_formal_evidence(
                    json.dumps(
                        {
                            "schema": "lambda-aitia.de-formal-evidence.v1",
                            "actionAuthorized": False,
                            "pendingOracles": [],
                            "g2Findings": [],
                            "guardProbes": essential_guard_probes,
                            "formalModels": [vacuous_overlay],
                        }
                    ),
                    context["contextDigest"],
                )
            except ValueError as exc:
                vacuous_overlay_rejected = "MR05 @countermodel" in str(exc)
            assert vacuous_overlay_rejected, "Vacuous ephemeral AI overlay MUST fail closed!"

            # Negative Control 7: DE G2 diff-delta defect + redundant F3 guard-probe MUST fail closed!
            scheme_g2_bad = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": ai_reports,
                            "conversationBound": True,
                            "humanApproved": True,
                            "dispositions": human_decision_ok["dispositions"],
                            "g2Findings": [
                                {
                                    "id": "G2-001",
                                    "rule": "unwrap-or-default-silent-fallback",
                                    "hallucinationClass": "silent-fallback",
                                }
                            ],
                            "guardProbes": [
                                {
                                    "probeId": "redundant-dup-check",
                                    "verdict": "redundant-or-under-modeled",
                                }
                            ],
                        }
                    )
                )
            )
            assert scheme_g2_bad["admissible"] is False
            assert "de-g2-mechanical-defect" in scheme_g2_bad["blockers"]
            assert "de-redundant-guard-probe" in scheme_g2_bad["blockers"]
            g2_defect_rejected = True

            # Negative Control 8: Pending mechanical oracle MUST emit PendingMethod (never silently pass)!
            scheme_pending = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": ai_reports,
                            "conversationBound": True,
                            "humanApproved": True,
                            "dispositions": human_decision_ok["dispositions"],
                            "pendingOracles": ["quint-modules-resolver"],
                        }
                    )
                )
            )
            assert scheme_pending["admissible"] is False
            assert scheme_pending["epistemicStatus"] == "PendingMethod"
            assert "de-pending-mechanical-oracle" in scheme_pending["blockers"]
            pending_oracle_rejected = True

            # Negative Control 9: N-Version disagreement (coordinator claims ADMIT despite ASCENT blocker)!
            scheme_disagree = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": ai_reports,
                            "conversationBound": True,
                            "humanApproved": True,
                            "dispositions": human_decision_ok["dispositions"],
                            "g2Findings": [
                                {
                                    "id": "G2-002",
                                    "rule": "diff-deleted-assertion",
                                    "hallucinationClass": "floor-weakening",
                                }
                            ],
                            "coordinatorClaimedAdmit": True,
                        }
                    )
                )
            )
            assert scheme_disagree["admissible"] is False
            assert scheme_disagree["oracleDisagreement"] is True
            assert "oracle-disagreement-fail-closed" in scheme_disagree["blockers"]
            oracle_disagreement_rejected = True

            # 5c. RFC 0022 + 0023: Re-evaluate via the SAME LIVE linked Scheme/POO `gerbil-ascent`
            #     Session AFTER dual-mode AI audit + BOTH DE formal library reuse & verified ephemeral
            #     AI overlay + redacted conversation + human disposition -> admissible=True, Proven!
            formal_evidence = {
                "schema": "lambda-aitia.de-formal-evidence.v1",
                "actionAuthorized": False,
                "pendingOracles": [],
                "g2Findings": [],
                "guardProbes": essential_guard_probes,
                "formalModels": [
                    upstream_quint_model,
                    upstream_lean_model,
                    ephemeral_ai_overlay,
                ],
            }
            formal_verdict = json.loads(
                lambda_aitia_rust.verify_de_formal_evidence(
                    json.dumps(formal_evidence), context["contextDigest"]
                )
            )
            assert formal_verdict["verified"] is True
            assert formal_verdict["upstreamReuseCount"] == 2
            assert formal_verdict["ephemeralOverlayCount"] == 1
            assert formal_verdict["actionAuthorized"] is False

            scheme_post = json.loads(
                session.sidecar_audit_assess(
                    json.dumps(
                        {
                            "targetRepo": profile["targetRepo"],
                            "nasaProfile": profile["nasaProfile"],
                            "contextDigest": context["contextDigest"],
                            "changedPaths": context["changedFiles"],
                            "forbiddenPrefixes": profile["forbiddenUpstreamPrefixes"],
                            "requiredLenses": profile["requiredAuditLenses"],
                            "aiReports": ai_reports,
                            "conversationBound": True,
                            "humanApproved": True,
                            "dispositions": human_decision_ok["dispositions"],
                            "guardProbes": essential_guard_probes,
                            "formalModels": formal_evidence["formalModels"],
                            "coordinatorClaimedAdmit": True,
                        }
                    )
                )
            )
            assert scheme_post["admissible"] is True, scheme_post
            assert scheme_post["epistemicStatus"] == "Proven"
            assert scheme_post["oracleDisagreement"] is False
            assert scheme_post["blockers"] == []
            assert scheme_post["openObligations"] == []
            assert scheme_post["supportedObligations"] == ["SWE-083", "SWE-084", "SWE-087", "SWE-146"]
            assert scheme_post["admittedFormalModels"] == [
                ["SubprocessEnvScrubAndAuthTiming", "upstream-library-reuse"],
                ["TokenParserTimingOverlay.qnt", "ephemeral-ai-overlay"],
                ["oauth-token-lifecycle", "upstream-library-reuse"],
            ]
            assert scheme_post["nextHandoffMode"] == "ready-for-sidecar-commit"
            assert scheme_post["actionAuthorized"] is False
        finally:
            session.close()

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
                    "formalEvidence": formal_evidence,
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
                "schemeAscentPreOpenObligations": scheme_pre["openObligations"],
                "schemeAscentPostAdmissible": scheme_post["admissible"],
                "schemeAscentPostSupportedObligations": scheme_post["supportedObligations"],
                "sanctionedEngineBindings": bundle["verdict"]["engineBindingsUsed"],
                "upstreamPollutionRejected": pollution_rejected,
                "unapprovedCliBindingRejected": rogue_binding_rejected,
                "unaddressedHighFindingRejected": unaddressed_rejected,
                "aiSelfApprovalRejected": self_approve_rejected,
                "staleAiAuditRejected": stale_audit_rejected,
                "vacuousEphemeralOverlayRejected": vacuous_overlay_rejected,
                "g2DefectAndRedundantProbeRejected": g2_defect_rejected,
                "pendingOracleRejected": pending_oracle_rejected,
                "oracleDisagreementRejected": oracle_disagreement_rejected,
                "admittedFormalModels": scheme_post["admittedFormalModels"],
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
