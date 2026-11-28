#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Use Case 3: FunFlow DAG Leaf Python Verification (`python.observe-pytest`).

Demonstrates the Scheme/FunFlow-first pattern for Python repositories:
1. Scheme emits a `python.observe-pytest` `HostRead` frame alongside JJ & SysML probes.
2. A failing frozen-snapshot pytest receipt fails closed into a localized `leaf-python-check`
   Schwarz `repairTask` (`need-agent-synthesis`).
3. A passing frozen-snapshot pytest receipt (`sourceUnchanged: true`) injects a cut-bound
   `ObservedFact` and allows convergence to `quiescent` (`actionAuthorized: false`).
"""

import json

from lambda_aitia_rust import Session, host_capabilities


def base_request(extra_receipts: dict) -> dict:
    receipts = {
        "gitops.jj.observe-cut": {
            "cut": {
                "workspace": "default",
                "change": "pydemo1",
                "operation": "op-py-1",
                "commit": "sha-py-001",
                "tree": "tree-py-1",
                "parents": ["sha-py-000"],
            },
            "paths": ["src/service.py"],
            "sources": [
                {"path": "README.md", "text": "# Python Service\nEnglish readme.\n"},
                {
                    "path": "docs/rfcs/0008.org",
                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                },
            ],
        },
        "sysml.project-scopes": [{"name": "service", "paths": ["src"]}],
    }
    receipts.update(extra_receipts)
    return {
        "caseId": "aitia/case/gitops-commit",
        "project": "example/python-service",
        "profile": "lambda-aitia/sdlc",
        "directory": ".",
        "pythonCheck": {
            "selectors": ["tests/test_service.py"],
            "paths": ["src/service.py", "tests/test_service.py"],
        },
        "receipts": receipts,
        "naming": {
            "projectKey": "PYSVC",
            "primaryLanguage": "en",
            "languageSources": ["README.md"],
            "types": ["feat", "fix"],
            "scopes": [],
            "references": [
                {
                    "identity": "RFC-0008",
                    "source": "docs/rfcs/0008.org",
                    "element": "ascent-obligation-funflow",
                }
            ],
        },
        "proposals": [
            {
                "identity": "PYSVC-RFC-0008",
                "reference": "RFC-0008",
                "language": "en",
                "languageSource": "README.md",
                "type": "feat",
                "scope": "service",
                "summary": "Add leaf Python verification step",
                "rationale": "Run pytest as a frozen-snapshot FunFlow HostRead capability.",
            }
        ],
        "approvalLive": True,
        "reconcile": True,
    }


def main() -> None:
    caps = json.loads(host_capabilities())
    cap_map = {c["capability"]: c["effectClass"] for c in caps["capabilities"]}
    assert cap_map["python.observe-pytest"] == "host-read"

    with Session() as session:
        # Step 1: Missing receipt -> Scheme emits `python.observe-pytest` HostRead frame
        step_probe = json.loads(session.workflow_protocol_step(json.dumps(base_request({}))))
        assert step_probe["state"] == "need-host-frames"
        assert step_probe["frames"][0]["capability"] == "python.observe-pytest"
        assert step_probe["frames"][0]["effectClass"] == "host-read"

        # Step 2: Failed pytest receipt -> localized leaf-python-check Schwarz repairTask
        step_failed = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    base_request(
                        {
                            "python.observe-pytest": {
                                "verdict": "process-failed",
                                "sourceUnchanged": True,
                                "sourceSha256": "sha256:frozen-source",
                            }
                        }
                    )
                )
            )
        )
        assert step_failed["state"] == "need-agent-synthesis"
        assert step_failed["escalationReason"] == "python-check-failed"
        assert step_failed["repairTasks"][0]["recomputeScope"] == "leaf-python-check"
        assert step_failed["actionAuthorized"] is False

        # Step 3: Passing frozen pytest receipt + applied commit receipt -> quiescent!
        step_passed = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    base_request(
                        {
                            "python.observe-pytest": {
                                "verdict": "passed",
                                "sourceUnchanged": True,
                                "sourceSha256": "sha256:frozen-source",
                            },
                            "gitops.jj.apply-description": {"resulting_commit": "sha-py-002"},
                        }
                    )
                )
            )
        )
        assert step_passed["state"] == "quiescent"
        assert step_passed["actionAuthorized"] is False

    print(
        json.dumps(
            {
                "example": "03-python-leaf-pytest-capability",
                "emittedCapability": step_probe["frames"][0]["capability"],
                "failedEscalation": step_failed["escalationReason"],
                "failedRepairScope": step_failed["repairTasks"][0]["recomputeScope"],
                "passedState": step_passed["state"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
