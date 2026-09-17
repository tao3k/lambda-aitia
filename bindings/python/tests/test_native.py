# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

from lambda_aitia import descriptor, evaluate_gitops


def test_descriptor_is_owned_by_lambda_aitia() -> None:
    value = descriptor()
    assert value["schema"] == "lambda-aitia.native-descriptor"
    assert value["semanticOwner"] == "lambda-aitia"
    assert value["abiRevision"] == 1


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
    assert decision["schema"] == "lambda-aitia.gitops-decision"
    assert decision["accepted"] is True
    assert decision["profile"] == "dev"
    assert decision["revision"] == "0123456789abcdef"
