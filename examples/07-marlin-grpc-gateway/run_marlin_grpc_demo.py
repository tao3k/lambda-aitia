#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""RFC 0024 live example: Process-Isolated Marlin gRPC Sidecar Gateway (`aitia serve-marlin-grpc`).

Proves that `marlin-agent-core` Gateway can invoke `lambda-aitia`'s persistent Scheme
`gerbil-ascent` session, Deterministic Engineering formal library + ephemeral overlay
verification, and NASA Sidecar DSSE receipt generation over gRPC — with ZERO dual Gambit
runtime collision, ZERO Rust crate splitting, and full DE SM24/SM25/SM26 hardening:
  1. Non-loopback bind without Bearer token refused fail-closed at startup.
  2. Non-loopback bind with insecure default dev token refused fail-closed at startup.
  3. Missing Authorization / empty `"Bearer   "` / wrong token rejected with grpc-status 16.
  4. Live Health, CaptureDetachedContext, multi-call persistent Scheme AssessSidecarAuditAscent,
     VerifyFormalEvidence (positive + vacuous ephemeral overlay negative control), and
     BuildNasaSidecarReceipt RPCs succeed over wire-level length-prefixed gRPC frames.
  5. Live TripEmergencyStop blocks subsequent audit/receipt RPCs with grpc-status 9
     (FAILED_PRECONDITION) while Health remains observable with `estopActive: true`.
"""

from __future__ import annotations

import hashlib
import http.client
import json
import os
import pathlib
import struct
import subprocess
import tempfile
from typing import Any


SERVICE_PREFIX = "/aitia.marlin.v1.AitiaSidecarGateway/"


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


def grpc_call(
    host: str,
    port: int,
    method: str,
    payload: dict[str, Any],
    auth_header: str | None = None,
) -> tuple[int, str, dict[str, Any]]:
    raw_json = json.dumps(payload).encode("utf-8")
    frame = b"\x00" + struct.pack(">I", len(raw_json)) + raw_json
    headers = {
        "Content-Type": "application/grpc+json",
        "Content-Length": str(len(frame)),
    }
    if auth_header is not None:
        headers["Authorization"] = auth_header

    conn = http.client.HTTPConnection(host, port, timeout=15)
    try:
        conn.request("POST", f"{SERVICE_PREFIX}{method}", body=frame, headers=headers)
        resp = conn.getresponse()
        body = resp.read()
        grpc_status = int(resp.getheader("grpc-status", "-1"))
        grpc_msg = resp.getheader("grpc-message", "")
        assert len(body) >= 5 and body[0] == 0, f"Malformed gRPC response frame: {body!r}"
        declared_len = struct.unpack(">I", body[1:5])[0]
        assert declared_len == len(body) - 5
        decoded = json.loads(body[5:].decode("utf-8"))
        return grpc_status, grpc_msg, decoded
    finally:
        conn.close()


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

    # SM26 Negative Control 1: Non-loopback bind without Bearer token MUST refuse startup!
    no_tok = subprocess.run(
        [cli, "serve-marlin-grpc", "--bind", "0.0.0.0:0"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert no_tok.returncode != 0 and "SM26 fail-closed" in (no_tok.stderr + no_tok.stdout)

    # SM26 Negative Control 2: Non-loopback bind with default dev token MUST refuse startup!
    dev_tok = subprocess.run(
        [cli, "serve-marlin-grpc", "--bind", "0.0.0.0:0", "--bearer-token", "dev"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert dev_tok.returncode != 0 and "default dev token" in (dev_tok.stderr + dev_tok.stdout)

    bearer = "marlin-prod-ephemeral-token-9f81c2"
    auth = f"Bearer {bearer}"

    with tempfile.TemporaryDirectory() as tmp:
        upstream_repo = pathlib.Path(tmp) / "external-repo"
        upstream_repo.mkdir()
        run_git(upstream_repo, "init", "-b", "main")
        run_git(upstream_repo, "config", "user.name", "Marlin Gateway User")
        run_git(upstream_repo, "config", "user.email", "marlin@example.org")
        (upstream_repo / "app.py").write_text("def check(a, b):\n    return a == b\n", encoding="utf-8")
        run_git(upstream_repo, "add", ".")
        run_git(upstream_repo, "commit", "-m", "chore: baseline")
        (upstream_repo / "app.py").write_text(
            "import hmac\ndef check(a, b):\n    return bool(a and b) and hmac.compare_digest(a, b)\n",
            encoding="utf-8",
        )

        # Spawn process-isolated `aitia serve-marlin-grpc` with bounded max-requests
        proc = subprocess.Popen(
            [
                cli,
                "serve-marlin-grpc",
                "--bind",
                "127.0.0.1:0",
                "--bearer-token",
                bearer,
                "--max-requests",
                "12",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            assert proc.stdout is not None
            ready_line = proc.stdout.readline().strip()
            ready = json.loads(ready_line)
            assert ready["schema"] == "lambda-aitia.marlin-grpc-ready.v1"
            assert ready["loopbackOnly"] is True
            assert ready["authRequired"] is True
            assert ready["actionAuthorized"] is False
            host, port_str = ready["listenAddr"].rsplit(":", 1)
            port = int(port_str)

            # 1-3: Auth Negative Controls (missing, blank "Bearer   ", wrong token)
            s_missing, _, _ = grpc_call(host, port, "Health", {}, auth_header=None)
            assert s_missing == 16
            s_blank, _, _ = grpc_call(host, port, "Health", {}, auth_header="Bearer    ")
            assert s_blank == 16
            s_wrong, _, _ = grpc_call(host, port, "Health", {}, auth_header="Bearer wrong-secret")
            assert s_wrong == 16

            # 4: Live Health RPC
            s_health, _, health = grpc_call(host, port, "Health", {}, auth_header=auth)
            assert s_health == 0
            assert health["status"] == "SERVING"
            assert health["estopActive"] is False
            assert health["actionAuthorized"] is False

            # 5: CaptureDetachedContext RPC over external uninitialized Git repo
            profile = {
                "schema": "lambda-aitia.sidecar-profile.v1",
                "targetRepo": "external-org/app",
                "nasaProfile": "nasa/sdlc/npr-7150.2d",
                "requiredAuditLenses": ["correctness", "security"],
                "forbiddenUpstreamPrefixes": [".agents/aita/", ".aitia/"],
                "commitConvention": "conventional-commits",
                "allowAuditTrailer": False,
                "epoch": 1,
            }
            s_cap, _, ctx = grpc_call(
                host,
                port,
                "CaptureDetachedContext",
                {
                    "repoDir": str(upstream_repo),
                    "baseRef": "HEAD",
                    "profileJson": json.dumps(profile),
                    "deterministicChecksJson": "[]",
                },
                auth_header=auth,
            )
            assert s_cap == 0
            assert ctx["upstreamPollutionFree"] is True
            assert ctx["actionAuthorized"] is False
            ctx_digest = ctx["contextDigest"]

            # 6: AssessSidecarAuditAscent #1 (Pre-audit via persistent AitiaSession)
            s_pre, _, pre = grpc_call(
                host,
                port,
                "AssessSidecarAuditAscent",
                {
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
                auth_header=auth,
            )
            assert s_pre == 0
            assert pre["admissible"] is False
            assert pre["openObligations"] == ["SWE-087", "SWE-146"]
            assert pre["formalLibraryGuidance"]["generalCaseMode"] == "upstream-library-reuse"
            assert pre["formalLibraryGuidance"]["specialCaseMode"] == "ephemeral-ai-overlay"

            # 7: VerifyFormalEvidence Negative Control (vacuous ephemeral overlay without @countermodel)
            resolver_digest = sha256_prefixed("de-resolver-v1")
            vacuous_fe = {
                "schema": "lambda-aitia.de-formal-evidence.v1",
                "actionAuthorized": False,
                "pendingOracles": [],
                "g2Findings": [],
                "guardProbes": [],
                "formalModels": [
                    {
                        "modelId": "AppOverlay.qnt",
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
            s_vac, _, vac_body = grpc_call(
                host,
                port,
                "VerifyFormalEvidence",
                {
                    "formalEvidenceJson": json.dumps(vacuous_fe),
                    "expectedContextDigest": ctx_digest,
                },
                auth_header=auth,
            )
            assert s_vac == 3 and "MR05 @countermodel" in vac_body["error"]

            # 8: AssessSidecarAuditAscent #2 (SAME persistent AitiaSession -> Proven!)
            ai_reports = [
                {
                    "schema": "lambda-aitia.ai-audit-report.v1",
                    "engineBinding": "marlin-agent-core",
                    "provider": "marlin-agent-core",
                    "modelId": "marlin-gateway-auditor-v1",
                    "promptTemplateDigest": sha256_prefixed("marlin-prompt-1"),
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
            formal_models = [
                {
                    "modelId": "SubprocessEnvScrubAndAuthTiming",
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
                    "modelId": "AppOverlay.qnt",
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
            s_post, _, post = grpc_call(
                host,
                port,
                "AssessSidecarAuditAscent",
                {
                    "targetRepo": profile["targetRepo"],
                    "nasaProfile": profile["nasaProfile"],
                    "contextDigest": ctx_digest,
                    "changedPaths": ctx["changedFiles"],
                    "requiredLenses": profile["requiredAuditLenses"],
                    "aiReports": ai_reports,
                    "conversationBound": True,
                    "humanApproved": True,
                    "dispositions": [],
                    "guardProbes": [{"probeId": "empty-check-guard", "verdict": "essential"}],
                    "formalModels": formal_models,
                    "coordinatorClaimedAdmit": True,
                },
                auth_header=auth,
            )
            assert s_post == 0
            assert post["admissible"] is True
            assert post["epistemicStatus"] == "Proven"
            assert post["actionAuthorized"] is False

            # 9: BuildNasaSidecarReceipt RPC over gRPC
            conversation = {
                "schema": "lambda-aitia.conversation-transcript.v1",
                "contextDigest": ctx_digest,
                "redactionMode": "redacted-summary",
                "turns": [
                    {
                        "turnId": 1,
                        "role": "human",
                        "summary": "Audit constant-time comparison via Marlin gRPC gateway.",
                        "contentDigest": sha256_prefixed("marlin-turn-1"),
                    }
                ],
                "actionAuthorized": False,
            }
            conv_digest = sha256_prefixed(json.dumps(conversation, sort_keys=True, separators=(",", ":")))
            human_decision = {
                "schema": "lambda-aitia.human-audit-decision.v1",
                "contextDigest": ctx_digest,
                "conversationDigest": conv_digest,
                "reviewerId": "maintainer@hardenedlinux.org",
                "decision": "approve-commit",
                "dispositions": [],
                "actionAuthorized": False,
            }
            formal_evidence_ok = {
                "schema": "lambda-aitia.de-formal-evidence.v1",
                "actionAuthorized": False,
                "pendingOracles": [],
                "g2Findings": [],
                "guardProbes": [{"probeId": "empty-check-guard", "verdict": "essential"}],
                "formalModels": formal_models,
            }
            s_rcpt, _, receipt = grpc_call(
                host,
                port,
                "BuildNasaSidecarReceipt",
                {
                    "context": ctx,
                    "aiReports": ai_reports,
                    "conversation": conversation,
                    "humanDecision": human_decision,
                    "profile": profile,
                    "formalEvidence": formal_evidence_ok,
                    "commitProposal": {
                        "type": "fix",
                        "scope": "auth",
                        "summary": "use constant-time compare_digest via marlin gateway",
                    },
                    "signingSeeds": ["81" * 32, "82" * 32],
                },
                auth_header=auth,
            )
            assert s_rcpt == 0
            assert receipt["schema"] == "lambda-aitia.nasa-sidecar-commit-bundle.v1"
            assert receipt["actionAuthorized"] is False
            assert "Deterministic Engineering Formal Verification (RFC 0023)" in receipt["nasaOrgReport"]

            # 10-12: SM26 Operator E-Stop confinement
            s_trip, _, tripped = grpc_call(
                host, port, "TripEmergencyStop", {"operatorId": "sec-ops"}, auth_header=auth
            )
            assert s_trip == 0 and tripped["estopActive"] is True

            s_blocked, _, blocked = grpc_call(
                host, port, "AssessSidecarAuditAscent", {"targetRepo": "x"}, auth_header=auth
            )
            assert s_blocked == 9 and blocked["estopActive"] is True

            s_health2, _, health2 = grpc_call(host, port, "Health", {}, auth_header=auth)
            assert s_health2 == 0 and health2["estopActive"] is True

            proc.wait(timeout=10)
            assert proc.returncode == 0
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)

    print(
        json.dumps(
            {
                "example": "07-marlin-grpc-gateway",
                "service": "aitia.marlin.v1.AitiaSidecarGateway",
                "nonLoopbackNoTokenRefused": True,
                "nonLoopbackDevTokenRefused": True,
                "blankAndInvalidBearerRejected": True,
                "persistentSessionMultiCallProven": True,
                "vacuousOverlayRejectedOverGrpc": True,
                "nasaDsseReceiptIssuedOverGrpc": True,
                "operatorEstopBlockedRpcStatus": 9,
                "receiptDigest": receipt["receiptDigest"],
                "actionAuthorized": False,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
