// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Process-isolated gRPC sidecar gateway (`aitia serve-marlin-grpc`) for
//! `tao3k/marlin-agent-core` (RFC 0024).
//!
//! Serves length-prefixed gRPC frames (`Content-Type: application/grpc+json`)
//! over a persistent `AitiaSession`, avoiding dual Gambit runtime collisions
//! while enforcing Deterministic Engineering SM24/SM25/SM26 control-plane
//! invariants: non-loopback Bearer fail-closed, constant-time non-blank Bearer
//! verification, Operator E-Stop confinement, bounded request frames, and
//! `actionAuthorized: false` on every RPC response.

use super::{Result, defense_audit, err, formal_evidence, sidecar};
use crate::{AitiaSession, MAX_REQUEST_BYTES};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

const SERVICE_PREFIX: &str = "/aitia.marlin.v1.AitiaSidecarGateway/";
const GRPC_USAGE: &str = "usage: aitia serve-marlin-grpc [--bind <host:port>] [--bearer-token <token>] [--estop] [--max-requests <n>]";
const DISALLOWED_DEV_TOKENS: &[&str] = &["dev", "test", "default", "changeme", "token", "secret"];

struct GatewayConfig {
    bind: SocketAddr,
    bearer_token: Option<String>,
    initial_estop: bool,
    max_requests: Option<usize>,
}

fn parse_gateway_config(args: &[String]) -> Result<GatewayConfig> {
    let mut bind_str = "127.0.0.1:50051".to_owned();
    let mut bearer_token = std::env::var("AITIA_GRPC_BEARER_TOKEN").ok();
    let mut initial_estop = false;
    let mut max_requests = None;
    let mut i = 0usize;
    while i < args.len() {
        match args[i].as_str() {
            "--bind" => {
                i += 1;
                bind_str = args.get(i).ok_or_else(|| err(GRPC_USAGE))?.to_owned();
            }
            "--bearer-token" => {
                i += 1;
                bearer_token = Some(args.get(i).ok_or_else(|| err(GRPC_USAGE))?.to_owned());
            }
            "--estop" => initial_estop = true,
            "--max-requests" => {
                i += 1;
                let raw = args.get(i).ok_or_else(|| err(GRPC_USAGE))?;
                max_requests = Some(
                    raw.parse::<usize>()
                        .map_err(|_| err("Invalid --max-requests integer"))?,
                );
            }
            _ => return Err(err(GRPC_USAGE)),
        }
        i += 1;
    }
    let bind: SocketAddr = bind_str
        .parse()
        .map_err(|_| err(format!("Invalid --bind socket address `{bind_str}`")))?;
    validate_bind_auth_policy(&bind, bearer_token.as_deref())?;
    Ok(GatewayConfig {
        bind,
        bearer_token,
        initial_estop,
        max_requests,
    })
}

fn validate_bind_auth_policy(bind: &SocketAddr, bearer_token: Option<&str>) -> Result<()> {
    let is_loopback = bind.ip().is_loopback();
    match bearer_token {
        None if !is_loopback => Err(err(
            "SM26 fail-closed: non-loopback gRPC bind requires a non-blank --bearer-token",
        )),
        Some(tok) if tok.trim().is_empty() => Err(err(
            "SM26 fail-closed: blank or whitespace-only Bearer token refused",
        )),
        Some(tok)
            if !is_loopback
                && DISALLOWED_DEV_TOKENS
                    .iter()
                    .any(|dev| tok.trim().eq_ignore_ascii_case(dev)) =>
        {
            Err(err(
                "SM26 fail-closed: default dev token refused on non-loopback gRPC bind",
            ))
        }
        _ => Ok(()),
    }
}

fn constant_time_token_eq(expected: &str, provided: &str) -> bool {
    let a = expected.as_bytes();
    let b = provided.as_bytes();
    let mut diff = a.len() ^ b.len();
    for (&x, &y) in a.iter().zip(b.iter()) {
        diff |= usize::from(x ^ y);
    }
    diff == 0
}

fn verify_bearer_header(expected: Option<&str>, header_value: Option<&str>) -> bool {
    let Some(expected_tok) = expected else {
        return true;
    };
    let Some(raw) = header_value else {
        return false;
    };
    let Some(candidate) = raw.strip_prefix("Bearer ") else {
        return false;
    };
    if candidate.trim().is_empty() {
        return false;
    }
    constant_time_token_eq(expected_tok, candidate)
}

fn encode_grpc_frame(payload: &[u8]) -> Vec<u8> {
    let len = u32::try_from(payload.len()).unwrap_or(u32::MAX);
    let mut frame = Vec::with_capacity(5 + payload.len());
    frame.push(0u8);
    frame.extend_from_slice(&len.to_be_bytes());
    frame.extend_from_slice(payload);
    frame
}

fn decode_grpc_frame(body: &[u8]) -> std::result::Result<&[u8], &'static str> {
    if body.len() < 5 {
        return Err("gRPC frame shorter than 5-byte prefix");
    }
    if body[0] != 0 {
        return Err("Compressed gRPC frames are not supported");
    }
    let declared = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
    if declared != body.len() - 5 {
        return Err("gRPC frame length mismatch");
    }
    Ok(&body[5..])
}

fn write_grpc_response(
    stream: &mut TcpStream,
    grpc_status: u8,
    grpc_message: &str,
    payload_json: &str,
) -> std::io::Result<()> {
    let frame = encode_grpc_frame(payload_json.as_bytes());
    let sanitized_msg: String = grpc_message
        .chars()
        .map(|c| {
            if c.is_ascii_graphic() || c == ' ' {
                c
            } else {
                ' '
            }
        })
        .take(200)
        .collect();
    write!(
        stream,
        "HTTP/1.1 200 OK\r\n\
         Content-Type: application/grpc+json\r\n\
         grpc-status: {grpc_status}\r\n\
         grpc-message: {sanitized_msg}\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\r\n",
        frame.len()
    )?;
    stream.write_all(&frame)?;
    stream.flush()
}

fn dispatch_rpc(
    method: &str,
    payload_bytes: &[u8],
    session: &AitiaSession,
    estop: &AtomicBool,
) -> (u8, String, String) {
    let is_estop = estop.load(Ordering::SeqCst);
    if method == "Health" {
        let body = json!({
            "schema": "lambda-aitia.marlin-grpc-health.v1",
            "status": "SERVING",
            "service": "aitia.marlin.v1.AitiaSidecarGateway",
            "estopActive": is_estop,
            "actionAuthorized": false,
        });
        return (0, "OK".to_owned(), body.to_string());
    }
    if method == "TripEmergencyStop" {
        estop.store(true, Ordering::SeqCst);
        let body = json!({ "estopActive": true, "actionAuthorized": false });
        return (0, "OK".to_owned(), body.to_string());
    }
    if method == "ResetEmergencyStop" {
        estop.store(false, Ordering::SeqCst);
        let body = json!({ "estopActive": false, "actionAuthorized": false });
        return (0, "OK".to_owned(), body.to_string());
    }
    if is_estop {
        let msg = "Operator E-Stop active: audit/capture/receipt RPC blocked";
        let body = json!({ "error": msg, "estopActive": true, "actionAuthorized": false });
        return (9, msg.to_owned(), body.to_string());
    }
    let req: Value = match serde_json::from_slice(payload_bytes) {
        Ok(v) => v,
        Err(e) => {
            let msg = format!("Invalid gRPC JSON payload: {e}");
            return (
                3,
                msg.clone(),
                json!({ "error": msg, "actionAuthorized": false }).to_string(),
            );
        }
    };
    let outcome: Result<String> = match method {
        "CaptureDetachedContext" => (|| {
            let repo_dir = req["repoDir"]
                .as_str()
                .ok_or_else(|| err("Missing repoDir"))?;
            let base_ref = req["baseRef"].as_str().unwrap_or("HEAD");
            let profile_json = req["profileJson"].as_str().unwrap_or("");
            let checks_json = req["deterministicChecksJson"].as_str().unwrap_or("[]");
            sidecar::capture_detached_audit_context_json(
                Path::new(repo_dir),
                base_ref,
                profile_json,
                checks_json,
            )
        })(),
        "AssessSidecarAuditAscent" => (|| {
            let req_json = match req.get("requestJson").and_then(Value::as_str) {
                Some(s) => s.to_owned(),
                None => serde_json::to_string(&req)?,
            };
            Ok(session.sidecar_audit_assess(req_json)?)
        })(),
        "AuditDiffDefense" => (|| {
            let repo_dir = req["repoDir"]
                .as_str()
                .ok_or_else(|| err("Missing repoDir"))?;
            let base_ref = req["baseRef"].as_str().unwrap_or("HEAD");
            let staged_only = req["stagedOnly"].as_bool().unwrap_or(false);
            let rule_packs: Vec<Value> = match req.get("rulePacksJson").and_then(Value::as_str) {
                Some(s) if !s.trim().is_empty() => serde_json::from_str(s)?,
                _ => req
                    .get("rulePacks")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default(),
            };
            let funflow_receipts: Vec<Value> =
                match req.get("funflowReceiptsJson").and_then(Value::as_str) {
                    Some(s) if !s.trim().is_empty() => serde_json::from_str(s)?,
                    _ => req
                        .get("funflowReceipts")
                        .and_then(Value::as_array)
                        .cloned()
                        .unwrap_or_default(),
                };
            let report = defense_audit::audit_git_repo_defense_with_packs(
                Path::new(repo_dir),
                base_ref,
                staged_only,
                &rule_packs,
                &funflow_receipts,
                Some(session),
            )?;
            Ok(serde_json::to_string(&report)?)
        })(),
        "StepReview" => (|| {
            let step = defense_audit::run_review_flow_step_json(&req, Some(session))?;
            Ok(serde_json::to_string(&step)?)
        })(),
        "GetToolSchema" => (|| {
            let schema = defense_audit::get_review_tool_schema_json(Some(session))?;
            Ok(serde_json::to_string(&schema)?)
        })(),
        "VerifyFormalEvidence" => (|| {
            let fe = req["formalEvidenceJson"]
                .as_str()
                .ok_or_else(|| err("Missing formalEvidenceJson"))?;
            let ctx = req["expectedContextDigest"]
                .as_str()
                .ok_or_else(|| err("Missing expectedContextDigest"))?;
            formal_evidence::verify_de_formal_evidence_json(fe, ctx)
        })(),
        "BuildNasaSidecarReceipt" => (|| {
            let spec_json = match req.get("specJson").and_then(Value::as_str) {
                Some(s) => s.to_owned(),
                None => serde_json::to_string(&req)?,
            };
            sidecar::build_nasa_sidecar_receipt_json(&spec_json)
        })(),
        _ => {
            let msg = format!("Unknown gRPC method `{method}`");
            return (
                12,
                msg.clone(),
                json!({ "error": msg, "actionAuthorized": false }).to_string(),
            );
        }
    };
    match outcome {
        Ok(payload) => (0, "OK".to_owned(), payload),
        Err(e) => {
            let msg = e.to_string();
            (
                3,
                msg.clone(),
                json!({ "error": msg, "actionAuthorized": false }).to_string(),
            )
        }
    }
}

fn handle_connection(
    mut stream: TcpStream,
    expected_token: Option<&str>,
    session: &AitiaSession,
    estop: &AtomicBool,
) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut request_line = String::new();
    if reader.read_line(&mut request_line)? == 0 {
        return Ok(());
    }
    let parts: Vec<&str> = request_line.split_whitespace().collect();
    if parts.len() < 2 || parts[0] != "POST" {
        return write_grpc_response(
            &mut stream,
            3,
            "Expected HTTP POST gRPC invocation",
            r#"{"error":"Expected HTTP POST gRPC invocation","actionAuthorized":false}"#,
        );
    }
    let path = parts[1];
    let mut content_len = 0usize;
    let mut auth_header: Option<String> = None;
    let mut header_line = String::new();
    loop {
        header_line.clear();
        let n = reader.read_line(&mut header_line)?;
        if n == 0 || header_line == "\r\n" || header_line == "\n" {
            break;
        }
        if let Some((k, v)) = header_line.split_once(':') {
            let key = k.trim().to_ascii_lowercase();
            let val = v.trim();
            if key == "content-length" {
                content_len = val.parse::<usize>().unwrap_or(usize::MAX);
            } else if key == "authorization" {
                auth_header = Some(val.to_owned());
            }
        }
    }
    if content_len as u64 > MAX_REQUEST_BYTES {
        return write_grpc_response(
            &mut stream,
            3,
            "gRPC request exceeds MAX_REQUEST_BYTES",
            r#"{"error":"gRPC request exceeds MAX_REQUEST_BYTES","actionAuthorized":false}"#,
        );
    }
    let mut body = vec![0u8; content_len];
    reader.read_exact(&mut body)?;

    if !verify_bearer_header(expected_token, auth_header.as_deref()) {
        return write_grpc_response(
            &mut stream,
            16,
            "UNAUTHENTICATED: valid non-blank Bearer token required",
            r#"{"error":"UNAUTHENTICATED","actionAuthorized":false}"#,
        );
    }
    let Some(method) = path.strip_prefix(SERVICE_PREFIX) else {
        return write_grpc_response(
            &mut stream,
            12,
            "UNIMPLEMENTED: unknown gRPC service path",
            r#"{"error":"UNIMPLEMENTED","actionAuthorized":false}"#,
        );
    };
    let payload = match decode_grpc_frame(&body) {
        Ok(p) => p,
        Err(reason) => {
            return write_grpc_response(
                &mut stream,
                3,
                reason,
                &json!({ "error": reason, "actionAuthorized": false }).to_string(),
            );
        }
    };
    let (status, msg, resp_json) = dispatch_rpc(method, payload, session, estop);
    write_grpc_response(&mut stream, status, &msg, &resp_json)
}

/// Thin CLI entrypoint for `aitia serve-marlin-grpc` (RFC 0024).
///
/// # Errors
/// Fails closed if bind/auth SM26 policy is violated, the listener cannot bind,
/// or the persistent `AitiaSession` fails to initialize.
pub(crate) fn run_serve_marlin_grpc_cli(args: &[String]) -> Result<()> {
    if args.iter().any(|a| a == "--help" || a == "-h") {
        writeln!(std::io::stdout().lock(), "{GRPC_USAGE}")?;
        return Ok(());
    }
    let cfg = parse_gateway_config(args)?;
    let listener = TcpListener::bind(cfg.bind)?;
    let actual_addr = listener.local_addr()?;
    let session = AitiaSession::start()?;
    let estop = AtomicBool::new(cfg.initial_estop);

    let ready = json!({
        "schema": "lambda-aitia.marlin-grpc-ready.v1",
        "service": "aitia.marlin.v1.AitiaSidecarGateway",
        "listenAddr": actual_addr.to_string(),
        "loopbackOnly": actual_addr.ip().is_loopback(),
        "authRequired": cfg.bearer_token.is_some(),
        "estopActive": cfg.initial_estop,
        "actionAuthorized": false,
    });
    {
        let mut stdout = std::io::stdout().lock();
        writeln!(stdout, "{ready}")?;
        stdout.flush()?;
    }

    for (idx, incoming) in listener.incoming().enumerate() {
        let stream = incoming?;
        let _ = handle_connection(stream, cfg.bearer_token.as_deref(), &session, &estop);
        if cfg.max_requests.is_some_and(|limit| idx + 1 >= limit) {
            break;
        }
    }
    session.close()?;
    Ok(())
}
