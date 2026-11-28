// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::{
    FrozenSourceFile, FrozenWorkspace, MAGIC, MAX_FILES, capture_source_tree, decode_source_tree,
};
use std::io;
use std::{fs, os::unix::fs::symlink};

#[test]
fn encodes_files_in_wire_order() -> io::Result<()> {
    let root = tempfile::tempdir()?;
    fs::create_dir(root.path().join("a"))?;
    fs::write(root.path().join("a/z"), b"\0")?;
    fs::write(root.path().join("a-"), b"two")?;
    let expected = b"lambda-aitia.source-tree.v1\0\0\0\0\0\0\0\0\x02\
        \0\0\0\x02a-\0\0\0\0\0\0\0\x03two\
        \0\0\0\x03a/z\0\0\0\0\0\0\0\x01\0";
    let payload = capture_source_tree(root.path())?;
    assert_eq!(payload, expected);
    assert_eq!(
        decode_source_tree(&payload)?,
        [
            FrozenSourceFile {
                path: "a-",
                bytes: b"two"
            },
            FrozenSourceFile {
                path: "a/z",
                bytes: b"\0"
            },
        ]
    );
    for length in 0..payload.len() {
        assert!(decode_source_tree(&payload[..length]).is_err(), "{length}");
    }
    Ok(())
}

#[test]
fn refuses_symlink_and_unrepresentable_path() -> io::Result<()> {
    let root = tempfile::tempdir()?;
    symlink("missing", root.path().join("link"))?;
    assert!(capture_source_tree(root.path()).is_err());
    fs::remove_file(root.path().join("link"))?;
    fs::write(root.path().join("a\\b"), b"bytes")?;
    assert!(capture_source_tree(root.path()).is_err());
    Ok(())
}

#[test]
fn rejects_unsafe_or_noncanonical_frozen_trees() {
    fn payload(paths: &[&str]) -> Vec<u8> {
        let mut payload = MAGIC.to_vec();
        payload.extend_from_slice(&(paths.len() as u64).to_be_bytes());
        for path in paths {
            payload.extend_from_slice(&u32::try_from(path.len()).unwrap().to_be_bytes());
            payload.extend_from_slice(path.as_bytes());
            payload.extend_from_slice(&0_u64.to_be_bytes());
        }
        payload
    }

    for paths in [
        &["../escape"][..],
        &["/absolute"],
        &["C:drive"],
        &["a\\b"],
        &["a/./b"],
        &["a//b"],
        &["a\0b"],
        &["b", "a"],
        &["a", "a"],
        &["a", "a-", "a/z"],
    ] {
        assert!(decode_source_tree(&payload(paths)).is_err(), "{paths:?}");
    }

    let mut over_limit = payload(&[]);
    let count = u64::try_from(MAX_FILES).unwrap() + 1;
    over_limit[MAGIC.len()..].copy_from_slice(&count.to_be_bytes());
    assert!(decode_source_tree(&over_limit).is_err());

    let mut oversized_field = payload(&["a"]);
    let size_offset = oversized_field.len() - 8;
    oversized_field[size_offset..].copy_from_slice(&u64::MAX.to_be_bytes());
    assert!(decode_source_tree(&oversized_field).is_err());

    let mut trailing = payload(&[]);
    trailing.push(0);
    assert!(decode_source_tree(&trailing).is_err());
}

#[test]
fn prepares_an_isolated_workspace_from_frozen_bytes() -> io::Result<()> {
    let original = tempfile::tempdir()?;
    let test_path = "tests/test_example.py";
    fs::create_dir(original.path().join("tests"))?;
    fs::write(original.path().join(test_path), b"frozen")?;
    let payload = capture_source_tree(original.path())?;
    fs::write(original.path().join(test_path), b"edited")?;

    let workspace = FrozenWorkspace::prepare(&payload)?;
    let root = workspace.root().to_path_buf();
    assert_eq!(capture_source_tree(&root)?, payload);
    assert_eq!(fs::read(root.join(test_path))?, b"frozen");
    fs::write(root.join(test_path), b"replay mutation")?;
    assert_eq!(fs::read(original.path().join(test_path))?, b"edited");
    assert_ne!(capture_source_tree(&root)?, payload);
    drop(workspace);
    assert!(!root.exists());
    assert!(FrozenWorkspace::prepare(&payload[..payload.len() - 1]).is_err());
    Ok(())
}
