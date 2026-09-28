# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""The delivered Aitia library calls Orgize's Scheme-owned C ABI."""

import pytest

from lambda_aitia import (
    AitiaNativeSession,
    OrgElementFact,
    evaluate_org_contract,
)
from lambda_aitia.native import AitiaNativeError


ROWS = (
    OrgElementFact(0, -1, "org-data"),
    OrgElementFact(1, 0, "headline", "title", "Evidence"),
)


def test_orgize_contract_through_bundled_native_library() -> None:
    result = evaluate_org_contract(
        ROWS, scope_id=0, query_kind="headline", field_name="title",
        field_value="Evidence",
    )
    assert result.matched_count == 1
    assert result.passed is True
    assert evaluate_org_contract(
        ROWS, scope_id=0, query_kind="headline", field_name="title",
        field_value="Missing",
    ).passed is False


def test_orgize_contract_uses_existing_native_session() -> None:
    with AitiaNativeSession() as session:
        result = evaluate_org_contract(
            ROWS, scope_id=0, query_kind="headline", session=session,
        )
        assert result.matched_count == 1
    with pytest.raises(AitiaNativeError, match="closed"):
        evaluate_org_contract(
            ROWS, scope_id=0, query_kind="headline", session=session,
        )


@pytest.mark.parametrize(
    ("rows", "kind", "error"),
    [
        ((OrgElementFact(0, -1, "head\x00line"),), "headline", "NUL"),
        ((OrgElementFact(-1, -1, "headline"),), "headline", "row id"),
        (ROWS, "head\x00line", "NUL"),
    ],
)
def test_orgize_transport_rejects_unsafe_inputs(rows, kind, error) -> None:
    with pytest.raises(ValueError, match=error):
        evaluate_org_contract(rows, scope_id=0, query_kind=kind)
