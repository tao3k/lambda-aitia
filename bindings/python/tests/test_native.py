# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import pytest

from lambda_aitia import GitOpsDecision, SdlcRuntime, descriptor, evaluate_gitops
from lambda_aitia.native import AitiaNativeError
from lambda_aitia.runtime import SdlcFlowPlan


def test_descriptor_is_owned_by_lambda_aitia() -> None:
    value = descriptor()
    assert value["schema"] == "lambda-aitia.native-descriptor"
    assert value["semanticOwner"] == "lambda-aitia"
    assert value["abiRevision"] == 2
    assert value["operations"] == ["sdlc-flow-plan", "gitops-evaluate"]


def test_production_runtime_materializes_scheme_owned_sdlc_plan() -> None:
    plan = SdlcRuntime().plan("release/42")
    assert plan.lifecycle_id == "release/42"
    assert plan.stages == (
        "change",
        "invalidate",
        "plan",
        "verify",
        "admit",
        "decide",
        "authorize",
        "effect",
    )
    assert plan.topological_order[-1] == "release/42/effect"
    assert plan.semantic_owner == "lambda-aitia"
    assert plan.runtime_owner == "poo-flow"
    assert plan.release_authorized is False
    assert plan.runtime_executed is False


def test_runtime_rejects_invalid_lifecycle_before_native_dispatch() -> None:
    with pytest.raises(ValueError, match="non-empty"):
        SdlcRuntime().plan("")


@pytest.mark.parametrize("field", ["releaseAuthorized", "runtimeExecuted"])
def test_runtime_rejects_inert_plan_claiming_effect(field: str) -> None:
    payload = {
        "schema": "lambda-aitia.sdlc-flow-plan",
        "lifecycleId": "release/forged",
        "stages": ["change", "effect"],
        "topologicalOrder": ["release/forged/change", "release/forged/effect"],
        "cyclePath": None,
        "accepted": True,
        "semanticOwner": "lambda-aitia",
        "runtimeOwner": "poo-flow",
        "releaseAuthorized": False,
        "runtimeExecuted": False,
    }
    payload[field] = True

    with pytest.raises(AitiaNativeError, match="claimed authority or execution"):
        SdlcFlowPlan.from_payload(payload)


def _gitops_change() -> dict[str, object]:
    return {
        "event": "pull-request",
        "repository": "tao3k/poo-flow",
        "revision": "0123456789abcdef",
        "source-ref": "feature/aitia",
        "target-ref": "develop",
        "pull-request": 42,
        "checks": [
            {"name": "commit-policy", "conclusion": "success"},
            {"name": "build", "conclusion": "success"},
            {"name": "unit-test", "conclusion": "success"},
            {
                "name": "nasa/sdlc/npr-7150.2",
                "conclusion": "success",
                "standardEdition": "D",
                "sourceLockDigest": "sha256:cfb963b8cd81fd8e22e9b47251c1dc7927b85fcdf9ec9366057cd38cb94f338c",
            },
        ],
    }


def test_python_delegates_gitops_decision_to_scheme() -> None:
    decision = evaluate_gitops(_gitops_change())
    assert isinstance(decision, GitOpsDecision)
    assert decision.accepted is True
    assert decision.profile == "dev"
    assert decision.revision == "0123456789abcdef"
    assert decision.authority_status == "not-evaluated"
    assert decision.release_authorized is False
    assert decision.runtime_executed is False


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("standardEdition", "C"),
        ("sourceLockDigest", "sha256:wrong-lock"),
        ("sourceLockDigest", None),
    ],
)
def test_python_rejects_stale_standard_assessment(field: str, value: str | None) -> None:
    change = _gitops_change()
    checks = change["checks"]
    assert isinstance(checks, list)
    standard_check = checks[-1]
    assert isinstance(standard_check, dict)
    if value is None:
        standard_check.pop(field)
    else:
        standard_check[field] = value

    decision = evaluate_gitops(change)
    assert decision.accepted is False
    assert decision.stale_checks == ("nasa/sdlc/npr-7150.2",)
    assert decision.reasons == ("standard-assessment-mismatch",)
