# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import pytest

from lambda_aitia import GitOpsDecision, SdlcRuntime, descriptor, evaluate_gitops


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


def test_python_delegates_gitops_decision_to_scheme() -> None:
    decision = evaluate_gitops(
        {
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
                {"name": "nasa-7150-2d", "conclusion": "success"},
            ],
        }
    )
    assert isinstance(decision, GitOpsDecision)
    assert decision.accepted is True
    assert decision.profile == "dev"
    assert decision.revision == "0123456789abcdef"
    assert decision.authority_status == "not-evaluated"
    assert decision.release_authorized is False
    assert decision.runtime_executed is False
