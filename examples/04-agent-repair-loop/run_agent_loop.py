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
        assert r1["agentHandoff"]["schema"] == "lambda-aitia.agent-synthesis-handoff.v1"
        assert r1["agentHandoff"]["actionAuthorized"] is False
        assert "execute-fenced-effect" in r1["agentHandoff"]["forbiddenActions"]
        task = r1["repairTasks"][0]
        assert "gitops" in task["allowedScopes"]
        assert "RFC-0008" in task["allowedReferences"]
        assert r1["actionAuthorized"] is False

        # Agent synthesizes TWO competing grounded candidate branches strictly within allowed bounds
        branch_feat = {
            "identity": f"AITIA-{task['allowedReferences'][0]}-feat",
            "reference": task["allowedReferences"][0],
            "language": "en",
            "languageSource": "README.md",
            "type": "feat",
            "scope": task["allowedScopes"][0],
            "summary": "Add grounded commit proposal",
            "rationale": "Candidate branch A: introduce new capability boundary.",
        }
        branch_fix = {
            "identity": f"AITIA-{task['allowedReferences'][0]}-fix",
            "reference": task["allowedReferences"][0],
            "language": "en",
            "languageSource": "README.md",
            "type": "fix",
            "scope": task["allowedScopes"][0],
            "summary": "Fix grounded commit proposal",
            "rationale": "Candidate branch B: narrow patch to existing boundary.",
        }

        # Round 2: Both competing branches pass machine checks -> Scheme preserves BOTH eligible
        # titles (never silently picks a winner!) and escalates cleanly to Human governance gate.
        r2 = json.loads(
            session.workflow_protocol_step(
                json.dumps(make_step_payload([branch_feat, branch_fix], False, False))
            )
        )
        assert r2["state"] == "need-human-decision"
        assert r2["handoffTarget"] == "human-decision"
        assert r2["gapKind"] == "requirement-gap"
        assert len(r2["reconciliation"]["eligibleTitles"]) == 2
        assert r2["actionAuthorized"] is False

        # Round 3: Human selects winning branch + grants live approval + fenced commit applied -> quiescent
        r3 = json.loads(
            session.workflow_protocol_step(
                json.dumps(make_step_payload([branch_feat], True, True))
            )
        )
        assert r3["state"] == "quiescent"
        assert r3["handoffTarget"] == "none"
        assert r3["actionAuthorized"] is False

    print(
        json.dumps(
            {
                "example": "04-agent-repair-loop",
                "round1": {
                    "state": r1["state"],
                    "handoff": r1["handoffTarget"],
                    "agentHandoffSchema": r1["agentHandoff"]["schema"],
                },
                "round2": {
                    "state": r2["state"],
                    "handoff": r2["handoffTarget"],
                    "competingBranchesPreserved": len(r2["reconciliation"]["eligibleTitles"]),
                },
                "round3": {"state": r3["state"], "handoff": r3["handoffTarget"]},
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
