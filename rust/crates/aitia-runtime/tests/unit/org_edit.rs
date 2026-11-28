// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::{OrgEdit, OrgEditReview, sha256};
use std::ops::Range;

fn edit(node: &str, span: Range<usize>, expected: &str) -> OrgEdit {
    OrgEdit {
        node_id: node.into(),
        span,
        expected: expected.into(),
        replacement: "new".into(),
    }
}

#[test]
fn binds_review_to_exact_source_bytes_and_orders_edits() {
    let source = "* α\n* B\n".as_bytes();
    let digest = sha256(source);
    let review = OrgEditReview::prepare(
        "doc".into(),
        source,
        &digest,
        vec![edit("b", 7..8, "B"), edit("a", 2..4, "α")],
    )
    .unwrap();
    assert_eq!(review.source_id(), "doc");
    assert_eq!(review.source_sha256(), digest);
    assert_eq!(review.edits()[0].node_id, "a");
    assert!(review.source_current(source));
    assert!(!review.source_current("* α\n* C\n".as_bytes()));
}

#[test]
fn refuses_unbound_or_ambiguous_edits() {
    let source = "* α\n* B\n".as_bytes();
    let digest = sha256(source);
    for edits in [
        vec![edit("a", 3..4, "α")],
        vec![edit("a", 2..4, "B")],
        vec![edit("a", 2..4, "α"), edit("b", 2..5, "α\n")],
        vec![edit("a", 2..4, "α"), edit("a", 7..8, "B")],
    ] {
        assert!(OrgEditReview::prepare("doc".into(), source, &digest, edits).is_err());
    }
    assert!(
        OrgEditReview::prepare(
            "doc".into(),
            source,
            "sha256:stale",
            vec![edit("a", 2..4, "α")]
        )
        .is_err()
    );
}
