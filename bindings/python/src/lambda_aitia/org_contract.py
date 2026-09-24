# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Call Orgize's Scheme-owned Element/Contract C ABI from Aitia's runtime.

Rows are already-admitted Org graph facts.  Org parsing and contract semantics
remain in Orgize; this module only owns Python transport and lifetime checks.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Sequence

from ._native._aitia_cffi import ffi, lib
from .native import AitiaNativeError, AitiaNativeSession


Expectation = Literal["exactly", "at-least", "at-most"]
_EXPECTATION_CODE = {"exactly": 0, "at-least": 1, "at-most": 2}
_INT64_MAX = (1 << 63) - 1


@dataclass(frozen=True, slots=True)
class OrgElementFact:
    """One Orgize-projected graph node with at most one projected field."""

    id: int
    parent_id: int
    kind: str
    field_name: str = ""
    field_value: str = ""


@dataclass(frozen=True, slots=True)
class OrgContractResult:
    matched_count: int
    passed: bool


def _integer(value: int, *, name: str, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(f"{name} must be an integer between {minimum} and {maximum}")
    return value


def _utf8(value: str, *, name: str, required: bool = False) -> bytes:
    if not isinstance(value, str) or (required and not value):
        raise ValueError(f"{name} must be {'nonempty ' if required else ''}text")
    if "\0" in value:
        raise ValueError(f"{name} cannot contain NUL")
    return value.encode("utf-8")


def _evaluate(
    rows: Sequence[OrgElementFact],
    scope_id: int,
    query_kind: str,
    field_name: str,
    field_value: str,
    expectation: Expectation,
    expected_count: int,
    session: AitiaNativeSession,
) -> OrgContractResult:
    session._require_owner()
    if session.closed:
        raise AitiaNativeError("Aitia native session is closed")

    # Keep the same library handle and process-exclusive Gambit session used
    # by Aitia. Opening a second dynamic handle can break cleanup/reinit.
    buffers = []

    def pointer(value: str, name: str, required: bool = False):
        buffer = ffi.new("char[]", _utf8(value, name=name, required=required))
        buffers.append(buffer)
        return buffer

    native_rows = ffi.new("orgize_element_row[]", len(rows))
    for index, row in enumerate(rows):
        native_rows[index].id = _integer(
            row.id, name="row id", minimum=0, maximum=_INT64_MAX
        )
        native_rows[index].parent_id = _integer(
            row.parent_id, name="parent id", minimum=-1, maximum=_INT64_MAX
        )
        native_rows[index].kind = pointer(row.kind, "row kind", required=True)
        native_rows[index].field_name = pointer(row.field_name, "field name")
        native_rows[index].field_value = pointer(row.field_value, "field value")
    result = ffi.new("orgize_contract_result *")
    error = ffi.new("char[512]")
    status = lib.lambda_aitia_python_session_org_contract(
        session._handle,
        native_rows if rows else ffi.NULL,
        len(rows),
        scope_id,
        pointer(query_kind, "query kind", required=True),
        pointer(field_name, "field name"),
        pointer(field_value, "field value"),
        _EXPECTATION_CODE[expectation],
        expected_count,
        result,
        error,
        512,
    )
    if status != 0 or result.status != 0:
        detail = ffi.string(error).decode("utf-8", errors="replace")
        raise AitiaNativeError(detail or "Orgize rejected graph contract evaluation")
    return OrgContractResult(result.matched_count, result.passed == 1)


def evaluate_org_contract(
    rows: Sequence[OrgElementFact],
    *,
    scope_id: int,
    query_kind: str,
    field_name: str = "",
    field_value: str = "",
    expectation: Expectation = "exactly",
    expected_count: int = 1,
    session: AitiaNativeSession | None = None,
) -> OrgContractResult:
    """Evaluate an Orgize Contract on source-owner-projected graph facts.

    This result is an observation, not source authenticity, Host admission,
    review approval, or runtime-effect authority.
    """
    if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
        raise TypeError("rows must be a sequence of OrgElementFact values")
    if len(rows) > 10000 or any(not isinstance(row, OrgElementFact) for row in rows):
        raise ValueError("rows must contain at most 10000 OrgElementFact values")
    _integer(scope_id, name="scope id", minimum=0, maximum=_INT64_MAX)
    _integer(expected_count, name="expected count", minimum=0, maximum=10000)
    if expectation not in _EXPECTATION_CODE:
        raise ValueError("expectation must be exactly, at-least, or at-most")
    if session is None:
        with AitiaNativeSession() as owned:
            return _evaluate(
                rows, scope_id, query_kind, field_name, field_value,
                expectation, expected_count, owned,
            )
    return _evaluate(
        rows, scope_id, query_kind, field_name, field_value,
        expectation, expected_count, session,
    )
