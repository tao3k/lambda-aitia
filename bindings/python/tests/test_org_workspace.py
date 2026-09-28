# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Aitia preflight uses Orgize anchors; it never parses or mutates Org."""

import hashlib
from pathlib import Path

import pytest

from lambda_aitia import OrgNodeEdit, prepare_org_edit_review


SOURCE = b"* Design\n:PROPERTIES:\n:ID: design-1\n:END:\nOld guarantee\n* Notes\nKeep me\n"


def _digest(payload: bytes) -> str:
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _edit(payload: bytes = SOURCE, target: bytes = b"Old guarantee") -> OrgNodeEdit:
    start = payload.index(target)
    return OrgNodeEdit("design-1", start, start + len(target), target, b"New guarantee")


def test_prepares_source_bound_review_without_writing(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE)
    review = prepare_org_edit_review(
        source,
        source_id="design.org",
        projected_source_digest=_digest(SOURCE),
        edits=(_edit(),),
    )
    assert review.source_id == "design.org"
    assert review.source_digest == _digest(SOURCE)
    assert review.edits == (_edit(),)
    assert review.source_current(source)
    assert source.read_bytes() == SOURCE


def test_preflights_aitia_maintained_workspace_without_mutating_it() -> None:
    source = Path(__file__).resolve().parents[3] / "user-interface/workspaces/job-executor.org"
    payload = source.read_bytes()
    expected = b"This subtree is the review context for ADR 0008."
    start = payload.index(expected)
    review = prepare_org_edit_review(
        source,
        source_id="job-executor",
        projected_source_digest=_digest(payload),
        edits=(
            OrgNodeEdit(
                "aitia-job-executor-design-decision",
                start,
                start + len(expected),
                expected,
                b"This subtree requires renewed review for ADR 0008.",
            ),
        ),
    )
    assert review.source_current(source)
    assert source.read_bytes() == payload


def test_rejects_stale_projection_even_when_old_text_remains(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE + b"* Later\n")
    with pytest.raises(ValueError, match="changed since projection"):
        prepare_org_edit_review(
            source,
            source_id="design.org",
            projected_source_digest=_digest(SOURCE),
            edits=(_edit(),),
        )


def test_rejects_moved_span_with_fresh_digest(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    moved = SOURCE.replace(b"Old guarantee", b"prefix Old guarantee")
    source.write_bytes(moved)
    with pytest.raises(ValueError, match="moved or its expected content changed"):
        prepare_org_edit_review(
            source,
            source_id="design.org",
            projected_source_digest=_digest(moved),
            edits=(_edit(),),
        )


def test_rejects_overlapping_edits_and_duplicate_node(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE)
    first = _edit()
    second = OrgNodeEdit(
        "design-2",
        first.start_byte + 1,
        first.end_byte,
        SOURCE[first.start_byte + 1 : first.end_byte],
        b"changed",
    )
    with pytest.raises(ValueError, match="overlap"):
        prepare_org_edit_review(
            source, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(first, second),
        )
    with pytest.raises(ValueError, match="duplicate Org node ID"):
        prepare_org_edit_review(
            source, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(first, first),
        )


def test_review_goes_stale_after_preflight(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE)
    review = prepare_org_edit_review(
        source, source_id="design.org", projected_source_digest=_digest(SOURCE),
        edits=(_edit(),),
    )
    source.write_bytes(SOURCE.replace(b"Keep me", b"Changed"))
    assert not review.source_current(source)


def test_refuses_symlink_and_invalid_byte_span(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE)
    alias = tmp_path / "alias.org"
    alias.symlink_to(source)
    with pytest.raises(OSError):
        prepare_org_edit_review(
            alias, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(_edit(),),
        )
    bad = OrgNodeEdit("design-1", True, 3, b"* D", b"new")
    with pytest.raises(ValueError, match="invalid byte span"):
        prepare_org_edit_review(
            source, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(bad,),
        )


def test_refuses_non_utf8_source_and_split_codepoint(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE + b"\xff")
    with pytest.raises(ValueError, match="source must be UTF-8"):
        prepare_org_edit_review(
            source, source_id="design.org",
            projected_source_digest=_digest(source.read_bytes()), edits=(_edit(),),
        )
    unicode_source = SOURCE + "说明\n".encode()
    source.write_bytes(unicode_source)
    start = unicode_source.index("说明".encode()) + 1
    split = OrgNodeEdit("design-1", start, start + 1, b"\x01", b"x")
    with pytest.raises(ValueError, match="splits a UTF-8 codepoint"):
        prepare_org_edit_review(
            source, source_id="design.org",
            projected_source_digest=_digest(unicode_source), edits=(split,),
        )


def test_refuses_non_utf8_replacement_and_excess_edit_count(tmp_path: Path) -> None:
    source = tmp_path / "design.org"
    source.write_bytes(SOURCE)
    edit = _edit()
    invalid = OrgNodeEdit(
        edit.node_id, edit.start_byte, edit.end_byte, edit.expected_old, b"\xff",
    )
    with pytest.raises(ValueError, match="edit must use UTF-8"):
        prepare_org_edit_review(
            source, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(invalid,),
        )
    with pytest.raises(ValueError, match="edit count"):
        prepare_org_edit_review(
            source, source_id="design.org", projected_source_digest=_digest(SOURCE),
            edits=(edit,) * 129,
        )
