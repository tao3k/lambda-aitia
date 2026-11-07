// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use aitia_runtime::{RecordedSysmlError, parse_recorded_sysml, parse_sysml};
use opensysml::Connection;
use std::path::Path;
use std::process::Command;

const NAME: &str = "dev/sysml/aitia-commit.sysml";
const SOURCE: &str = include_str!("../../../../../dev/sysml/aitia-commit.sysml");

#[test]
fn resolves_the_commit_case_and_refuses_invalid_input() -> Result<(), Box<dyn std::error::Error>> {
    let connection = Connection::connect()?;
    let model = parse_sysml(&connection, [(NAME.into(), SOURCE.into())])?;
    assert_eq!(model.documents(), [NAME]);
    for name in ["exactCut", "modelEngineeringGraph", "groundedGaps"] {
        let qualified = format!("AitiaCommit::{name}");
        assert_eq!(model.lookup(&qualified)?.id(), qualified);
    }
    assert!(model.find("AitiaCommit::missingModelBinding")?.is_none());
    assert!(matches!(
        parse_sysml(&connection, [(NAME.into(), "package Broken {".into())]),
        Err(opensysml::Error::ModelErrors { .. })
    ));
    if let Some(jj) = std::env::var_os("AITIA_JJ_BIN") {
        check_recorded_documents(&connection, Path::new(&jj))?;
    }
    Ok(())
}

fn check_recorded_documents(
    connection: &Connection,
    jj: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let repository = tempfile::tempdir()?;
    let root = repository.path();
    let execute = |args: &[&str]| {
        let result = Command::new(jj)
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
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
    };
    execute(&["git", "init", "--colocate"]);
    std::fs::create_dir_all(root.join("dev/sysml"))?;
    std::fs::write(root.join(NAME), SOURCE)?;
    let second = "dev/sysml/consumer.sysml";
    std::fs::write(
        root.join(second),
        "package Consumer { private import AitiaCommit::*; item cut : CommitCut; }",
    )?;
    std::fs::create_dir_all(root.join(".agents/aita"))?;
    let manifest = root.join(".agents/aita/project.json");
    std::fs::write(
        &manifest,
        serde_json::to_vec(&serde_json::json!({
            "schemaVersion": 1, "models": {"quint": [], "sysml": [NAME, second]}
        }))?,
    )?;
    execute(&["describe", "-m", "record paired SysML documents"]);
    let cut = aitia_jj::observe_workspace(root)?;
    std::fs::write(root.join(second), "package Broken {")?;
    let model = parse_recorded_sysml(connection, &cut, &[NAME.into(), second.into()])?;
    assert_eq!(model.documents(), [NAME, second]);
    assert_eq!(model.lookup("Consumer::cut")?.id(), "Consumer::cut");
    assert!(matches!(
        parse_recorded_sysml(connection, &cut, &["missing.sysml".into()]),
        Err(RecordedSysmlError::Source(_))
    ));
    #[cfg(feature = "linked-program")]
    let check = || {
        Command::new(env!("CARGO_BIN_EXE_aitia"))
            .current_dir(root)
            .args(["check", "sysml"])
            .arg(".")
            .output()
    };
    #[cfg(feature = "linked-program")]
    {
        std::fs::write(&manifest, r#"{"schemaVersion":1}"#)?;
        let result = check()?;
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        let receipt: serde_json::Value = serde_json::from_slice(&result.stdout)?;
        assert_eq!(receipt["cut"]["commit_id"], cut.commit_id());
        assert_eq!(receipt["documents"], serde_json::json!([NAME, second]));
        assert_eq!(receipt["modelHash"], model.hash());
        // Keep the original declared paths so the next cut reaches the invalid model.
        std::fs::write(
            &manifest,
            aitia_jj::read_recorded_file(&cut, ".agents/aita/project.json")?,
        )?;
    }
    execute(&["describe", "-m", "record invalid working copy"]);
    assert!(matches!(
        parse_recorded_sysml(connection, &cut, &[NAME.into(), second.into()]),
        Err(RecordedSysmlError::Source(
            aitia_jj::JjObservationError::ChangedOperation
        ))
    ));
    let current = aitia_jj::observe_workspace(root)?;
    assert!(matches!(
        parse_recorded_sysml(connection, &current, &[NAME.into(), second.into()]),
        Err(RecordedSysmlError::Model(
            opensysml::Error::ModelErrors { .. }
        ))
    ));
    #[cfg(feature = "linked-program")]
    {
        let result = check()?;
        assert!(!result.status.success());
        assert!(result.stdout.is_empty());
        let diagnostic = String::from_utf8_lossy(&result.stderr);
        assert!(diagnostic.contains("ModelErrors"), "{diagnostic}");
    }
    Ok(())
}
