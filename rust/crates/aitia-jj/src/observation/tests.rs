// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::{JjObservationError, capture_workspace, open_workspace, read_at_cut, require_current};
use futures::executor::block_on;
use std::process::Command;

#[test]
fn manifest_observation_refuses_an_operation_changed_during_file_read() {
    let executable = std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN");
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path();
    let jj = |args: &[&str]| {
        let result = Command::new(&executable)
            .current_dir(root)
            .args([
                "--config",
                "user.name='AITIA Test'",
                "--config",
                "user.email='test@example.invalid'",
            ])
            .args(args)
            .output()
            .unwrap();
        assert!(result.status.success(), "{:?}", result);
    };
    jj(&["git", "init", "--colocate"]);
    std::fs::create_dir_all(root.join(".agents/aita")).unwrap();
    let path = ".agents/aita/project.json";
    let original = r#"{"schemaVersion":1}"#;
    std::fs::write(root.join(path), original).unwrap();
    jj(&["describe", "-m", "record manifest"]);
    let workspace = open_workspace(root).unwrap();
    block_on(async {
        let cut = capture_workspace(&workspace).await.unwrap();
        assert_eq!(read_at_cut(&workspace, &cut, path).await.unwrap(), original);
        jj(&["describe", "-m", "competing operation"]);
        assert!(matches!(
            require_current(&workspace, &cut).await,
            Err(JjObservationError::ChangedOperation)
        ));
    });
}
