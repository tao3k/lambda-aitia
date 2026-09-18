# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Typed GitOps decision receipts produced by the Scheme semantic owner."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from .native import AitiaNativeError, _evaluate_gitops_payload
from .runtime import _boolean, _string, _strings


@dataclass(frozen=True, slots=True)
class GitOpsDecision:
    """An inert GitOps evidence decision; it grants no release authority."""

    repository: str
    revision: str
    profile: str
    environment: str
    accepted: bool
    next_profile: str
    required_checks: tuple[str, ...]
    standards: tuple[str, ...]
    missing_checks: tuple[str, ...]
    failed_checks: tuple[str, ...]
    stale_checks: tuple[str, ...]
    reasons: tuple[str, ...]
    semantic_owner: str
    runtime_owner: str
    authority_status: str
    release_authorized: bool
    runtime_executed: bool

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> GitOpsDecision:
        if payload.get("schema") != "lambda-aitia.gitops-decision":
            raise AitiaNativeError("unexpected GitOps decision schema")
        decision = cls(
            repository=_string(payload.get("repository"), "repository"),
            revision=_string(payload.get("revision"), "revision"),
            profile=_string(payload.get("profile"), "profile"),
            environment=_string(payload.get("environment"), "environment"),
            accepted=_boolean(payload.get("accepted"), "accepted"),
            next_profile=_string(payload.get("nextProfile"), "nextProfile"),
            required_checks=_strings(payload.get("requiredChecks"), "requiredChecks"),
            standards=_strings(payload.get("standards"), "standards"),
            missing_checks=_strings(payload.get("missingChecks"), "missingChecks"),
            failed_checks=_strings(payload.get("failedChecks"), "failedChecks"),
            stale_checks=_strings(payload.get("staleChecks"), "staleChecks"),
            reasons=_strings(payload.get("reasons"), "reasons"),
            semantic_owner=_string(payload.get("semanticOwner"), "semanticOwner"),
            runtime_owner=_string(payload.get("runtimeOwner"), "runtimeOwner"),
            authority_status=_string(payload.get("authorityStatus"), "authorityStatus"),
            release_authorized=_boolean(
                payload.get("releaseAuthorized"), "releaseAuthorized"
            ),
            runtime_executed=_boolean(payload.get("runtimeExecuted"), "runtimeExecuted"),
        )
        if decision.semantic_owner != "lambda-aitia" or decision.runtime_owner != "poo-flow":
            raise AitiaNativeError("unexpected GitOps decision owner")
        if decision.authority_status != "not-evaluated":
            raise AitiaNativeError("unexpected GitOps authority status")
        return decision


def evaluate_gitops(change: Mapping[str, Any]) -> GitOpsDecision:
    """Evaluate check evidence without implying release authorization or execution."""

    if not isinstance(change, Mapping):
        raise TypeError("change must be a mapping")
    return GitOpsDecision.from_payload(_evaluate_gitops_payload(change))
