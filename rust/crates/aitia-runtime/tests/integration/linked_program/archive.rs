// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use super::json_output;
use serde_json::{Value, json};
use std::{path::Path, process::Output};

pub(super) fn assert_applied_readback(
    run: &impl Fn(&[&str], &Value) -> Output,
    revision: &str,
    base_revision: &str,
    attempt: &Value,
    written: &Value,
    workspace: &Path,
) -> (Value, Value, Value) {
    let evidence_args = ["jj", "commit", "evidence", revision];
    let mut evidence = json_output(run(
        &["jj", "commit", "evidence", revision, "--gql"],
        written,
    ));
    let query = evidence["lineage"]
        .as_object_mut()
        .unwrap()
        .remove("query")
        .unwrap();
    assert_eq!(query["status"], "executed");
    assert_eq!(query["revision"], revision);
    assert_eq!(query["complete"], false);
    assert_eq!(query["actionAuthority"], false);
    assert!(query["gql"].as_str().unwrap().contains("enumerated_by"));
    let reports = &query["verifiedReports"];
    assert_eq!(reports["revision"], revision);
    let report_rows = reports["rows"].as_array().unwrap();
    assert_eq!(report_rows.len(), 2);
    for method in ["jj.recorded-change", "jj.configuration-audit"] {
        assert!(report_rows.contains(&json!({"method": method})));
    }
    assert!(
        query["rows"]
            .as_array()
            .unwrap()
            .contains(&json!({"path":"change.txt","method":"jj.recorded-change"}))
    );
    let inputs = &query["projectInputs"];
    assert_eq!(inputs["revision"], revision);
    assert_eq!(inputs["complete"], false);
    assert_eq!(inputs["actionAuthority"], false);
    assert!(inputs["gql"].as_str().unwrap().contains("reads_config"));
    assert!(
        inputs["rows"]
            .as_array()
            .unwrap()
            .contains(&json!({"path":".agents/aita/project.json","changed":true}))
    );
    assert_eq!(query["modelEvidence"]["rows"], json!([]));
    let sources = &query["policySources"];
    assert_eq!(sources["revision"], revision);
    assert!(
        sources["gql"]
            .as_str()
            .unwrap()
            .contains("has_policy_source")
    );
    assert!(
        sources["rows"]
            .as_array()
            .unwrap()
            .contains(&json!({"path":".agents/aita/work.org","changed":false}))
    );
    // The caller compares this response with the plain read after advancing
    // the workspace. The archived revision must survive both changes.
    assert_eq!(evidence["revision"], revision);
    assert_eq!(evidence["original"], written["cut"]);
    assert_eq!(evidence["description"], written["review"]["description"]);
    assert_eq!(evidence["missingReports"], json!([]));
    assert_eq!(
        query["engineeringReference"]["rows"],
        json!([{"engineeringId":"WORK-1","element":"work-1","path":".agents/aita/rebound.org"}])
    );
    for context in [Value::Null, json!(format!("sha256:{}", "0".repeat(64)))] {
        let mut stale_archive = written.clone();
        stale_archive["review"]["context"] = context;
        let refused = run(&evidence_args, &stale_archive);
        assert_eq!(refused.status.code(), Some(1), "{refused:?}");
        assert!(refused.stdout.is_empty(), "{refused:?}");
        assert!(
            String::from_utf8_lossy(&refused.stderr)
                .contains("Archived review context differs from the applied review"),
            "{refused:?}"
        );
    }
    for (field, replacement) in [
        ("summary", "Invent a different title"),
        (
            "rationale",
            "Invent a different rationale while preserving the title",
        ),
    ] {
        let mut forged_proposal = written.clone();
        forged_proposal["proposal"][field] = json!(replacement);
        let refused = run(&evidence_args, &forged_proposal);
        assert!(
            !refused.status.success() && refused.stdout.is_empty(),
            "{refused:?}"
        );
        assert!(
            String::from_utf8_lossy(&refused.stderr)
                .contains("Archived commit proposal differs from the applied review"),
            "{refused:?}"
        );
    }
    let mut forged_proposal = written.clone();
    forged_proposal["proposal"]["source"] = json!("forged.org");
    let refused = run(&evidence_args, &forged_proposal);
    assert!(
        !refused.status.success() && refused.stdout.is_empty(),
        "{refused:?}"
    );
    assert!(
        String::from_utf8_lossy(&refused.stderr).contains("Invalid archived commit proposal"),
        "{refused:?}"
    );
    let mut missing_proposal = written.clone();
    missing_proposal.as_object_mut().unwrap().remove("proposal");
    let refused = run(&evidence_args, &missing_proposal);
    assert_eq!(refused.status.code(), Some(1), "{refused:?}");
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr).contains("Invalid archived commit proposal"),
        "{refused:?}"
    );
    let recovered = json_output(run(
        &["jj", "commit", "recover"],
        &json!({"attempt": attempt}),
    ));
    let mut recovered_evidence = json_output(run(
        &["jj", "commit", "evidence", revision, "--gql"],
        &recovered,
    ));
    let recovered_query = recovered_evidence["lineage"]
        .as_object_mut()
        .unwrap()
        .remove("query")
        .unwrap();
    assert_recovered_reports(revision, &recovered_query);
    assert_eq!(recovered_query["engineeringReference"]["rows"], json!([]));
    assert_eq!(recovered_evidence["original"], evidence["original"]);
    assert_eq!(recovered_evidence["description"], evidence["description"]);
    assert_eq!(recovered_evidence["observations"], json!([]));
    assert_eq!(
        recovered_evidence["missingReports"],
        json!(["jj.recorded-change", "jj.configuration-audit"])
    );
    let lineage = &evidence["lineage"];
    assert_eq!(lineage["revision"], revision);
    assert_eq!(lineage["dependencyCoverage"], "unknown");
    let nodes = lineage["nodes"].as_array().unwrap();
    let edges = lineage["edges"].as_array().unwrap();
    assert_eq!(
        nodes
            .iter()
            .map(|node| node["id"].as_str().expect("serialized graph identity"))
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        nodes.len()
    );
    let path = |name: &str| nodes.iter().find(|node| node["path"] == name).unwrap();
    let changed = path("change.txt");
    let config = path(".agents/aita/project.json");
    let language_source = path(".agents/aita/work.org");
    assert_eq!(language_source["changed"], false);
    assert!(edges.iter().any(|edge| edge["from"] == revision
        && edge["to"] == language_source["id"]
        && edge["relation"] == "has_policy_source"));
    assert_eq!(changed["changed"], true);
    assert_eq!(changed["after"]["kind"], "file");
    let inventory = nodes
        .iter()
        .find(|node| node["method"] == "jj.recorded-change")
        .unwrap();
    assert!(edges.iter().any(|edge| edge["from"] == changed["id"]
        && edge["to"] == inventory["id"]
        && edge["relation"] == "enumerated_by"));
    assert!(edges.iter().any(|edge| edge["from"] == revision
        && edge["to"] == config["id"]
        && edge["relation"] == "reads_config"));

    for (observed, archived) in evidence["observations"]
        .as_array()
        .unwrap()
        .iter()
        .zip(written["executions"].as_array().unwrap())
    {
        assert_eq!(observed["method"], archived["method"]);
        assert_eq!(observed["report"], archived["report"]);
        assert!(observed.get("obligation").is_none());
    }
    let mut stale_inputs = written.clone();
    stale_inputs["executions"][0]["inputDigest"] = json!("sha256:stale");
    let refused = run(&evidence_args, &stale_inputs);
    assert!(
        !refused.status.success(),
        "accepted a check report from a different input cut"
    );
    assert!(refused.stdout.is_empty(), "{refused:?}");
    assert!(
        String::from_utf8_lossy(&refused.stderr)
            .contains("Archived jj.recorded-change report rejected"),
        "{refused:?}"
    );
    for (field, replacement) in [
        ("requirement", "SWE-084"),
        ("identity", "claimed-authority"),
    ] {
        let mut relabelled = written.clone();
        relabelled["executions"][0][field] = json!(replacement);
        let refused = run(&evidence_args, &relabelled);
        assert!(
            !refused.status.success() && refused.stdout.is_empty(),
            "{refused:?}"
        );
        assert!(
            String::from_utf8_lossy(&refused.stderr)
                .contains("Archived jj.recorded-change report rejected"),
            "{refused:?}"
        );
    }
    let mut forged = written.clone();
    let changed_report = json!([{"path":"forged.txt"}]);
    forged["executions"][0]["report"] = changed_report.clone();
    use sha2::{Digest, Sha256};
    forged["executions"][0]["reportDigest"] = json!(format!(
        "sha256:{:x}",
        Sha256::digest(serde_json::to_vec(&changed_report).unwrap())
    ));
    assert!(!run(&evidence_args, &forged).status.success());

    assert_rejects_extra_reports(run, revision, written, workspace);

    let mut forged = written.clone();
    forged["receipt"]["description"] = json!("Forged description");
    forged["review"]["description"] = forged["receipt"]["description"].clone();
    assert!(!run(&evidence_args, &forged).status.success());
    assert!(
        !run(&["jj", "commit", "evidence", base_revision], written)
            .status
            .success()
    );

    let mut missing = written.clone();
    missing["executions"].as_array_mut().unwrap().remove(1);
    let partial = json_output(run(
        &["jj", "commit", "evidence", revision, "--gql"],
        &missing,
    ));
    assert_eq!(partial["missingReports"], json!(["jj.configuration-audit"]));
    assert_eq!(partial["observations"].as_array().unwrap().len(), 1);
    assert_eq!(
        partial["lineage"]["query"]["verifiedReports"]["rows"],
        json!([{"method":"jj.recorded-change"}])
    );
    let missing_query = &partial["lineage"]["query"]["missingReports"];
    assert_eq!(missing_query["revision"], revision);
    assert_eq!(missing_query["actionAuthority"], false);
    assert_eq!(
        missing_query["rows"],
        json!([{"method":"jj.configuration-audit"}])
    );
    assert!(
        missing_query["gql"]
            .as_str()
            .unwrap()
            .contains("missing_report")
    );
    let missing_report = partial["lineage"]["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|node| node["method"] == "jj.configuration-audit")
        .unwrap();
    assert_eq!(missing_report["state"], "missing");
    let edges = partial["lineage"]["edges"].as_array().unwrap();
    assert!(
        edges
            .iter()
            .any(|edge| edge["to"] == missing_report["id"] && edge["relation"] == "missing_report")
    );
    assert!(!edges.iter().any(|edge| edge["to"] == missing_report["id"]
        && edge["relation"] == "verified_report"));

    (evidence, recovered, recovered_evidence)
}

fn assert_recovered_reports(revision: &str, recovered_query: &Value) {
    assert_eq!(recovered_query["verifiedReports"]["rows"], json!([]));
    let files = &recovered_query["changedFiles"];
    assert_eq!(files["revision"], revision);
    assert_eq!(files["actionAuthority"], false);
    assert!(
        files["rows"]
            .as_array()
            .unwrap()
            .contains(&json!({"path": "change.txt"}))
    );
    let missing = &recovered_query["missingReports"];
    assert_eq!(missing["revision"], revision);
    assert_eq!(missing["actionAuthority"], false);
    let missing_methods: std::collections::BTreeSet<_> = missing["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| row["method"].as_str().unwrap())
        .collect();
    assert_eq!(
        missing_methods,
        ["jj.configuration-audit", "jj.recorded-change"].into()
    );
}

fn assert_rejects_extra_reports(
    run: &impl Fn(&[&str], &Value) -> Output,
    revision: &str,
    written: &Value,
    workspace: &Path,
) {
    let readback_cut = aitia_jj::observe_workspace(workspace).unwrap();
    for (method, diagnostic) in [
        (
            "jj.configuration-audit",
            "Archived jj.configuration-audit report rejected",
        ),
        (
            "unselected.check",
            "Archived check method is outside the recorded policy",
        ),
    ] {
        let mut archive = written.clone();
        let mut extra = written["executions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["method"] == "jj.configuration-audit")
            .unwrap()
            .clone();
        extra["method"] = json!(method);
        archive["executions"].as_array_mut().unwrap().push(extra);
        let refused = run(&["jj", "commit", "evidence", revision, "--gql"], &archive);
        assert_eq!(refused.status.code(), Some(1), "{refused:?}");
        assert!(refused.stdout.is_empty(), "{refused:?}");
        assert!(
            String::from_utf8_lossy(&refused.stderr).contains(diagnostic),
            "{refused:?}"
        );
    }
    assert_eq!(
        aitia_jj::observe_workspace(workspace).unwrap(),
        readback_cut
    );
}
