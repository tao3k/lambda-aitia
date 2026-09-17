# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Typed production runtime surface for the Scheme-owned SDLC lifecycle."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from .native import AitiaNativeError, sdlc_flow_plan


def _string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise AitiaNativeError(f"invalid SDLC flow-plan field: {field}")
    return value


def _strings(value: Any, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise AitiaNativeError(f"invalid SDLC flow-plan field: {field}")
    return tuple(value)


def _boolean(value: Any, field: str) -> bool:
    if not isinstance(value, bool):
        raise AitiaNativeError(f"invalid SDLC flow-plan field: {field}")
    return value


@dataclass(frozen=True, slots=True)
class SdlcFlowPlan:
    """An inert lifecycle DAG receipt produced by Lambda Aitia Scheme."""

    lifecycle_id: str
    stages: tuple[str, ...]
    topological_order: tuple[str, ...]
    cycle_path: tuple[str, ...] | None
    accepted: bool
    semantic_owner: str
    runtime_owner: str
    release_authorized: bool
    runtime_executed: bool

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> SdlcFlowPlan:
        """Validate and materialize one native flow-plan receipt."""

        if payload.get("schema") != "lambda-aitia.sdlc-flow-plan":
            raise AitiaNativeError("unexpected SDLC flow-plan schema")
        cycle_value = payload.get("cyclePath")
        cycle_path = (
            None
            if cycle_value is None or cycle_value is False
            else _strings(cycle_value, "cyclePath")
        )
        plan = cls(
            lifecycle_id=_string(payload.get("lifecycleId"), "lifecycleId"),
            stages=_strings(payload.get("stages"), "stages"),
            topological_order=_strings(
                payload.get("topologicalOrder"), "topologicalOrder"
            ),
            cycle_path=cycle_path,
            accepted=_boolean(payload.get("accepted"), "accepted"),
            semantic_owner=_string(payload.get("semanticOwner"), "semanticOwner"),
            runtime_owner=_string(payload.get("runtimeOwner"), "runtimeOwner"),
            release_authorized=_boolean(
                payload.get("releaseAuthorized"), "releaseAuthorized"
            ),
            runtime_executed=_boolean(payload.get("runtimeExecuted"), "runtimeExecuted"),
        )
        if plan.semantic_owner != "lambda-aitia" or plan.runtime_owner != "poo-flow":
            raise AitiaNativeError("unexpected SDLC flow-plan owner")
        return plan


class SdlcRuntime:
    """Production entry point for Lambda Aitia's SDLC runtime contracts.

    Planning is available now. Execution is intentionally not represented as
    complete until every Scheme-owned stage publishes an attributable receipt.
    """

    def plan(self, lifecycle_id: str) -> SdlcFlowPlan:
        """Build and validate the canonical POO Flow DAG for a lifecycle."""

        if not isinstance(lifecycle_id, str) or not lifecycle_id:
            raise ValueError("lifecycle_id must be a non-empty string")
        return SdlcFlowPlan.from_payload(sdlc_flow_plan(lifecycle_id))
