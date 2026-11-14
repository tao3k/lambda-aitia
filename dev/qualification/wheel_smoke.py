# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Exercise the installed PyO3 extension against the linked Scheme program."""

import hashlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory

from lambda_aitia_rust import OrgEdit, OrgEditReview, Session, capture_source_tree, run_frozen_pytest


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
finally:
    session.close()

try:
    session.flow_graph('{"lifecycle-id":"wheel/42"}')
except RuntimeError:
    pass
else:
    raise AssertionError("closed Rust session accepted a request")

print("AITIA-INSTALLED-RUST-WHEEL-OK")
