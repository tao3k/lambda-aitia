#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Use Case 4: AI-Native Mixed-Initiative 5-State IoC Protocol Loop.

Demonstrates a high-frequency in-process AI Agent loop over one resident `Session`:
- Round 1 (missing proposal) -> `need-agent-synthesis` with bounded Schwarz `repairTasks`
- Round 2 (Agent synthesizes grounded proposal from `repairTasks`) -> `need-human-decision`
- Round 3 (Human grants live approval + fenced commit applied) -> `quiescent`
"""

import json

from lambda_aitia_rust import Session


def make_step_payload(proposals: list, approval_live: bool, applied: bool) -> dict:
    receipts = {
        "gitops.jj.observe-cut": {
            "cut": {
                "workspace": "default",
                "change": "agent1",
                "operation": "op-agent-1",
                "commit": "sha-agent-001",
                "tree": "tree-agent-1",
                "parents": ["sha-agent-000"],
            },
            "paths": ["modules/workflow/protocol.ss"],
            "sources": [
                {"path": "README.md", "text": "# Agentic Repo\nEnglish readme.\n"},
                {
                    "path": "docs/rfcs/0008.org",
                    "text": "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n",
                },
            ],
        },
        "sysml.project-scopes": [{"name": "gitops", "paths": ["modules/workflow"]}],
    }
    if applied:
        receipts["gitops.jj.apply-description"] = {"resulting_commit": "sha-agent-002"}
    return {
        "caseId": "aitia/case/gitops-commit",
        "project": "example/agent-loop",
        "profile": "lambda-aitia/sdlc",
        "directory": ".",
        "receipts": receipts,
        "naming": {
            "projectKey": "AITIA",
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
        "proposals": proposals,
        "approvalLive": approval_live,
        "reconcile": True,
    }


def main() -> None:
    with Session() as session:
        # Round 1: No proposal yet -> Scheme asks the AI Agent for bounded synthesis (NOT the human!)
        r1 = json.loads(
            session.workflow_protocol_step(json.dumps(make_step_payload([], False, False)))
        )
        assert r1["state"] == "need-agent-synthesis"
        assert r1["handoffTarget"] == "agent-synthesis"
        assert r1["gapKind"] == "model-check-gap"
        task = r1["repairTasks"][0]
        assert "gitops" in task["allowedScopes"]
        assert "RFC-0008" in task["allowedReferences"]
        assert r1["actionAuthorized"] is False

        # Agent synthesizes a grounded proposal strictly within Scheme's allowed scope/reference/type
        synthesized_proposal = {
            "identity": f"AITIA-{task['allowedReferences'][0]}",
            "reference": task["allowedReferences"][0],
            "language": "en",
            "languageSource": "README.md",
            "type": task["allowedTypes"][0],
            "scope": task["allowedScopes"][0],
            "summary": "Add grounded commit proposal",
            "rationale": "Machine-checkable synthesis hole resolved by Agent before human review.",
        }

        # Round 2: Grounded proposal passes machine checks -> escalates cleanly to Human governance gate
        r2 = json.loads(
            session.workflow_protocol_step(
                json.dumps(make_step_payload([synthesized_proposal], False, False))
            )
        )
        assert r2["state"] == "need-human-decision"
        assert r2["handoffTarget"] == "human-decision"
        assert r2["gapKind"] == "requirement-gap"
        assert r2["actionAuthorized"] is False

        # Round 3: Human approves + fenced commit receipt recorded -> quiescent
        r3 = json.loads(
            session.workflow_protocol_step(
                json.dumps(make_step_payload([synthesized_proposal], True, True))
            )
        )
        assert r3["state"] == "quiescent"
        assert r3["handoffTarget"] == "none"
        assert r3["actionAuthorized"] is False

    print(
        json.dumps(
            {
                "example": "04-agent-repair-loop",
                "round1": {"state": r1["state"], "handoff": r1["handoffTarget"]},
                "round2": {"state": r2["state"], "handoff": r2["handoffTarget"]},
                "round3": {"state": r3["state"], "handoff": r3["handoffTarget"]},
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
