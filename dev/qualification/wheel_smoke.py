# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Exercise the installed PyO3 extension against the linked Scheme program."""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory

from lambda_aitia_rust import (
    OrgEdit,
    OrgEditReview,
    Session,
    capture_source_tree,
    dispatch_host_frames,
    host_capabilities,
    run_frozen_pytest,
)

caps = json.loads(host_capabilities())
assert caps["schema"] == "lambda-aitia.host-capabilities.v1"
assert caps["actionAuthorized"] is False
cap_names = {entry["capability"] for entry in caps["capabilities"]}
assert "gitops.jj.push-reviewed" in cap_names
assert "gitops.jj.prepare-description" in cap_names
assert "gitops.jj.apply-description" in cap_names
assert "python.observe-pytest" in cap_names
assert len(cap_names) == 12

# Fail-closed check: dispatching a fenced-effect frame without a fenceToken MUST raise RuntimeError
try:
    dispatch_host_frames(
        json.dumps(
            [
                {
                    "capability": "gitops.jj.push-reviewed",
                    "effectClass": "fenced-effect",
                    "receiptKey": "gitops.jj.push-reviewed",
                    "payload": {},
                }
            ]
        )
    )
except RuntimeError:
    pass
else:
    raise AssertionError("dispatch_host_frames accepted an unfenced FencedEffect frame")


with TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "a").mkdir()
    (root / "a" / "z").write_bytes(b"\0")
    (root / "a-").write_bytes(b"two")
    expected = (
        b"lambda-aitia.source-tree.v1\0\0\0\0\0\0\0\0\x02"
        b"\0\0\0\x02a-\0\0\0\0\0\0\0\x03two"
        b"\0\0\0\x03a/z\0\0\0\0\0\0\0\x01\0"
    )
    assert capture_source_tree(root) == expected
    (root / "escape").symlink_to(root.parent)
    try:
        capture_source_tree(root)
    except OSError:
        pass
    else:
        raise AssertionError("source capture followed a directory symlink")

with TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "test_frozen.py").write_text(
        "def test_frozen():\n    assert open('input.txt').read() == 'frozen'\n"
        "def test_changed():\n"
        "    open('input.txt', 'w').write('mutated')\n"
        "    assert False\n",
        encoding="utf-8",
    )
    (root / "input.txt").write_text("frozen", encoding="utf-8")
    snapshot = capture_source_tree(root)
    (root / "input.txt").write_text("edited", encoding="utf-8")
    try:
        run_frozen_pytest(Path(sys.executable), snapshot, ["../test_frozen.py"])
    except OSError:
        pass
    else:
        raise AssertionError("frozen replay accepted an escaping selector")

    if len(sys.argv) == 2:
        observation = run_frozen_pytest(
            Path(sys.argv[1]), snapshot, ["test_frozen.py::test_frozen"]
        )
        assert observation["outcome"] == "exited"
        assert observation["verdict"] == "passed"
        assert observation["exit_code"] == 0, observation["output_tail"]
        assert observation["source_unchanged"] is True
        source_sha256 = "sha256:" + hashlib.sha256(snapshot).hexdigest()
        assert observation["source_sha256"] == source_sha256
        assert observation["observed_source_sha256"] == source_sha256
        assert observation["selectors"] == ["test_frozen.py::test_frozen"]
        report = observation["report"]
        assert report["sha256"].startswith("sha256:")
        assert (report["passed"], report["failed"], report["skipped"]) == (1, 0, 0)
        changed = run_frozen_pytest(
            Path(sys.argv[1]), snapshot, ["test_frozen.py::test_changed"]
        )
        assert changed["outcome"] == "exited"
        assert changed["verdict"] == "source-changed"
        assert changed["exit_code"] == 1, changed["output_tail"]
        assert changed["source_unchanged"] is False
        assert changed["source_sha256"] == source_sha256
        assert changed["observed_source_sha256"] != source_sha256
        assert changed["observed_source_sha256"].startswith("sha256:")
        assert changed["report"]["passed"] == 0
        assert changed["report"]["failed"] == 1
        assert (root / "input.txt").read_text(encoding="utf-8") == "edited"

source = "* α\n* B\n".encode()
digest = "sha256:" + hashlib.sha256(source).hexdigest()
first = OrgEdit("first", 2, 4, "α", "Alpha")
second = OrgEdit("second", 7, 8, "B", "Beta")
review = OrgEditReview("document", source, digest, [second, first])
assert review.source_id == "document"
assert review.source_sha256 == digest
assert [(edit.node_id, edit.start_byte, edit.end_byte, edit.expected, edit.replacement)
        for edit in review.edits] == [
    ("first", 2, 4, "α", "Alpha"),
    ("second", 7, 8, "B", "Beta"),
]
assert review.source_current(source)
assert not review.source_current("* α\n* C\n".encode())

for stale_source, edits in [
    ("* α\n* C\n".encode(), [second]),
    (source, [OrgEdit("split", 3, 4, "α", "Alpha")]),
    (source, [first, OrgEdit("overlap", 2, 5, "α\n", "Alpha")]),
]:
    try:
        OrgEditReview("document", stale_source, digest, edits)
    except OSError:
        pass
    else:
        raise AssertionError("ORG review accepted stale or ambiguous bytes")

session = Session()
try:
    with ThreadPoolExecutor(max_workers=1) as callers:
        payload = callers.submit(session.flow_graph, '{"lifecycle-id":"wheel/42"}').result()
    graph = json.loads(payload)
    assert graph["schema"] == "lambda-aitia.sdlc-flow-graph"
    assert len(graph["nodes"]) == 8
    assert len(graph["edges"]) == 7
    assert graph["edges"][-1]["to"] == "wheel/42/effect"
    assert graph["releaseAuthorized"] is False
    assert graph["runtimeExecuted"] is False
    assert graph["lifecycleId"] == "wheel/42"

    change = {
        "event": "pull-request",
        "repository": "tao3k/agentic-ai-lab",
        "revision": "0123456789abcdef",
        "source-ref": "feature/aitia",
        "target-ref": "develop",
        "pull-request": 42,
        "checks": [],
    }
    decision = json.loads(session.gitops_evaluate(json.dumps(change)))
    assert decision["accepted"] is False
    assert "nasa/sdlc/npr-7150.2" in decision["missingChecks"]
    assert decision["runtimeExecuted"] is False

    nasa_check = {
        "name": "nasa/sdlc/npr-7150.2",
        "conclusion": "success",
        "standardEdition": "D",
        "sourceLockDigest": "sha256:68113744771506840ed6d7abb4873f87fc6b490d405b9637d446ba4b2ba39108",
    }
    change["checks"] = [
        {"name": name, "conclusion": "success"}
        for name in ("commit-policy", "build", "unit-test")
    ] + [nasa_check]
    accepted = json.loads(session.gitops_evaluate(json.dumps(change)))
    assert accepted["accepted"] is True
    assert accepted["profile"] == "dev"
    assert accepted["releaseAuthorized"] is False
    assert accepted["runtimeExecuted"] is False

    nasa_check["sourceLockDigest"] = "sha256:cfb963b8cd81fd8e22e9b47251c1dc7927b85fcdf9ec9366057cd38cb94f338c"
    rejected = json.loads(session.gitops_evaluate(json.dumps(change)))
    assert rejected["accepted"] is False
    assert rejected["staleChecks"] == ["nasa/sdlc/npr-7150.2"]
    assert rejected["releaseAuthorized"] is False
    assert rejected["runtimeExecuted"] is False

    contract = {
        "rows": [
            {"id": 0, "parentId": -1, "kind": "org-data", "fieldName": "", "fieldValue": ""},
            {"id": 1, "parentId": 0, "kind": "headline", "fieldName": "title", "fieldValue": "Evidence"},
        ],
        "scopeId": 0,
        "queryKind": "headline",
        "fieldName": "title",
        "fieldValue": "Evidence",
        "expectation": "exactly",
        "expectedCount": 1,
    }
    matched = json.loads(session.org_contract_evaluate(json.dumps(contract)))
    assert matched == {"matchedCount": 1, "passed": True}
    missing = json.loads(
        session.org_contract_evaluate(json.dumps(dict(contract, fieldValue="Missing")))
    )
    assert missing == {"matchedCount": 0, "passed": False}

    kind_only = dict(contract, fieldName="", fieldValue="", expectation="at-least")
    assert json.loads(session.org_contract_evaluate(json.dumps(kind_only))) == matched
    at_most_zero = dict(contract, expectation="at-most", expectedCount=0)
    assert json.loads(session.org_contract_evaluate(json.dumps(at_most_zero))) == {
        "matchedCount": 1,
        "passed": False,
    }

    for invalid in (
        dict(contract, queryKind="head\0line"),
        dict(contract, expectation="unsupported"),
        dict(contract, rows=[dict(contract["rows"][0], id=-1)]),
    ):
        try:
            session.org_contract_evaluate(json.dumps(invalid))
        except RuntimeError:
            pass
        else:
            raise AssertionError("Orgize transport accepted an invalid request")
    assert json.loads(session.org_contract_evaluate(json.dumps(contract))) == matched

    protocol_naming = {
        "projectKey": "AITIA",
        "primaryLanguage": "en",
        "languageSources": ["README.md"],
        "types": ["feat"],
        "references": [
            {
                "identity": "RFC-0008",
                "source": "docs/rfcs/0008.org",
                "element": "ascent-obligation-funflow",
            }
        ],
    }
    step1 = json.loads(
        session.workflow_protocol_step(
            json.dumps(
                {
                    "caseId": "aitia/case/gitops-commit",
                    "project": "lambda-aitia",
                    "directory": ".",
                    "requestedPaths": ["README.md", "docs/rfcs/0008.org"],
                    "modelCheckEnabled": True,
                    "naming": protocol_naming,
                    "receipts": {},
                }
            )
        )
    )
    assert step1["schema"] == "lambda-aitia.workflow-protocol-step.v1"
    assert step1["state"] == "need-host-frames"
    assert {frame["capability"] for frame in step1["frames"]} == {
        "gitops.jj.observe-cut",
        "sysml.project-scopes",
    }
    assert step1["actionAuthorized"] is False
    step2 = json.loads(
        session.workflow_protocol_step(
            json.dumps(
                {
                    "caseId": "aitia/case/gitops-commit",
                    "project": "lambda-aitia",
                    "directory": ".",
                    "naming": protocol_naming,
                    "receipts": {
                        "gitops.jj.observe-cut": {
                            "cut": {
                                "workspace": "default",
                                "change": "kxy",
                                "operation": "op1",
                                "commit": "abc123",
                                "tree": "tree123",
                                "parents": ["p0"],
                            },
                            "paths": ["modules/workflow/reconcile.ss"],
                            "sources": [
                                {"path": "README.md", "text": "English readme.\n"},
                                {
                                    "path": "docs/rfcs/0008.org",
                                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                                },
                            ],
                        },
                        "sysml.project-scopes": [
                            {"name": "gitops", "paths": ["modules/workflow"]}
                        ],
                    },
                    "proposals": [
                        {
                            "identity": "AITIA-RFC-0008",
                            "reference": "RFC-0008",
                            "language": "en",
                            "languageSource": "README.md",
                            "type": "feat",
                            "scope": "gitops",
                            "summary": "Verify wheel protocol parity",
                            "rationale": "Exercise workflow_protocol_step from Python Session.",
                        }
                    ],
                    "approvalLive": False,
                    "reconcile": True,
                }
            )
        )
    )
    assert step2["state"] == "need-human-decision"
    assert step2["handoffTarget"] == "human-decision"
    assert step2["gapKind"] == "requirement-gap"
    assert step2["profile"] == "lambda-aitia/sdlc"
    assert step2["reconciliation"]["choiceStatus"] == "unique-deduction"
    assert step2["reconciliation"]["choiceWorldCount"] == 1
    assert step2["actionAuthorized"] is False

    # Multi-profile SDLC lifecycle protocol from Python Session
    sdlc_step = json.loads(
        session.workflow_protocol_step(
            json.dumps(
                {
                    "caseId": "aitia/case/sdlc-lifecycle",
                    "project": "lambda-aitia",
                    "profile": "lambda-aitia/sdlc/open-security",
                    "changeId": "change:wheel-sec-1",
                    "designAlternatives": ["design-zero-trust"],
                    "verified": True,
                    "observedObligations": ["sec.sbom-provenance"],
                    "repairRound": 1,
                    "maxRepairRounds": 3,
                }
            )
        )
    )
    assert sdlc_step["profile"] == "lambda-aitia/sdlc/open-security"
    assert sdlc_step["state"] == "need-agent-synthesis"
    assert len(sdlc_step["repairTasks"]) == 2
    assert sdlc_step["actionAuthorized"] is False

    # Multi-repo GitOps orchestration inside the SAME live Python Session:
    # 1) Dependency cycle fails closed
    cycle_res = json.loads(
        session.drive_multi_repo_protocol(
            json.dumps(
                {
                    "repos": [
                        {"repoId": "repo-a", "dependsOn": ["repo-b"]},
                        {"repoId": "repo-b", "dependsOn": ["repo-a"]},
                    ]
                }
            )
        )
    )
    assert cycle_res["state"] == "need-human-decision"
    assert cycle_res["escalationReason"] == "dependency-cycle"
    assert cycle_res["actionAuthorized"] is False

    # 2) Cross-repo pin drift emits localized Schwarz repairTask preserving unaffected upstream
    drift_res = json.loads(
        session.workflow_protocol_step(
            json.dumps(
                {
                    "caseId": "aitia/case/multi-repo-gitops",
                    "project": "multi-repo-wheel",
                    "receipts": {
                        "repo:core:gitops.jj.observe-cut": {
                            "cut": {
                                "workspace": "default",
                                "change": "c1",
                                "operation": "op1",
                                "commit": "core-new-sha",
                                "tree": "t1",
                                "parents": ["p0"],
                            },
                            "paths": ["modules/workflow/reconcile.ss"],
                            "sources": [
                                {"path": "README.md", "text": "English readme.\n"},
                                {
                                    "path": "docs/rfcs/0008.org",
                                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                                },
                            ],
                        },
                        "repo:core:sysml.project-scopes": [
                            {"name": "gitops", "paths": ["modules/workflow"]}
                        ],
                        "repo:app:gitops.jj.observe-cut": {
                            "cut": {
                                "workspace": "default",
                                "change": "a1",
                                "operation": "op2",
                                "commit": "app-sha-1",
                                "tree": "t2",
                                "parents": ["p1"],
                            },
                            "paths": ["modules/workflow/reconcile.ss"],
                            "sources": [
                                {"path": "README.md", "text": "English readme.\n"},
                                {
                                    "path": "docs/rfcs/0008.org",
                                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                                },
                            ],
                        },
                        "repo:app:sysml.project-scopes": [
                            {"name": "gitops", "paths": ["modules/workflow"]}
                        ],
                    },
                    "repos": [
                        {
                            "repoId": "core",
                            "directory": ".",
                            "dependsOn": [],
                            "naming": protocol_naming,
                            "proposals": [
                                {
                                    "identity": "AITIA-RFC-0008",
                                    "reference": "RFC-0008",
                                    "language": "en",
                                    "languageSource": "README.md",
                                    "type": "feat",
                                    "scope": "gitops",
                                    "summary": "Core upstream change",
                                    "rationale": "Upstream repo.",
                                }
                            ],
                            "approvalLive": True,
                        },
                        {
                            "repoId": "app",
                            "directory": ".",
                            "dependsOn": ["core"],
                            "pinnedUpstreamCommits": {"core": "core-stale-sha"},
                            "naming": protocol_naming,
                            "proposals": [
                                {
                                    "identity": "AITIA-RFC-0008",
                                    "reference": "RFC-0008",
                                    "language": "en",
                                    "languageSource": "README.md",
                                    "type": "feat",
                                    "scope": "gitops",
                                    "summary": "Downstream app change",
                                    "rationale": "Downstream repo.",
                                }
                            ],
                            "approvalLive": True,
                        },
                    ],
                }
            )
        )
    )
    assert drift_res["state"] == "need-agent-synthesis"
    assert drift_res["escalationReason"] == "cross-repo-pin-drift"
    assert drift_res["waves"] == [["core"], ["app"]]
    assert len(drift_res["pinDrifts"]) == 1
    assert drift_res["repairTasks"][0]["recomputeScope"] == "cross-repo-pin-drift"
    assert drift_res["repairTasks"][0]["preservedSupportedObligations"] == ["core"]
    assert drift_res["actionAuthorized"] is False

    # 3) Session.__enter__ returns the live session, and drive_protocol executes against a real JJ workspace when jj is available
    assert session.__enter__() is session
    jj_bin = os.environ.get("AITIA_JJ_BIN") or shutil.which("jj")
    if jj_bin:
        with tempfile.TemporaryDirectory() as jj_tmp:
            jj_root = Path(jj_tmp)
            env_jj = dict(os.environ, AITIA_JJ_BIN=jj_bin)
            os.environ["AITIA_JJ_BIN"] = jj_bin
            for jj_args in (
                ["git", "init", "--colocate"],
                ["describe", "-m", "wheel smoke base"],
            ):
                subprocess.run(
                    [
                        jj_bin,
                        "--config",
                        "user.name='Wheel Smoke'",
                        "--config",
                        "user.email='wheel@example.invalid'",
                        *jj_args,
                    ],
                    cwd=jj_root,
                    env=env_jj,
                    check=True,
                    capture_output=True,
                )
            (jj_root / ".agents" / "aita").mkdir(parents=True)
            (jj_root / "src").mkdir(parents=True)
            (jj_root / ".agents" / "aita" / "project.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "programs": {
                            "jj": {
                                "enable": True,
                                "settings": {
                                    "project": "wheel-py-core",
                                    "profile": "lambda-aitia/sdlc",
                                    "primary": "sdlc.config-audit",
                                    "checks": [
                                        {
                                            "requirement": "sdlc.change-record",
                                            "method": "jj.recorded-change",
                                        },
                                        {
                                            "requirement": "sdlc.config-audit",
                                            "method": "jj.configuration-audit",
                                        },
                                    ],
                                    "naming": {
                                        "projectKey": "PY",
                                        "primaryLanguage": "en",
                                        "languageSources": ["README.org"],
                                        "types": ["feat"],
                                        "scopes": [
                                            {
                                                "name": "core",
                                                "paths": [
                                                    "src",
                                                    ".agents/aita",
                                                    "README.org",
                                                    "work.org",
                                                ],
                                            }
                                        ],
                                        "references": [
                                            {
                                                "identity": "RFC-1",
                                                "source": "work.org",
                                                "element": "work1",
                                            }
                                        ],
                                    },
                                },
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            (jj_root / "README.org").write_text("* Wheel Core\nEnglish readme.\n", encoding="utf-8")
            (jj_root / "work.org").write_text(
                "* RFC-1\n:PROPERTIES:\n:ID: work1\n:ENGINEERING_ID: RFC-1\n:END:\n",
                encoding="utf-8",
            )
            (jj_root / "src" / "app.py").write_text("def main():\n    return 0\n", encoding="utf-8")
            subprocess.run(
                [
                    jj_bin,
                    "--config",
                    "user.name='Wheel Smoke'",
                    "--config",
                    "user.email='wheel@example.invalid'",
                    "describe",
                    "-m",
                    "wheel smoke candidate",
                ],
                cwd=jj_root,
                env=env_jj,
                check=True,
                capture_output=True,
            )
            py_proto = json.loads(session.drive_protocol(str(jj_root)))
            assert py_proto["profile"] == "lambda-aitia/sdlc"
            assert py_proto["state"] == "need-agent-synthesis"
            assert py_proto["handoffTarget"] == "agent-synthesis"
            assert py_proto["actionAuthorized"] is False
            assert len(py_proto["repairTasks"]) >= 1
finally:
    session.__exit__(None, None, None)

try:
    session.flow_graph('{"lifecycle-id":"wheel/42"}')
except RuntimeError:
    pass
else:
    raise AssertionError("closed Rust session accepted a request")

# Exercise the ultra-thin C ABI exported by the exact same pre-compiled cdylib in a fresh
# subprocess using pure `ctypes` (no PyO3 import, zero GERBIL_LOADPATH).
import lambda_aitia_rust as _aitia_mod

c_abi_script = r"""
import ctypes, json, sys

class AitiaBuffer(ctypes.Structure):
    _fields_ = [
        ("status", ctypes.c_int32),
        ("data", ctypes.c_void_p),
        ("len", ctypes.c_size_t),
        ("cap", ctypes.c_size_t),
    ]

lib = ctypes.CDLL(sys.argv[1])
lib.aitia_abi_version.restype = ctypes.c_uint32
lib.aitia_host_capabilities.restype = AitiaBuffer
lib.aitia_dispatch_host_frames.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
lib.aitia_dispatch_host_frames.restype = AitiaBuffer
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

def take_buf(buf):
    try:
        raw = ctypes.string_at(buf.data, buf.len).decode("utf-8") if buf.data and buf.len else ""
        return buf.status, raw
    finally:
        lib.aitia_buffer_free(buf)

assert lib.aitia_abi_version() == 1

st, text = take_buf(lib.aitia_host_capabilities())
assert st == 0, text
caps = json.loads(text)
assert caps["actionAuthorized"] is False
cap_ids = {c["capability"] for c in caps["capabilities"]}
assert len(cap_ids) == 12
assert "python.observe-pytest" in cap_ids
assert "gitops.jj.push-reviewed" in cap_ids

bad_frame = json.dumps([{"capability": "gitops.jj.apply-description", "effectClass": "fenced-effect", "payload": {}}]).encode()
st, err_text = take_buf(lib.aitia_dispatch_host_frames(bad_frame, len(bad_frame)))
assert st != 0 and "fence" in err_text.lower(), err_text

err_buf = AitiaBuffer()
handle = lib.aitia_session_start(ctypes.byref(err_buf))
assert handle, f"aitia_session_start failed: {take_buf(err_buf)}"
try:
    op = b"workflow_protocol_step"
    req = json.dumps({
        "caseId": "aitia/case/sdlc-lifecycle",
        "project": "c-abi-host",
        "profile": "lambda-aitia/sdlc/open-security",
        "changeId": "change:c-abi-1",
        "designAlternatives": ["zero-trust"],
        "verified": True,
        "observedObligations": ["sec.sbom-provenance"],
    }).encode()
    st, text = take_buf(lib.aitia_session_call(handle, op, len(op), req, len(req)))
    assert st == 0, text
    step = json.loads(text)
    assert step["state"] == "need-agent-synthesis"
    assert step["profile"] == "lambda-aitia/sdlc/open-security"
    assert step["actionAuthorized"] is False

    op2 = b"drive_multi_repo_protocol"
    req2 = json.dumps({
        "repos": [
            {"repoId": "a", "dependsOn": ["b"]},
            {"repoId": "b", "dependsOn": ["a"]},
        ]
    }).encode()
    st, text = take_buf(lib.aitia_session_call(handle, op2, len(op2), req2, len(req2)))
    assert st == 0, text
    cyc = json.loads(text)
    assert cyc["state"] == "need-human-decision"
    assert cyc["escalationReason"] == "dependency-cycle"
    assert cyc["actionAuthorized"] is False

    bad_op = b"no_such_op"
    st, err_msg = take_buf(lib.aitia_session_call(handle, bad_op, len(bad_op), b"{}", 2))
    assert st != 0 and "unknown" in err_msg.lower(), err_msg
finally:
    close_err = AitiaBuffer()
    rc = lib.aitia_session_close(handle, ctypes.byref(close_err))
    assert rc == 0, f"aitia_session_close failed: {take_buf(close_err)}"
"""

c_abi_env = {
    k: v
    for k, v in os.environ.items()
    if k not in ("GERBIL_LOADPATH", "GERBIL_PATH", "GERBIL_HOME")
}
subprocess.run(
    [sys.executable, "-c", c_abi_script, _aitia_mod.__file__],
    env=c_abi_env,
    check=True,
)

print("AITIA-INSTALLED-RUST-WHEEL-OK")
