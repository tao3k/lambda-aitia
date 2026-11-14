// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use aitia_runtime::{
    AgentInputSupport, ContextDelivery, ContextDeliveryAttempt, ContextTransportFailure,
    RecordedAgentInput,
};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::io::Write;
use std::process::Command;

const RECORDED_PROJECT: &str = "agent-input-jj-qualification";

#[test]
#[ignore = "requires JJ and a local loopback Provider"]
fn delivers_only_the_agent_input_packet_that_scheme_checked() {
    if let Some(checkpoint) = std::env::var_os("AITIA_CONTEXT_RESTART_FIXTURE") {
        check_restored_context(checkpoint.as_ref());
        println!("AITIA-CONTEXT-RESTART-OK");
        return;
    }

    let jj =
        std::env::var_os("AITIA_JJ_BIN").expect("set AITIA_JJ_BIN for Agent input qualification");
    let source = json!([
        {"role": "developer", "content": [{"type": "input_text", "text": "Use read-only tools"}]},
        {"type": "function_call", "call_id": "call-1", "name": "inspect", "arguments": "{\"path\":\"README.org\"}"},
        {"type": "function_call_output", "call_id": "call-1", "output": "present"},
        {"role": "assistant", "content": "Summary may be changed"},
    ]);
    let mut projected = source.clone();
    projected[3]["content"] = json!("Short summary");
    aitia_runtime::with_linked_program(|program| {
        let packet = projected.to_string();
        let mut consumed = Vec::new();
        assert_eq!(
            program.with_verified_agent_input(&source, &projected, |accepted| {
                consumed.write_all(accepted.as_bytes()).unwrap();
                accepted.len()
            })?,
            Some(packet.len())
        );
        assert_eq!(consumed, packet.as_bytes());

        let cases = [
            json!([source[0], source[2], source[3]]),
            json!([source[0], source[1], source[3]]),
            json!([source[0], source[3]]),
            json!([source[1], source[2], source[3]]),
            json!([source[0], source[1], source[1], source[2]]),
            json!([source[0], source[2], source[1]]),
        ];
        for invalid in cases {
            assert_eq!(
                program.with_verified_agent_input(&source, &invalid, |_| {
                    panic!("unverified packet reached the consumer")
                })?,
                None::<()>
            );
        }
        projected[2]["output"] = json!("substituted after verification");
        assert_eq!(
            program.with_verified_agent_input(&source, &projected, |_| {
                panic!("a substituted packet reached the consumer")
            })?,
            None::<()>
        );
        projected[2] = source[2].clone();
        projected[0]["content"][0]["text"] = json!("Use write tools");
        assert_eq!(
            program.with_verified_agent_input(&source, &projected, |_| {
                panic!("a weakened constraint reached the consumer")
            })?,
            None::<()>
        );
        check_live_context_transport(&program, &source);
        let repo = tempfile::tempdir().unwrap();
        let run_jj = |arguments: &[&str]| {
            let result = Command::new(&jj)
                .current_dir(repo.path())
                .args([
                    "--config",
                    "user.name='AITIA Test'",
                    "--config",
                    "user.email='test@example.invalid'",
                ])
                .args(arguments)
                .output()
                .unwrap();
            assert!(
                result.status.success(),
                "{}",
                String::from_utf8_lossy(&result.stderr)
            );
        };
        run_jj(&["git", "init", "--colocate"]);
        let history_path = "agent-input.json";
        let history = repo.path().join(history_path);
        std::fs::write(&history, source.to_string()).unwrap();
        run_jj(&["describe", "-m", "record the agent input"]);
        let cut = aitia_jj::observe_workspace(repo.path()).unwrap();
        std::fs::write(&history, projected.to_string()).unwrap();
        let original = source.to_string();
        let mut accepted = source.clone();
        accepted[3]["content"] = json!("Accepted summary");
        let (provider_request, provider_receipt) =
            check_provider_handoff(&program, &cut, history_path, &accepted);
        let RecordedAgentInput::Delivered {
            result: delivered,
            observation,
        } = program
            .with_verified_recorded_agent_input(
                RECORDED_PROJECT,
                &cut,
                history_path,
                &accepted,
                |packet| Ok::<_, std::io::Error>(packet.to_owned()),
            )
            .unwrap()
        else {
            panic!("expected a recorded delivery");
        };
        assert_eq!(delivered, accepted.to_string());
        assert_eq!(observation.project(), RECORDED_PROJECT);
        assert_eq!(observation.cut(), &cut);
        assert_eq!(observation.history_path(), history_path);
        assert_eq!(
            observation.source_digest(),
            format!("sha256:{:x}", Sha256::digest(original.as_bytes()))
        );
        assert_eq!(
            observation.packet_digest(),
            format!("sha256:{:x}", Sha256::digest(delivered.as_bytes()))
        );
        assert_ne!(observation.source_digest(), observation.packet_digest());
        observation.require_current().unwrap();
        let AgentInputSupport::Assessed(support) = program
            .assess_recorded_agent_input(
                RECORDED_PROJECT,
                cut.workspace_root(),
                &observation,
                &delivered,
            )
            .unwrap()
        else {
            panic!("expected current Host support");
        };
        assert_eq!(support["revision"], cut.commit_id());
        assert_eq!(support["scope"], history_path);
        assert_eq!(support["subject"], RECORDED_PROJECT);
        let other = tempfile::tempdir().unwrap();
        run_jj(&["git", "init", "--colocate", other.path().to_str().unwrap()]);
        for (project, workspace) in [
            ("other-project", repo.path()),
            (RECORDED_PROJECT, other.path()),
        ] {
            assert!(
                program
                    .assess_recorded_agent_input(project, workspace, &observation, &delivered)
                    .is_err()
            );
        }
        assert_eq!(support["complete"], true, "{support}");
        assert_eq!(support["releaseAuthorized"], false);
        assert_eq!(support["assumptionAssessments"], json!([]));
        assert_eq!(support["remaining"], json!([]));
        assert_eq!(support["witnesses"].as_array().unwrap().len(), 1);
        let witness = &support["witnesses"][0];
        assert_eq!(witness["obligation"], "preserve-required-input-fragment");
        assert_eq!(witness["method"], "integration-test");
        assert_eq!(witness["scope"], history_path);
        assert_eq!(witness["capability"], "agent-input-correspondence");
        assert_eq!(witness["relation"], "observed-support");
        assert!(
            witness["outcomeDigest"]
                .as_str()
                .is_some_and(|digest| digest.starts_with("sha256:") && digest.len() == 71)
        );
        assert_eq!(witness["tool"], "agent-input-correspondence");
        assert_eq!(
            witness["inputs"],
            json!([
                "artifact/agent-input-history",
                "artifact/delivered-agent-input"
            ])
        );
        // This other packet still corresponds, but was not delivered.
        assert!(
            program
                .assess_recorded_agent_input(
                    RECORDED_PROJECT,
                    cut.workspace_root(),
                    &observation,
                    &source.to_string()
                )
                .is_err()
        );

        let failed = program
            .with_verified_recorded_agent_input(
                RECORDED_PROJECT,
                &cut,
                history_path,
                &accepted,
                |_| Err::<(), _>("consumer rejected delivery"),
            )
            .unwrap();
        assert!(matches!(
            failed,
            RecordedAgentInput::ConsumerFailed("consumer rejected delivery")
        ));

        let RecordedAgentInput::Delivered {
            result: delivered_during_rewrite,
            observation: historical,
        } = program
            .with_verified_recorded_agent_input(
                RECORDED_PROJECT,
                &cut,
                history_path,
                &accepted,
                |packet| {
                    run_jj(&["describe", "-m", "record the changed constraint"]);
                    Ok::<_, std::io::Error>(packet.to_owned())
                },
            )
            .unwrap()
        else {
            panic!("expected a historical delivery");
        };
        assert_eq!(delivered_during_rewrite, delivered);
        for previous in [observation, historical] {
            assert!(matches!(
                previous.require_current(),
                Err(aitia_jj::JjObservationError::ChangedOperation)
            ));
            assert!(matches!(
                program
                    .assess_recorded_agent_input(
                        RECORDED_PROJECT,
                        cut.workspace_root(),
                        &previous,
                        &delivered
                    )
                    .unwrap(),
                AgentInputSupport::Reopened
            ));
        }
        assert!(matches!(
            program
                .assess_recorded_agent_input(
                    RECORDED_PROJECT,
                    cut.workspace_root(),
                    &provider_receipt,
                    &provider_request
                )
                .unwrap(),
            AgentInputSupport::Reopened
        ));
        let rewritten = aitia_jj::observe_workspace(repo.path()).unwrap();
        assert_eq!(cut.change_id(), rewritten.change_id());
        assert_ne!(cut.commit_id(), rewritten.commit_id());
        let refused = || panic!("an unbound packet reached the consumer");
        let old = program
            .with_verified_recorded_agent_input(
                RECORDED_PROJECT,
                &cut,
                history_path,
                &source,
                |_| -> Result<(), ()> { refused() },
            )
            .unwrap_err();
        assert!(matches!(
            old.downcast_ref::<aitia_jj::JjObservationError>(),
            Some(aitia_jj::JjObservationError::ChangedOperation)
        ));
        assert!(matches!(
            program
                .with_verified_recorded_agent_input(
                    RECORDED_PROJECT,
                    &rewritten,
                    history_path,
                    &source,
                    |_| -> Result<(), ()> { refused() }
                )
                .unwrap(),
            RecordedAgentInput::Refused
        ));
        Ok(())
    })
    .unwrap();
}

fn check_provider_handoff(
    program: &aitia_runtime::AitiaProgram<'_>,
    cut: &aitia_jj::WorkspaceCut,
    history_path: &str,
    projected: &serde_json::Value,
) -> (String, aitia_runtime::RecordedAgentInputObservation) {
    let mut settings = serde_json::Map::new();
    settings.insert("model".into(), json!("fixture-provider"));
    settings.insert("instructions".into(), json!("Keep tool access read-only"));
    let mut altered = projected.clone();
    altered[2]["output"] = json!("substituted result");
    let unexpected_send =
        |_: &str| -> std::io::Result<String> { panic!("unverified request was sent") };
    assert!(matches!(
        program
            .with_verified_recorded_provider_request(
                RECORDED_PROJECT,
                cut,
                history_path,
                &settings,
                altered,
                unexpected_send
            )
            .unwrap(),
        RecordedAgentInput::Refused
    ));
    settings.insert("input".into(), json!([]));
    assert!(matches!(
        program
            .with_verified_recorded_provider_request(
                RECORDED_PROJECT,
                cut,
                history_path,
                &settings,
                projected.clone(),
                unexpected_send
            )
            .unwrap(),
        RecordedAgentInput::Refused
    ));
    settings.remove("input");

    let RecordedAgentInput::Delivered {
        result,
        observation,
    } = program
        .with_verified_recorded_provider_request(
            RECORDED_PROJECT,
            cut,
            history_path,
            &settings,
            projected.clone(),
            send_to_loopback_provider,
        )
        .unwrap()
    else {
        panic!("expected provider delivery");
    };
    let request: serde_json::Value = serde_json::from_str(&result).unwrap();
    assert_eq!(request["input"], *projected);
    assert_eq!(request["model"], settings["model"]);
    assert_eq!(request["instructions"], settings["instructions"]);
    let AgentInputSupport::Assessed(support) = program
        .assess_recorded_agent_input(
            RECORDED_PROJECT,
            cut.workspace_root(),
            &observation,
            &result,
        )
        .unwrap()
    else {
        panic!("expected Host support at the current cut");
    };
    assert_eq!(support["complete"], true, "{support}");
    assert_eq!(support["releaseAuthorized"], false);
    assert_eq!(support["subject"], RECORDED_PROJECT);
    assert_eq!(
        observation.packet_digest(),
        format!("sha256:{:x}", Sha256::digest(result.as_bytes()))
    );
    let mut substituted = request;
    substituted["instructions"] = json!("Use write tools");
    assert!(
        program
            .assess_recorded_agent_input(
                RECORDED_PROJECT,
                cut.workspace_root(),
                &observation,
                &substituted.to_string()
            )
            .is_err()
    );
    (result, observation)
}

const CONTEXT_PROJECT: &str = "agent-input-qualification";

fn check_live_context_transport(
    program: &aitia_runtime::AitiaProgram<'_>,
    history: &serde_json::Value,
) {
    let source = |input: &serde_json::Value| {
        format!(
            ":PROPERTIES:\n:ID: source\n:CONTRACT_ID: context.evidence-source.v1\n:CONTRACT_REVISION: 1\n:END:\n\n#+title: Provider input\n\n* Selected history\n:PROPERTIES:\n:ID: history\n:AGENT_INPUT: {input}\n:END:\n"
        )
    };
    let mut settings = serde_json::Map::new();
    settings.insert("model".into(), json!("fixture-provider"));
    let original = source(history);
    assert!(program.context_checkpoint().is_err());
    program.bind_context_project(CONTEXT_PROJECT).unwrap();
    program.bind_context_project(CONTEXT_PROJECT).unwrap();
    assert!(program.bind_context_project("other-project").is_err());
    program
        .publish_context_source("provider-context", 1, &original)
        .unwrap();
    let selected = program
        .observe_context_element("provider-context", "history")
        .unwrap();
    let no_send =
        |_: &ContextDeliveryAttempt, _: &str| -> Result<(), ContextTransportFailure<()>> {
            panic!("unverified request was sent")
        };
    assert!(matches!(
        program
            .deliver_context_request("unissued-reference", "missing", &settings, history, no_send)
            .unwrap(),
        ContextDelivery::Refused
    ));
    assert!(matches!(
        program
            .deliver_context_request(&selected, "invalid\r\nid", &settings, history, no_send)
            .unwrap(),
        ContextDelivery::Refused
    ));
    let mut changed = history.clone();
    changed[0]["content"] = json!("Do not use tools");
    assert!(matches!(
        program
            .deliver_context_request(&selected, "substituted", &settings, &changed, no_send)
            .unwrap(),
        ContextDelivery::Refused
    ));
    assert!(matches!(
        program
            .deliver_context_request(&selected, "closed", &settings, history, |_, _| {
                Err::<(), _>(ContextTransportFailure::NotSent("closed"))
            })
            .unwrap(),
        ContextDelivery::NotSent("closed")
    ));
    let ContextDelivery::Delivered { result, receipt } = program
        .deliver_context_request(&selected, "success", &settings, history, |_, body| {
            send_to_loopback_provider(body).map_err(ContextTransportFailure::Indeterminate)
        })
        .unwrap()
    else {
        panic!("expected the live Context request to reach the provider");
    };
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&result).unwrap()["input"],
        *history
    );
    let AgentInputSupport::Assessed(support) = program.assess_context_delivery(&receipt).unwrap()
    else {
        panic!("expected a current Host witness");
    };
    assert_eq!(support["revision"], selected);
    assert_eq!(support["scope"], "provider-context/history");
    assert_eq!(support["complete"], true, "{support}");
    assert_eq!(support["releaseAuthorized"], false);
    assert_eq!(
        support["subject"],
        format!("sha256:{:x}", Sha256::digest(result.as_bytes()))
    );

    let AgentInputSupport::Assessed(repeated) = program.assess_context_delivery(&receipt).unwrap()
    else {
        panic!("expected the same delivery to remain assessable");
    };
    assert_eq!(repeated, support);

    let mut old_record = tempfile::NamedTempFile::new().unwrap();
    let mut provider_record = None;
    let ContextDelivery::Indeterminate { error, pending } = program
        .deliver_context_request(
            &selected,
            "lost-ack",
            &settings,
            history,
            |attempt, body| {
                write_attempt_record(&mut old_record, attempt);
                provider_record =
                    Some(loopback_exchange(body, Some(attempt.identity()), false).unwrap());
                Err::<(), _>(ContextTransportFailure::Indeterminate("response lost"))
            },
        )
        .unwrap()
    else {
        panic!("a lost acknowledgement must leave the delivery indeterminate");
    };
    assert_eq!(error, "response lost");
    let (received, identity) = provider_record.unwrap();
    let digest = format!("sha256:{:x}", Sha256::digest(received.as_bytes()));
    assert_eq!(pending.attempt().body_digest(), digest);
    let pending = pending.confirm("other-attempt", &digest).unwrap_err();
    let pending = pending.confirm(&identity, "sha256:wrong-body").unwrap_err();
    let reconciled = pending.confirm(&identity, &digest).unwrap();
    assert_eq!(reconciled.attempt().identity(), "lost-ack");
    assert_eq!(reconciled.attempt().body_digest(), digest);
    let AgentInputSupport::Assessed(recovered_support) =
        program.assess_context_delivery(&reconciled).unwrap()
    else {
        panic!("the independently observed matching record should reconcile delivery");
    };
    assert_eq!(recovered_support["subject"], digest);
    assert_eq!(recovered_support["complete"], true);
    assert_eq!(recovered_support["releaseAuthorized"], false);

    let old_checkpoint = program.context_checkpoint().unwrap();
    program
        .publish_context_source("provider-context", 2, &source(&changed))
        .unwrap();
    for earlier in [&receipt, &reconciled] {
        assert!(matches!(
            program.assess_context_delivery(earlier).unwrap(),
            AgentInputSupport::Reopened
        ));
    }
    assert!(matches!(
        program
            .deliver_context_request(&selected, "stale", &settings, history, no_send)
            .unwrap(),
        ContextDelivery::Refused
    ));
    let new_selection = program
        .observe_context_element("provider-context", "history")
        .unwrap();
    assert_ne!(new_selection, selected);
    let ContextDelivery::Delivered {
        receipt: racing, ..
    } = program
        .deliver_context_request(&new_selection, "racing", &settings, &changed, |_, body| {
            let received =
                send_to_loopback_provider(body).map_err(ContextTransportFailure::Indeterminate)?;
            program
                .withdraw_context_source("provider-context", 3)
                .unwrap();
            Ok(received)
        })
        .unwrap()
    else {
        panic!("expected the racing delivery to retain a historical receipt");
    };
    assert!(matches!(
        program.assess_context_delivery(&racing).unwrap(),
        AgentInputSupport::Reopened
    ));
    program
        .publish_context_source("provider-context", 4, &original)
        .unwrap();
    assert!(matches!(
        program.assess_context_delivery(&receipt).unwrap(),
        AgentInputSupport::Reopened
    ));
    let current = program
        .observe_context_element("provider-context", "history")
        .unwrap();
    assert_ne!(current, selected);
    let mut new_record = tempfile::NamedTempFile::new().unwrap();
    let mut provider_observation = None;
    assert!(matches!(
        program
            .deliver_context_request(
                &current,
                "restart-ack",
                &settings,
                history,
                |attempt, body| {
                    write_attempt_record(&mut new_record, attempt);
                    provider_observation =
                        Some(loopback_exchange(body, Some(attempt.identity()), false).unwrap());
                    Err::<(), _>(ContextTransportFailure::Indeterminate(
                        "lost before restart",
                    ))
                }
            )
            .unwrap(),
        ContextDelivery::Indeterminate { .. }
    ));
    let (observed_body, observed_attempt) = provider_observation.unwrap();
    let checkpoint = program.context_checkpoint().unwrap();
    let digest = format!("sha256:{:x}", Sha256::digest(checkpoint.as_bytes()));
    assert!(
        program
            .restore_context_checkpoint(&checkpoint, &digest)
            .is_err()
    );
    let fixture = tempfile::NamedTempFile::new().unwrap();
    std::fs::write(
        fixture.path(),
        json!({
            "checkpoint": checkpoint,
            "oldCheckpoint": old_checkpoint,
            "digest": digest,
            "historical": selected,
            "current": current,
            "input": history,
            "delivery": delivery_fixture(&new_record, &observed_attempt, &observed_body),
            "oldDelivery": delivery_fixture(&old_record, &identity, &received),
        })
        .to_string(),
    )
    .unwrap();
    let restart = Command::new(std::env::current_exe().unwrap())
        .args([
            "--ignored",
            "--exact",
            "delivers_only_the_agent_input_packet_that_scheme_checked",
            "--nocapture",
        ])
        .env("AITIA_CONTEXT_RESTART_FIXTURE", fixture.path())
        .output()
        .unwrap();
    assert!(
        restart.status.success()
            && String::from_utf8_lossy(&restart.stdout)
                .lines()
                .any(|line| line == "AITIA-CONTEXT-RESTART-OK"),
        "restart failed: {}\n{}",
        String::from_utf8_lossy(&restart.stdout),
        String::from_utf8_lossy(&restart.stderr)
    );

    // Org can retain a control character that the Lab recovery codec refuses.
    // The live catalog must not export an unusable checkpoint as successful.
    let nonportable = format!("{original}\nContent \u{b} after a vertical tab.\n");
    program
        .publish_context_source("checkpoint-control", 1, &nonportable)
        .unwrap();
    assert!(program.context_checkpoint().is_err());
}

fn write_attempt_record(file: &mut tempfile::NamedTempFile, attempt: &ContextDeliveryAttempt) {
    assert_eq!(attempt.project(), CONTEXT_PROJECT);
    file.write_all(attempt.recovery_record().unwrap().as_bytes())
        .unwrap();
    file.as_file().sync_all().unwrap();
}

fn delivery_fixture(
    file: &tempfile::NamedTempFile,
    identity: &str,
    body: &str,
) -> serde_json::Value {
    let record = std::fs::read_to_string(file.path()).unwrap();
    json!({
        "record": record,
        "recordDigest": format!("sha256:{:x}", Sha256::digest(record.as_bytes())),
        "identity": identity,
        "body": body,
        "bodyDigest": format!("sha256:{:x}", Sha256::digest(body.as_bytes())),
    })
}

fn check_restored_context(path: &std::path::Path) {
    let fixture: serde_json::Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    let text = |key: &str| fixture[key].as_str().unwrap();
    aitia_runtime::with_linked_program(|program| {
        program.bind_context_project(CONTEXT_PROJECT)?;
        let checkpoint = text("checkpoint");
        let digest = text("digest");
        let mut foreign_checkpoint: serde_json::Value = serde_json::from_str(checkpoint).unwrap();
        foreign_checkpoint["project"] = json!("other-project");
        let foreign_checkpoint = foreign_checkpoint.to_string();
        let foreign_digest = format!("sha256:{:x}", Sha256::digest(foreign_checkpoint.as_bytes()));
        assert!(
            program
                .restore_context_checkpoint(&foreign_checkpoint, &foreign_digest)
                .is_err()
        );
        assert!(
            program
                .restore_context_checkpoint(text("oldCheckpoint"), digest)
                .is_err()
        );
        let malformed = "not a Lab recovery capsule";
        let malformed_digest = format!("sha256:{:x}", Sha256::digest(malformed.as_bytes()));
        assert!(
            program
                .restore_context_checkpoint(malformed, &malformed_digest)
                .is_err()
        );
        fn get<'a>(value: &'a serde_json::Value, key: &str) -> &'a str {
            value[key].as_str().unwrap()
        }
        let recover = |value: &serde_json::Value| {
            program
                .recover_context_delivery(
                    get(value, "record"),
                    get(value, "recordDigest"),
                    get(value, "body"),
                    get(value, "identity"),
                    get(value, "bodyDigest"),
                )
                .unwrap()
        };
        assert!(recover(&fixture["delivery"]).is_none());
        assert!(checkpoint.starts_with("{\"project\":"));
        let fields: serde_json::Value = serde_json::from_str(checkpoint).unwrap();
        let reordered = format!(
            "{{\"journal\":{},\"project\":{}}}",
            fields["journal"], fields["project"]
        );
        assert_ne!(reordered, checkpoint);
        let reordered_digest = format!("sha256:{:x}", Sha256::digest(reordered.as_bytes()));
        program
            .restore_context_checkpoint(&reordered, &reordered_digest)
            .unwrap();
        assert_eq!(program.context_checkpoint()?, checkpoint);

        assert!(recover(&fixture["oldDelivery"]).is_none());
        let delivery = &fixture["delivery"];
        for field in ["recordDigest", "identity", "body", "bodyDigest"] {
            let mut substituted = delivery.clone();
            substituted[field] = json!("substituted");
            assert!(recover(&substituted).is_none(), "{field}");
        }
        let mut foreign = delivery.clone();
        let mut record: serde_json::Value = serde_json::from_str(get(delivery, "record")).unwrap();
        record["project"] = json!("other-project");
        let record = record.to_string();
        foreign["recordDigest"] = json!(format!("sha256:{:x}", Sha256::digest(record.as_bytes())));
        foreign["record"] = json!(record);
        assert!(recover(&foreign).is_none());

        let receipt = recover(delivery).expect("matching Provider record after restart");
        assert_eq!(receipt.attempt().project(), CONTEXT_PROJECT);
        let AgentInputSupport::Assessed(assessment) =
            program.assess_context_delivery(&receipt).unwrap()
        else {
            panic!("expected current support after reconciliation");
        };
        assert_eq!(assessment["revision"], text("current"));
        assert_eq!(assessment["subject"], delivery["bodyDigest"]);
        assert_eq!(assessment["releaseAuthorized"], false);
        assert_eq!(receipt.attempt().identity(), "restart-ack");

        let settings = serde_json::Map::new();
        let input = &fixture["input"];
        assert!(matches!(
            program.deliver_context_request(
                text("historical"),
                "historical",
                &settings,
                input,
                |_, _| -> Result<(), ContextTransportFailure<()>> {
                    panic!("historical Context was delivered after restart")
                }
            )?,
            ContextDelivery::Refused
        ));
        let ContextDelivery::Delivered { receipt, .. } = program.deliver_context_request(
            text("current"),
            "restored",
            &settings,
            input,
            |_, body| Ok::<_, ContextTransportFailure<()>>(body.to_owned()),
        )?
        else {
            panic!("restored current observation did not support a fresh delivery");
        };
        let AgentInputSupport::Assessed(support) =
            program.assess_context_delivery(&receipt).unwrap()
        else {
            panic!("fresh delivery after restart did not support assessment");
        };
        assert_eq!(support["revision"], text("current"));
        assert_eq!(support["complete"], true);
        assert_eq!(support["releaseAuthorized"], false);
        Ok(())
    })
    .unwrap();
}

fn send_to_loopback_provider(body: &str) -> std::io::Result<String> {
    loopback_exchange(body, None, true).map(|(body, _)| body)
}

fn loopback_exchange(
    body: &str,
    attempt: Option<&str>,
    acknowledge: bool,
) -> std::io::Result<(String, String)> {
    use std::io::{BufRead, BufReader, Read};
    use std::net::{TcpListener, TcpStream};
    use std::time::Duration;

    let timeout = Duration::from_secs(3);
    let listener = TcpListener::bind(("127.0.0.1", 0))?;
    let address = listener.local_addr()?;
    let mut sender = TcpStream::connect_timeout(&address, timeout)?;
    sender.set_read_timeout(Some(timeout))?;
    sender.set_write_timeout(Some(timeout))?;
    let provider = std::thread::spawn(move || -> std::io::Result<(String, String)> {
        let (stream, _) = listener.accept()?;
        stream.set_read_timeout(Some(timeout))?;
        stream.set_write_timeout(Some(timeout))?;
        let mut request = BufReader::new(stream);
        let mut line = String::new();
        request.read_line(&mut line)?;
        assert_eq!(line, "POST /responses HTTP/1.1\r\n");
        let mut length = None;
        let mut identity = String::new();
        loop {
            line.clear();
            assert_ne!(request.read_line(&mut line)?, 0);
            if line == "\r\n" {
                break;
            }
            if let Some(value) = line.strip_prefix("Content-Length: ") {
                length = Some(value.trim().parse::<usize>().unwrap());
            }
            if let Some(value) = line.strip_prefix("X-Attempt: ") {
                identity = value.trim().to_owned();
            }
        }
        let mut received = vec![0; length.expect("request length")];
        request.read_exact(&mut received)?;
        if acknowledge {
            request
                .get_mut()
                .write_all(b"HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")?;
        }
        Ok((String::from_utf8(received).unwrap(), identity))
    });
    write!(
        sender,
        "POST /responses HTTP/1.1\r\nHost: {address}\r\nContent-Type: application/json\r\nContent-Length: {}\r\n",
        body.len()
    )?;
    if let Some(attempt) = attempt {
        write!(sender, "X-Attempt: {attempt}\r\n")?;
    }
    sender.write_all(b"\r\n")?;
    sender.write_all(body.as_bytes())?;
    let mut response = String::new();
    sender.read_to_string(&mut response)?;
    if acknowledge {
        assert!(response.starts_with("HTTP/1.1 204 "));
    } else {
        assert!(response.is_empty());
    }
    let (received, identity) = provider.join().expect("loopback provider")?;
    assert_eq!(received.as_bytes(), body.as_bytes());
    Ok((received, identity))
}
