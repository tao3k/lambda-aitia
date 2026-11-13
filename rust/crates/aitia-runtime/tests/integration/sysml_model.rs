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
    for name in [
        "exactCut",
        "modelEngineeringGraph",
        "groundedGaps",
        "EngineeringReference",
        "ReviewRevision",
        "historicalReviewRead",
        "recoveredReviewRead",
        "appliedReviewRefresh",
        "acknowledgedPushRecovery",
        "appliedEvidenceReadback",
        "observedEvidenceLineage",
        "revisionInventoryQuery",
        "affectedModelAudit",
        "historicalModelEvidence",
        "NarrationProposal",
        "RecordedReviewBookmark",
        "RecordedReviewBookmark::githubRepository",
        "ProviderReviewObservation::headRevision",
        "ProviderReviewObservation::targetRevision",
        "ProviderReviewObservation::onCandidate",
        "ProviderReviewObservation::updatedAt",
        "ProviderBranchAbsence::headRevision",
        "liveReviewAssociation",
        "currentPushDestination",
        "projectDeclarationOverlay",
        "NarrationAssessment",
        "CompiledPolicyProgram",
        "compiledPolicyCurrentness",
        "DescriptionReviewOrigin",
        "reviewContextPreservation",
        "NarrationProposal::language",
        "NarrationProposal::languageSource",
    ] {
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
            "schemaVersion": 1,
            "services": {"sysml": {"enable": true, "parse": true}},
            "programs": {"jj": {"enable": true, "settings": {
                "project": "sysml-review", "profile": "nasa/sdlc/npr-7150.2", "primary": "SWE-084",
                "checks": [{"requirement": "SWE-084", "method": "jj.configuration-audit"}],
                "naming": {
                    "projectKey": "TEST", "types": ["docs"],
                    "scopes": [{"name": "model", "paths": ["dev/sysml"]}],
                    "references": [{"identity": "RFC-1", "source": "work.org", "element": "work"}],
                    "languageSources": ["work.org"]
                }
            }}}
        }))?,
    )?;
    std::fs::write(
        root.join("work.org"),
        "* Review a model\n:PROPERTIES:\n:ID: work\n:ENGINEERING_ID: RFC-1\n:END:\n",
    )?;
    execute(&["describe", "-m", "record paired SysML documents"]);
    let cut = aitia_jj::observe_workspace(root)?;
    #[cfg(feature = "linked-program")]
    let commit_manifest = std::fs::read(&manifest)?;
    std::fs::write(root.join(second), "package Broken {")?;
    std::fs::write(root.join("unrecorded.sysml"), "package Broken {")?;
    let sources = aitia_jj::recorded_sysml_paths(&cut)?;
    assert_eq!(sources, [NAME, second]);
    let model = parse_recorded_sysml(connection, &cut, &sources)?;
    assert_eq!(model.documents(), [NAME, second]);
    assert_eq!(model.lookup("Consumer::cut")?.id(), "Consumer::cut");
    assert!(matches!(
        parse_recorded_sysml(connection, &cut, &["missing.sysml".into()]),
        Err(RecordedSysmlError::Source(_))
    ));
    #[cfg(feature = "linked-program")]
    let check = || {
        Command::new(env!("CARGO_BIN_EXE_aitia"))
            .current_dir(root.join("dev/sysml"))
            .arg("check")
            .output()
    };
    #[cfg(feature = "linked-program")]
    let review = || -> Result<serde_json::Value, Box<dyn std::error::Error>> {
        let result = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .current_dir(root)
            .args(["jj", "commit"])
            .output()?;
        assert!(result.status.success(), "{:?}", result);
        Ok(serde_json::from_slice(&result.stdout)?)
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
        assert_eq!(
            receipt["checks"]["sysml"]["documents"],
            serde_json::json!([NAME, second])
        );
        assert_eq!(receipt["checks"]["sysml"]["modelHash"], model.hash());
        let audit = review()?;
        assert_eq!(audit["modelCheck"]["report"], receipt["checks"]["sysml"]);
        assert_eq!(
            audit["review"]["auditChecklist"],
            serde_json::json!([{"check": "sysml.parse", "status": "passed"}])
        );
        // Keep the original declared paths so the next cut reaches the invalid model.
        std::fs::write(
            &manifest,
            aitia_jj::read_recorded_file(&cut, ".agents/aita/project.json")?,
        )?;
    }
    std::fs::remove_file(root.join("unrecorded.sysml"))?;
    execute(&["describe", "-m", "record invalid working copy"]);
    assert!(matches!(
        aitia_jj::recorded_sysml_paths(&cut),
        Err(aitia_jj::JjObservationError::ChangedOperation)
    ));
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
        let audit = review()?;
        assert_eq!(audit["modelCheck"]["status"], "open");
        assert_eq!(
            audit["review"]["open"],
            serde_json::json!([["sysml.parse"]])
        );
        execute(&["new", "-m", "record unrelated work"]);
        std::fs::write(root.join("note.txt"), "No model change.")?;
        execute(&["describe", "-m", "record unrelated work"]);
        let audit = review()?;
        assert!(audit["modelCheck"].is_null());
        assert_eq!(audit["review"]["auditChecklist"], serde_json::json!([]));
    }
    #[cfg(feature = "linked-program")]
    {
        std::fs::write(
            &manifest,
            r#"{"schemaVersion":1,"services":{"sysml":{"enable":true,"parse":false}}}"#,
        )?;
        execute(&["describe", "-m", "disable SysML parsing"]);
        let result = check()?;
        assert!(result.status.success(), "{:?}", result);
        let receipt: serde_json::Value = serde_json::from_slice(&result.stdout)?;
        assert!(receipt["checks"]["sysml"].is_null());
        execute(&["new", "-m", "record independently parsed model"]);
        let removed = std::fs::read(root.join(second))?;
        std::fs::remove_file(root.join(second))?;
        std::fs::write(&manifest, &commit_manifest)?;
        execute(&["describe", "-m", "record model removal"]);
        let audit = review()?;
        assert_eq!(audit["modelCheck"]["paths"], serde_json::json!([second]));
        assert_eq!(audit["modelCheck"]["status"], "open");
        assert_eq!(
            audit["review"]["open"],
            serde_json::json!([["sysml.parse"]])
        );
        std::fs::write(root.join(second), removed)?;
        let selected = "dev/sysml/review-only.sysml";
        std::fs::write(root.join(selected), "package ReviewOnly { item evidence; }")?;
        execute(&["describe", "-m", "record independently parsed model"]);
        check_model_readback(root, selected, &execute)?;
        execute(&["new", "-m", "record oversized model inputs"]);
        std::fs::write(&manifest, &commit_manifest)?;
        let oversized = ["dev/sysml/large-a.sysml", "dev/sysml/large-b.sysml"];
        for path in oversized {
            std::fs::write(root.join(path), "")?;
        }
        // Record the paths before growing them past JJ's new-file threshold.
        execute(&["describe", "-m", "track model inputs"]);
        for path in oversized {
            std::fs::write(root.join(path), vec![b' '; 2 * 1024 * 1024 + 1])?;
        }
        execute(&["describe", "-m", "record oversized model inputs"]);
        let oversized_cut = aitia_jj::observe_workspace(root)?;
        let refused =
            parse_recorded_sysml(connection, &oversized_cut, &oversized.map(str::to_owned));
        assert!(
            matches!(
                &refused,
                Err(RecordedSysmlError::Source(aitia_jj::JjObservationError::Output(message)))
                    if message == "recorded inputs exceed the byte limit"
            ),
            "{:?}",
            refused.err()
        );
        let audit = review()?;
        assert_eq!(audit["modelCheck"]["paths"], serde_json::json!(oversized));
        assert_eq!(audit["modelCheck"]["status"], "open");
        assert_eq!(
            audit["modelCheck"]["detail"],
            "recorded inputs exceed the byte limit"
        );
        assert_eq!(
            audit["review"]["open"],
            serde_json::json!([["sysml.parse"]])
        );
        check_oversized_model_archive(root, &oversized_cut, &audit)?;
    }
    Ok(())
}

#[cfg(feature = "linked-program")]
fn check_oversized_model_archive(
    root: &Path,
    cut: &aitia_jj::WorkspaceCut,
    audit: &serde_json::Value,
) -> Result<(), Box<dyn std::error::Error>> {
    use serde_json::json;
    use std::process::Stdio;

    // An applied JJ description alone cannot establish a passed model audit.
    let description = "Oversized model archive fixture";
    let receipt = aitia_jj::prepare_description(cut, description)?.publish(|_| true)?;
    let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
        .current_dir(root)
        .args(["jj", "commit", "evidence", &receipt.resulting_commit])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    serde_json::to_writer(
        child.stdin.take().unwrap(),
        &json!({
            "receipt":receipt, "cut":audit["cut"], "review":{"description":description},
            "executions":[],
            "modelCheck":{"paths":audit["modelCheck"]["paths"],"status":"passed","report":{}}
        }),
    )?;
    let output = child.wait_with_output()?;
    assert!(
        !output.status.success() && output.stdout.is_empty(),
        "{output:?}"
    );
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("recorded inputs exceed the byte limit"),
        "{output:?}"
    );
    Ok(())
}

#[cfg(feature = "linked-program")]
fn check_model_readback(
    root: &Path,
    model_path: &str,
    execute: &impl Fn(&[&str]),
) -> Result<(), Box<dyn std::error::Error>> {
    use serde_json::{Value, json};
    use std::process::Stdio;

    let run = |args: &[&str], input: &Value| {
        let mut child = Command::new(env!("CARGO_BIN_EXE_aitia"))
            .current_dir(root)
            .args(["jj", "commit"])
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap();
        serde_json::to_writer(child.stdin.take().unwrap(), input).unwrap();
        child.wait_with_output().unwrap()
    };
    let read = |args: &[&str], input: &Value| -> Value {
        let output = run(args, input);
        assert!(output.status.success(), "{output:?}");
        serde_json::from_slice(&output.stdout).unwrap()
    };
    let mut draft = json!({
        "proposal": {"identity":"model-review","reference":"RFC-1","type":"docs","scope":"model",
            "summary":"Record model evidence","rationale":"The recorded model is independently parsed",
            "language":"en","languageSource":"work.org"},
        "narration":{"change":"Record the model audit.","evidence":[{"obligation":"SWE-084","text":"Audited the recorded Git configuration."}],"open":[]},
        "org":"* Model review\n:PROPERTIES:\n:AITIA_SUPPORT: SWE-084\n:END:\n","context":""
    });
    let preview = read(&["preview"], &draft);
    draft["context"] = preview["review"]["context"].clone();
    let prepared = read(&["prepare"], &draft);
    let written = read(
        &["apply"],
        &json!({"draft":draft,"attempt":prepared["attempt"]}),
    );
    let revision = written["receipt"]["resulting_commit"].as_str().unwrap();
    let args = ["evidence", revision, "--gql"];
    let evidence = read(&args, &written);
    let report = evidence["observations"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["method"] == "sysml.parse")
        .unwrap();
    assert_eq!(report["report"]["documents"], json!([model_path]));
    assert_eq!(report["report"], written["modelCheck"]["report"]);
    let query = &evidence["lineage"]["query"];
    assert_eq!(query["status"], "executed");
    let model = &query["modelEvidence"];
    assert_eq!(model["revision"], revision);
    assert_eq!(model["complete"], false);
    assert_eq!(model["actionAuthority"], false);
    assert!(model["gql"].as_str().unwrap().contains("parsed_by"));
    assert_eq!(
        model["rows"],
        json!([{"path":model_path,"method":"sysml.parse"}])
    );
    let parsed_edges: Vec<_> = evidence["lineage"]["edges"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|edge| edge["relation"] == "parsed_by")
        .collect();
    assert_eq!(
        parsed_edges,
        [&json!({
            "from": format!("{revision}#path:{model_path}"),
            "to": format!("{revision}#report:sysml.parse"),
            "relation": "parsed_by",
        })]
    );
    let mut forged = written.clone();
    forged["modelCheck"]["report"]["modelHash"] = json!("forged");
    assert!(!run(&args, &forged).status.success());
    let mut unrelated = written.clone();
    unrelated["modelCheck"]["paths"] = json!([NAME]);
    assert!(!run(&args, &unrelated).status.success());
    let mut missing = written.clone();
    missing.as_object_mut().unwrap().remove("modelCheck");
    let without_archive = read(&args, &missing);
    assert_eq!(
        without_archive["lineage"]["query"]["modelEvidence"]["rows"],
        json!([])
    );
    assert!(
        without_archive["missingReports"]
            .as_array()
            .unwrap()
            .contains(&json!("sysml.parse"))
    );
    assert!(
        without_archive["lineage"]["edges"]
            .as_array()
            .unwrap()
            .iter()
            .all(|edge| edge["relation"] != "parsed_by")
    );
    execute(&["new", "-m", "change the model after application"]);
    std::fs::write(root.join(model_path), "package Broken {")?;
    execute(&["describe", "-m", "record invalid later model"]);
    assert_eq!(read(&args, &written), evidence);

    std::fs::write(
        root.join(".agents/aita/project.json"),
        r#"{"schemaVersion":1,"services":{"sysml":{"enable":true,"parse":false}}}"#,
    )?;
    execute(&["describe", "-m", "record the model with parsing disabled"]);
    let cut = aitia_jj::observe_workspace(root)?;
    let description = "Model parsing disabled";
    let receipt = aitia_jj::prepare_description(&cut, description)?.publish(|_| true)?;
    let disabled_args = ["evidence", &receipt.resulting_commit, "--gql"];
    let mut disabled = json!({
        "receipt":receipt,
        "cut":{"workspace":cut.workspace_name(),"change":cut.change_id(),
               "operation":cut.operation_id(),"commit":cut.commit_id(),
               "tree":cut.tree_id(),"parents":cut.parent_ids()},
        "review":{"description":description},
        "executions":[]
    });
    let result = read(&disabled_args, &disabled);
    assert_eq!(result["observations"], json!([]));
    assert_eq!(result["missingReports"], json!([]));
    disabled["modelCheck"] = written["modelCheck"].clone();
    let rejected = run(&disabled_args, &disabled);
    assert!(
        !rejected.status.success() && rejected.stdout.is_empty(),
        "{rejected:?}"
    );
    assert!(
        String::from_utf8_lossy(&rejected.stderr)
            .contains("Archived SysML observation is out of scope"),
        "{rejected:?}"
    );
    assert_eq!(read(&args, &written), evidence);
    Ok(())
}
