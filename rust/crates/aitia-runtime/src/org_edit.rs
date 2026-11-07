// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Source freshness and byte-range checks for inert ORG edit review.

use crate::source_tree::sha256;
use std::collections::HashSet;
use std::io;
use std::ops::Range;

const MAX_SOURCE_BYTES: usize = 16 * 1024 * 1024;
const MAX_EDITS: usize = 128;

/// A proposed ORG edit tied to a node and exact source byte range.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgEdit {
    pub node_id: String,
    pub span: Range<usize>,
    pub expected: String,
    pub replacement: String,
}

/// Reviewed ORG edits bound to the exact captured source.
#[derive(Debug, PartialEq, Eq)]
pub struct OrgEditReview {
    source_id: String,
    source_sha256: String,
    source_size: usize,
    edits: Vec<OrgEdit>,
}

fn invalid(reason: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, reason)
}

impl OrgEditReview {
    /// Check exact source bytes against spans supplied by the projection owner.
    ///
    /// # Errors
    ///
    /// Rejects stale source, invalid UTF-8, invalid or overlapping ranges,
    /// duplicate identities, and proposals above the source or edit limits.
    pub fn prepare(
        source_id: String,
        source: &[u8],
        projected_sha256: &str,
        mut edits: Vec<OrgEdit>,
    ) -> io::Result<Self> {
        if source_id.trim().is_empty() || source.len() > MAX_SOURCE_BYTES {
            return Err(invalid("invalid ORG source identity or size"));
        }
        let text = std::str::from_utf8(source).map_err(|_| invalid("ORG source is not UTF-8"))?;
        let source_sha256 = sha256(source);
        if source_sha256 != projected_sha256 {
            return Err(invalid("ORG source changed since projection"));
        }
        if !(1..=MAX_EDITS).contains(&edits.len()) {
            return Err(invalid("invalid ORG edit count"));
        }

        edits.sort_unstable_by_key(|edit| (edit.span.start, edit.span.end));
        let mut seen = HashSet::with_capacity(edits.len());
        let mut previous_end = 0;
        let mut replacement_size = 0_usize;
        for edit in &edits {
            if edit.node_id.trim().is_empty() || !seen.insert(&edit.node_id) {
                return Err(invalid("empty or duplicate ORG node ID"));
            }
            if edit.span.start < previous_end
                || edit.span.is_empty()
                || text.get(edit.span.clone()) != Some(edit.expected.as_str())
            {
                return Err(invalid("invalid, overlapping or stale ORG edit range"));
            }
            replacement_size = replacement_size.saturating_add(edit.replacement.len());
            if replacement_size > MAX_SOURCE_BYTES {
                return Err(invalid("ORG replacements exceed byte limit"));
            }
            previous_end = edit.span.end;
        }

        Ok(Self {
            source_id,
            source_sha256,
            source_size: source.len(),
            edits,
        })
    }

    #[must_use]
    pub fn source_id(&self) -> &str {
        &self.source_id
    }

    #[must_use]
    pub fn source_sha256(&self) -> &str {
        &self.source_sha256
    }

    #[must_use]
    pub fn edits(&self) -> &[OrgEdit] {
        &self.edits
    }

    /// Recheck supplied bytes immediately before an owner reviews the proposal.
    #[must_use]
    pub fn source_current(&self, source: &[u8]) -> bool {
        source.len() == self.source_size && sha256(source) == self.source_sha256
    }
}

#[cfg(test)]
#[path = "../tests/unit/org_edit.rs"]
mod tests;
