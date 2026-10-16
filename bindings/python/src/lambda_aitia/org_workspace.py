# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Source-bound Org edit proposals; Orgize owns parsing and application.

The caller supplies node identities and byte ranges from an Orgize projection.
This module checks that those ranges still refer to the projected source. It
does not authenticate the projection, interpret Org syntax, or write a file.
"""

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import re
import stat
from typing import Sequence


MAX_ORG_SOURCE_BYTES = 16 * 1024 * 1024
MAX_ORG_EDITS = 128
_DIGEST_PATTERN = re.compile(r"sha256:[0-9a-f]{64}\Z")


def _read_source(source: Path) -> bytes:
    if not hasattr(os, "O_NOFOLLOW"):
        raise OSError("Org source preflight requires O_NOFOLLOW")
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    descriptor = os.open(source, flags)
    try:
        with os.fdopen(descriptor, "rb") as stream:
            descriptor = -1
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ValueError("Org source must be a regular file")
            if info.st_size > MAX_ORG_SOURCE_BYTES:
                raise ValueError("Org source exceeds byte limit")
            payload = stream.read(MAX_ORG_SOURCE_BYTES + 1)
            if len(payload) > MAX_ORG_SOURCE_BYTES:
                raise ValueError("Org source exceeds byte limit")
            return payload
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def org_source_digest(payload: bytes) -> str:
    """Digest exact Org source bytes, not a parsed or canonicalized tree."""
    return "sha256:" + hashlib.sha256(payload).hexdigest()


@dataclass(frozen=True, slots=True)
class OrgNodeEdit:
    """An Orgize-projected node's original byte span and proposed replacement."""

    node_id: str
    start_byte: int
    end_byte: int
    expected_old: bytes
    replacement: bytes


@dataclass(frozen=True, slots=True)
class OrgEditReview:
    """Inert proposal for owner review and source-owned application."""

    source_id: str
    source_digest: str
    source_size_bytes: int
    edits: tuple[OrgNodeEdit, ...]

    def source_current(self, source: Path) -> bool:
        """Recheck bytes before review; application must check again itself."""
        try:
            payload = _read_source(Path(source))
        except (OSError, ValueError):
            return False
        return (
            len(payload) == self.source_size_bytes
            and org_source_digest(payload) == self.source_digest
            and all(
                payload[edit.start_byte : edit.end_byte] == edit.expected_old
                for edit in self.edits
            )
        )


def prepare_org_edit_review(
    source: Path,
    *,
    source_id: str,
    projected_source_digest: str,
    edits: Sequence[OrgNodeEdit],
) -> OrgEditReview:
    """Reject stale/ambiguous Orgize anchors without modifying the source.

    ``projected_source_digest`` must describe the exact bytes used to produce
    the upstream node IDs and byte ranges. A matching digest is a freshness
    check, not proof that the caller's projection is trusted or authorized.
    """
    if not isinstance(source_id, str) or not source_id.strip():
        raise ValueError("source_id must be nonempty")
    if not isinstance(projected_source_digest, str) or not _DIGEST_PATTERN.fullmatch(
        projected_source_digest
    ):
        raise ValueError("projected_source_digest must be a SHA-256 digest")
    payload = _read_source(Path(source))
    try:
        payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("Org source must be UTF-8") from error
    digest = org_source_digest(payload)
    if digest != projected_source_digest:
        raise ValueError("Org source changed since projection")
    if not 1 <= len(edits) <= MAX_ORG_EDITS:
        raise ValueError("Org edit count must be between 1 and 128")
    if any(not isinstance(edit, OrgNodeEdit) for edit in edits):
        raise TypeError("edits must be OrgNodeEdit values")
    if any(
        type(edit.start_byte) is not int or type(edit.end_byte) is not int
        for edit in edits
    ):
        raise ValueError("Org node edit has an invalid byte span")

    ordered = sorted(edits, key=lambda edit: (edit.start_byte, edit.end_byte))
    seen_ids: set[str] = set()
    prior_end = 0
    replacement_bytes = 0
    for edit in ordered:
        if not isinstance(edit.node_id, str) or not edit.node_id.strip():
            raise ValueError("node_id must be nonempty")
        if edit.node_id in seen_ids:
            raise ValueError("duplicate Org node ID in edit proposal")
        seen_ids.add(edit.node_id)
        if (
            not 0 <= edit.start_byte < edit.end_byte <= len(payload)
        ):
            raise ValueError("Org node edit has an invalid byte span")
        if (
            edit.start_byte < len(payload)
            and payload[edit.start_byte] & 0xC0 == 0x80
        ) or (
            edit.end_byte < len(payload)
            and payload[edit.end_byte] & 0xC0 == 0x80
        ):
            raise ValueError("Org node edit splits a UTF-8 codepoint")
        if edit.start_byte < prior_end:
            raise ValueError("Org node edits overlap")
        if not isinstance(edit.expected_old, bytes) or not isinstance(
            edit.replacement, bytes
        ):
            raise TypeError("Org node edits require exact source bytes")
        try:
            edit.node_id.encode("utf-8")
            edit.expected_old.decode("utf-8")
            edit.replacement.decode("utf-8")
        except UnicodeError as error:
            raise ValueError("Org node edit must use UTF-8") from error
        replacement_bytes += len(edit.replacement)
        if replacement_bytes > MAX_ORG_SOURCE_BYTES:
            raise ValueError("Org replacements exceed byte limit")
        if payload[edit.start_byte : edit.end_byte] != edit.expected_old:
            raise ValueError("Org node moved or its expected content changed")
        prior_end = edit.end_byte

    return OrgEditReview(source_id, digest, len(payload), tuple(ordered))
