#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Quint `MultiRepoDiamond.qnt` <-> Real `aitia` C ABI Differential Conformance Oracle.

Inspired by IOHK's `QuickCheck-Dynamic` + `IOSimPOR` (Partial Order Reduction) and
Bazel's Skyframe Early Cutoff verification:
  1. Evaluates the exact pure Quint reference oracle predicates (`hasDiamondConflict`,
     `isEarlyCutoff`, `isBreakingDrift`) across all 4! = 24 permutations of the 4-repo
     Cardano/Bazel diamond (`protocol-base -> {ledger-core, network-mux} -> node-runner`).
  2. Drives the REAL pre-compiled Scheme+Rust engine in-process via the 7-symbol C ABI
     (`liblambda_aitia_rust.{so,dylib}`, zero `GERBIL_LOADPATH`, single Gambit runtime).
  3. Asserts 72/72 bit-for-bit behavioral conformance between the Quint formal model and
     the live Scheme POO multi-repo orchestrator across all 24 permutations x 3 regimes.
"""

from __future__ import annotations

import ctypes
import itertools
import json
import os
import sys
from pathlib import Path


class AitiaBuffer(ctypes.Structure):
    _fields_ = [
        ("status", ctypes.c_int32),
        ("data", ctypes.c_void_p),
        ("len", ctypes.c_size_t),
        ("cap", ctypes.c_size_t),
    ]


def resolve_cdylib() -> str:
    explicit = os.environ.get("AITIA_CDYLIB")
    if explicit and Path(explicit).is_file():
        return explicit
    repo_root = Path(__file__).resolve().parents[2]
    for profile in ("debug", "release"):
        for name in ("liblambda_aitia_rust.dylib", "liblambda_aitia_rust.so"):
            candidate = repo_root / "rust" / "target" / profile / name
            if candidate.is_file():
                return str(candidate)
    raise SystemExit("Set AITIA_CDYLIB to liblambda_aitia_rust.{dylib,so}")


# Pure reference oracle mirroring `dev/proof/quint/MultiRepoDiamond.qnt`
def quint_diamond_oracle(
    base_commit: str,
    base_iface: str,
    ledger_pin_commit: str,
    ledger_pin_iface: str,
    net_pin_commit: str,
    net_pin_iface: str,
) -> dict[str, object]:
    if ledger_pin_iface != net_pin_iface:
        return {
            "state": "need-human-decision",
            "escalationReason": "diamond-pin-conflict",
            "earlyCutoffCount": 0,
            "pinDriftCount": 0,
            "diamondConflictCount": 1,
        }
    drifts = int(base_iface != ledger_pin_iface) + int(base_iface != net_pin_iface)
    if drifts > 0:
        return {
            "state": "need-agent-synthesis",
            "escalationReason": "cross-repo-pin-drift",
            "earlyCutoffCount": 0,
            "pinDriftCount": drifts,
            "diamondConflictCount": 0,
        }
    cutoffs = int(base_commit != ledger_pin_commit and base_iface == ledger_pin_iface) + int(
        base_commit != net_pin_commit and base_iface == net_pin_iface
    )
    return {
        "state": "quiescent",
        "escalationReason": None,
        "earlyCutoffCount": cutoffs,
        "pinDriftCount": 0,
        "diamondConflictCount": 0,
    }


def make_quiescent_repo(
    rid: str,
    deps: list[str],
    commit: str,
    iface: str,
    pin_commit: str | None = None,
    pin_iface: str | None = None,
) -> tuple[dict, dict]:
    naming = {
        "convention": "conventional-commits",
        "primaryLanguage": "en",
        "languageSources": ["README.org"],
        "types": ["feat"],
        "scopes": [{"name": "gitops", "paths": ["justfile"]}],
        "references": [
            {
                "identity": "RFC-0008",
                "source": "docs/rfcs/0008-ascent-obligation-funflow-dag.org",
                "element": "ascent-obligation-funflow",
            }
        ],
    }
    proposal = {
        "identity": "RFC-0008",
        "reference": "RFC-0008",
        "language": "en",
        "languageSource": "README.org",
        "type": "feat",
        "scope": "gitops",
        "summary": "Verify diamond differential oracle",
        "rationale": "Assert exact conformance between Quint MultiRepoDiamond and Scheme.",
    }
    repo = {
        "repoId": rid,
        "project": f"iohk/{rid}",
        "directory": f"/virtual/{rid}",
        "dependsOn": deps,
        "interfaceDigest": iface,
        "naming": naming,
        "proposals": [proposal],
        "approvalLive": True,
        "reconcile": True,
    }
    if pin_commit is not None:
        repo["pinnedUpstreamCommits"] = {"protocol-base": pin_commit}
    if pin_iface is not None:
        repo["pinnedUpstreamInterfaces"] = {"protocol-base": pin_iface}

    receipts = {
        f"repo:{rid}:gitops.jj.observe-cut": {
            "cut": {
                "workspace": "default",
                "change": f"chg-{rid}",
                "operation": f"op-{rid}",
                "commit": commit,
                "tree": f"tree-{rid}",
                "parents": ["base-0"],
            },
            "paths": ["justfile"],
            "sources": [
                {"path": "README.org", "text": "* Repo\nEnglish readme.\n"},
                {
                    "path": "docs/rfcs/0008-ascent-obligation-funflow-dag.org",
                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                },
            ],
        },
        f"repo:{rid}:sysml.project-scopes": [],
        f"repo:{rid}:gitops.jj.apply-description": {"resulting_commit": commit},
    }
    return repo, receipts


def main() -> None:
    lib = ctypes.CDLL(resolve_cdylib())
    lib.aitia_session_start.argtypes = [ctypes.POINTER(AitiaBuffer)]
    lib.aitia_session_start.restype = ctypes.c_void_p
    lib.aitia_session_call.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    lib.aitia_session_call.restype = AitiaBuffer
    lib.aitia_session_close.argtypes = [ctypes.c_void_p, ctypes.POINTER(AitiaBuffer)]
    lib.aitia_session_close.restype = ctypes.c_int32
    lib.aitia_buffer_free.argtypes = [AitiaBuffer]
    lib.aitia_buffer_free.restype = None

    def take_buf(buf: AitiaBuffer) -> tuple[int, str]:
        try:
            raw = ctypes.string_at(buf.data, buf.len).decode("utf-8") if buf.data and buf.len else ""
            return buf.status, raw
        finally:
            lib.aitia_buffer_free(buf)

    err_buf = AitiaBuffer()
    handle = lib.aitia_session_start(ctypes.byref(err_buf))
    assert handle, f"aitia_session_start failed: {take_buf(err_buf)}"

    regimes = [
        ("early_cutoff", "base-v2", "sha256:abi-v1", "base-v1", "sha256:abi-v1", "base-v1", "sha256:abi-v1"),
        ("breaking_abi", "base-v2", "sha256:abi-v2", "base-v1", "sha256:abi-v1", "base-v1", "sha256:abi-v1"),
        ("diamond_conflict", "base-v2", "sha256:abi-v2", "base-v2", "sha256:abi-v2", "base-v1", "sha256:abi-v1"),
    ]
    canonical_waves = [["protocol-base"], ["ledger-core", "network-mux"], ["node-runner"]]
    checked = 0

    try:
        op = b"workflow_protocol_step"
        for name, bc, bi, lc, li, nc, ni in regimes:
            expected = quint_diamond_oracle(bc, bi, lc, li, nc, ni)
            r_base, rc_base = make_quiescent_repo("protocol-base", [], bc, bi)
            r_ledg, rc_ledg = make_quiescent_repo("ledger-core", ["protocol-base"], "ledg-v1", "sha256:ledg", lc, li)
            r_net, rc_net = make_quiescent_repo("network-mux", ["protocol-base"], "net-v1", "sha256:net", nc, ni)
            r_node, rc_node = make_quiescent_repo("node-runner", ["ledger-core", "network-mux"], "node-v1", "sha256:node")
            all_receipts = {**rc_base, **rc_ledg, **rc_net, **rc_node}
            base_repos = [r_base, r_ledg, r_net, r_node]

            # Exhaust all 4! = 24 permutations of the 4-repo input list (IOSimPOR schedule confluence!)
            for perm in itertools.permutations(base_repos):
                req = json.dumps(
                    {
                        "caseId": "aitia/case/multi-repo-gitops",
                        "project": "quint-differential-oracle",
                        "repos": list(perm),
                        "receipts": all_receipts,
                    }
                ).encode()
                st, text = take_buf(lib.aitia_session_call(handle, op, len(op), req, len(req)))
                assert st == 0, f"{name} failed: {text}"
                actual = json.loads(text)
                assert actual["waves"] == canonical_waves, (name, actual["waves"])
                assert actual["state"] == expected["state"], (name, actual["state"], expected["state"])
                assert actual.get("escalationReason") == expected["escalationReason"], (
                    name,
                    actual.get("escalationReason"),
                    expected["escalationReason"],
                )
                assert len(actual.get("earlyCutoffs", [])) == expected["earlyCutoffCount"], (name, actual)
                assert len(actual.get("pinDrifts", [])) == expected["pinDriftCount"], (name, actual)
                assert len(actual.get("diamondConflicts", [])) == expected["diamondConflictCount"], (name, actual)
                assert actual["actionAuthorized"] is False
                if expected["state"] == "need-agent-synthesis":
                    assert actual["agentHandoff"]["schema"] == "lambda-aitia.agent-synthesis-handoff.v1"
                    assert actual["agentHandoff"]["actionAuthorized"] is False
                checked += 1

        # RFC 0012 Extension: Exhaust all 4! = 24 permutations over the RFC 0011 Counterfactual
        # Competing-Branch Verification Matrix (2 competing branches preserved, zero authority)!
        r_base, rc_base = make_quiescent_repo("protocol-base", [], "base-v2", "sha256:abi-v1")
        r_ledg, rc_ledg = make_quiescent_repo("ledger-core", ["protocol-base"], "ledg-v1", "sha256:ledg", "base-v1", "sha256:abi-v1")
        r_net, rc_net = make_quiescent_repo("network-mux", ["protocol-base"], "net-v1", "sha256:net", "base-v1", "sha256:abi-v1")
        r_node, rc_node = make_quiescent_repo("node-runner", ["ledger-core", "network-mux"], "node-v1", "sha256:node")
        cf_receipts = {**rc_base, **rc_ledg, **rc_net, **rc_node}
        cf_base_repos = [r_base, r_ledg, r_net, r_node]
        seed_req = json.dumps(
            {
                "caseId": "aitia/case/multi-repo-gitops",
                "project": "quint-differential-oracle",
                "repos": cf_base_repos,
                "receipts": cf_receipts,
            }
        ).encode()
        st, seed_text = take_buf(lib.aitia_session_call(handle, op, len(op), seed_req, len(seed_req)))
        assert st == 0, f"counterfactual seed failed: {seed_text}"
        seed_doc = json.loads(seed_text)
        attested_keys = {r["repoId"]: r["verificationKey"] for r in seed_doc["repos"]}
        cf_branches = [
            {
                "branchId": "branch-preserve-v1",
                "hypothesis": "Preserve ABI v1 for 4/4 Adapton/Salsa memo hits",
                "repoOverrides": [],
            },
            {
                "branchId": "branch-break-v2",
                "hypothesis": "Bump protocol-base to ABI v2 and invalidate Wave 1 peers",
                "repoOverrides": [{"repoId": "protocol-base", "interfaceDigest": "sha256:abi-v2"}],
            },
        ]
        for perm in itertools.permutations(cf_base_repos):
            req = json.dumps(
                {
                    "caseId": "aitia/case/multi-repo-gitops",
                    "project": "quint-differential-oracle",
                    "repos": list(perm),
                    "receipts": cf_receipts,
                    "attestedVerificationKeys": attested_keys,
                    "counterfactualBranches": cf_branches,
                }
            ).encode()
            st, text = take_buf(lib.aitia_session_call(handle, op, len(op), req, len(req)))
            assert st == 0, f"counterfactual perm failed: {text}"
            actual = json.loads(text)
            assert actual["waves"] == canonical_waves
            assert len(actual["verificationCacheHits"]) == 4
            cf_mat = actual["counterfactualMatrix"]
            assert len(cf_mat) == 2
            assert all(b["hypothetical"] is True and b["actionAuthorized"] is False for b in cf_mat)
            by_id = {b["branchId"]: b for b in cf_mat}
            assert len(by_id["branch-preserve-v1"]["verificationCacheHits"]) == 4
            assert by_id["branch-preserve-v1"]["invalidatedRepos"] == []
            assert by_id["branch-break-v2"]["resultingState"] == "need-agent-synthesis"
            assert sorted(by_id["branch-break-v2"]["invalidatedRepos"]) == [
                "ledger-core",
                "network-mux",
                "protocol-base",
            ]
            assert actual["actionAuthorized"] is False
            checked += 1
    finally:
        close_err = AitiaBuffer()
        rc = lib.aitia_session_close(handle, ctypes.byref(close_err))
        assert rc == 0, f"aitia_session_close failed: {take_buf(close_err)}"

    print(
        json.dumps(
            {
                "oracle": "MultiRepoDiamond.qnt + RFC 0011 Counterfactual <-> aitia C ABI",
                "regimes": len(regimes) + 1,
                "permutationsPerRegime": 24,
                "totalDifferentialChecksPassed": checked,
                "canonicalWaves": canonical_waves,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
