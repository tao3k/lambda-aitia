#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Use Case 1: Orthogonal Multi-Profile SDLC Governance (Core, OpenSecurity, NASA NPR 7150.2D).

Demonstrates calling the resident Scheme FunFlow/ASCENT engine in-process via the thin
`lambda_aitia_rust.Session` ABI with zero CLI fork overhead and zero downstream Gerbil build.
"""

import json

from lambda_aitia_rust import Session


def main() -> None:
    with Session() as session:
        # 1. Open-Security profile: missing 2 security obligations -> localized Schwarz repairTasks
        sec_open = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "example/payments-api",
                        "profile": "lambda-aitia/sdlc/open-security",
                        "changeId": "change:sec-101",
                        "designAlternatives": ["zero-trust-mesh"],
                        "verified": True,
                        "observedObligations": ["sec.sbom-provenance"],
                    }
                )
            )
        )
        assert sec_open["state"] == "need-agent-synthesis"
        assert len(sec_open["repairTasks"]) == 2
        assert sec_open["actionAuthorized"] is False

        # 2. Standard-Free SDLC Core with 2 competing designs: preserves BOTH worlds (no greedy collapse)
        competing = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "example/payments-api",
                        "profile": "lambda-aitia/sdlc",
                        "changeId": "change:core-102",
                        "designAlternatives": ["event-sourced", "relational-ledger"],
                        "verified": True,
                        "approvalLive": True,
                    }
                )
            )
        )
        assert competing["state"] == "need-human-decision"
        assert competing["epistemicSummary"]["worldCount"] == 2
        assert competing["actionAuthorized"] is False

        # 3. Open-Security with all obligations discharged + live approval + published -> quiescent
        sec_done = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "example/payments-api",
                        "profile": "lambda-aitia/sdlc/open-security",
                        "changeId": "change:sec-101",
                        "designAlternatives": ["zero-trust-mesh"],
                        "verified": True,
                        "observedObligations": [
                            "sec.sbom-provenance",
                            "sec.dependency-audit",
                            "sec.threat-model-review",
                        ],
                        "approvalLive": True,
                        "releasePublished": True,
                    }
                )
            )
        )
        assert sec_done["state"] == "quiescent"
        assert sec_done["actionAuthorized"] is False

        # 4. NASA NPR 7150.2D profile: dynamically projects SWE-052 / SWE-065 / SWE-084 obligations
        nasa_open = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "example/flight-guidance",
                        "profile": "nasa/sdlc/npr-7150.2",
                        "changeId": "change:nasa-103",
                        "designAlternatives": ["triple-modular-redundancy"],
                        "verified": True,
                        "observedObligations": [],
                    }
                )
            )
        )
        assert nasa_open["state"] == "need-agent-synthesis"
        assert len(nasa_open["repairTasks"]) == 3
        assert nasa_open["actionAuthorized"] is False

    print(
        json.dumps(
            {
                "example": "01-sdlc-profiles",
                "openSecurityOpenTasks": len(sec_open["repairTasks"]),
                "competingWorldsPreserved": competing["epistemicSummary"]["worldCount"],
                "openSecurityFinalState": sec_done["state"],
                "nasaOpenTasks": len(nasa_open["repairTasks"]),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
