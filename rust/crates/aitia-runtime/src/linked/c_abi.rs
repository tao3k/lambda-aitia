// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Ultra-thin, zero-logic C ABI over [`crate::AitiaSession`] and [`crate::HostCapabilityRegistry`].
//!
//! Exists solely to eliminate per-call CLI process startup overhead for non-Python and Python
//! hosts (C, Go, Node, Zig, Swift, `ctypes`) sharing the pre-compiled AOT-linked `cdylib`.
//! All workflow semantics remain 100% in Scheme POO/ASCENT/FunFlow.

use crate::AitiaSession;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

/// Stable C ABI version returned by [`aitia_abi_version`].
pub const AITIA_ABI_VERSION: u32 = 1;

/// Opaque handle owning one resident [`AitiaSession`] (single Gambit runtime thread).
pub struct AitiaSessionHandle {
    session: AitiaSession,
}

/// Owned UTF-8 buffer returned across the C ABI.
///
/// - `status == 0`: `data[0..len]` holds the UTF-8 JSON result (also NUL-terminated).
/// - `status != 0`: `data[0..len]` holds the UTF-8 error message (also NUL-terminated).
/// - Callers MUST release every non-null buffer via [`aitia_buffer_free`].
#[repr(C)]
pub struct AitiaBuffer {
    pub status: i32,
    pub data: *mut u8,
    pub len: usize,
    pub cap: usize,
}

impl AitiaBuffer {
    fn from_utf8(status: i32, text: String) -> Self {
        let mut bytes = text.into_bytes();
        let len = bytes.len();
        bytes.push(0);
        let cap = bytes.capacity();
        let data = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        Self {
            status,
            data,
            len,
            cap,
        }
    }

    fn ok(json: String) -> Self {
        Self::from_utf8(0, json)
    }

    fn err(code: i32, message: impl Into<String>) -> Self {
        Self::from_utf8(code, message.into())
    }
}

fn write_optional_err(err_out: *mut AitiaBuffer, code: i32, message: impl Into<String>) {
    if !err_out.is_null() {
        // SAFETY: Caller passed a valid writable `AitiaBuffer*` or null.
        unsafe {
            *err_out = AitiaBuffer::err(code, message);
        }
    }
}

fn read_utf8_arg<'a>(ptr: *const u8, len: usize, label: &str) -> Result<&'a str, String> {
    if len == 0 {
        return Ok("");
    }
    if ptr.is_null() {
        return Err(format!("null pointer passed for non-empty `{label}`"));
    }
    // SAFETY: Caller guarantees `ptr` is valid for `len` bytes for the duration of the FFI call.
    let slice = unsafe { std::slice::from_raw_parts(ptr, len) };
    std::str::from_utf8(slice).map_err(|error| format!("invalid UTF-8 in `{label}`: {error}"))
}

fn dispatch_session_operation(
    session: &AitiaSession,
    op: &str,
    request: &str,
) -> Result<String, String> {
    match op {
        "flow_graph" => session
            .flow_graph(request.to_owned())
            .map_err(|e| e.to_string()),
        "gitops_evaluate" => session
            .gitops_evaluate(request.to_owned())
            .map_err(|e| e.to_string()),
        "org_contract_evaluate" => session
            .org_contract_evaluate(request.to_owned())
            .map_err(|e| e.to_string()),
        "project_config_validate" => session
            .project_config_validate(request.to_owned())
            .map_err(|e| e.to_string()),
        "evidence_lineage" => session
            .evidence_lineage(request.to_owned())
            .map_err(|e| e.to_string()),
        "workflow_reconcile" => session
            .workflow_reconcile(request.to_owned())
            .map_err(|e| e.to_string()),
        "workflow_protocol_step" => session
            .workflow_protocol_step(request.to_owned())
            .map_err(|e| e.to_string()),
        "drive_multi_repo_protocol" => session.drive_multi_repo_protocol(request.to_owned(), false),
        "drive_multi_repo_protocol_fenced" => {
            session.drive_multi_repo_protocol(request.to_owned(), true)
        }
        "drive_protocol" => {
            let spec: serde_json::Value =
                serde_json::from_str(request).map_err(|error| error.to_string())?;
            let directory = spec["directory"].as_str().unwrap_or(".").to_owned();
            let case_id = spec["caseId"]
                .as_str()
                .unwrap_or(crate::DEFAULT_WORKFLOW_CASE)
                .to_owned();
            let overlay = spec
                .get("overlay")
                .filter(|v| !v.is_null())
                .map(serde_json::to_string)
                .transpose()
                .map_err(|error| error.to_string())?;
            let execute_fenced = spec["executeFenced"].as_bool().unwrap_or(false);
            session.drive_protocol(directory, case_id, overlay, execute_fenced)
        }
        _ => Err(format!("unknown aitia C ABI operation: `{op}`")),
    }
}

/// Return the stable AITIA C ABI version number (`1`).
#[unsafe(no_mangle)]
pub extern "C" fn aitia_abi_version() -> u32 {
    AITIA_ABI_VERSION
}

/// Return the JSON envelope listing all registered host capabilities (`actionAuthorized: false`).
#[unsafe(no_mangle)]
pub extern "C" fn aitia_host_capabilities() -> AitiaBuffer {
    match catch_unwind(crate::host_capabilities_json) {
        Ok(Ok(json)) => AitiaBuffer::ok(json),
        Ok(Err(message)) => AitiaBuffer::err(1, message),
        Err(_) => AitiaBuffer::err(2, "Rust panic inside aitia_host_capabilities"),
    }
}

/// Validate and dispatch a JSON array of Scheme-emitted host capability frames.
///
/// Fails closed on unknown capabilities, effect-class mismatches, or missing `fenceToken`.
///
/// # Safety
/// If `frames_len > 0`, `frames_ptr` must be valid for reads of `frames_len` bytes for the
/// duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aitia_dispatch_host_frames(
    frames_ptr: *const u8,
    frames_len: usize,
) -> AitiaBuffer {
    match catch_unwind(|| {
        let frames_json = read_utf8_arg(frames_ptr, frames_len, "frames")?;
        crate::dispatch_host_frames_json(frames_json)
    }) {
        Ok(Ok(json)) => AitiaBuffer::ok(json),
        Ok(Err(message)) => AitiaBuffer::err(1, message),
        Err(_) => AitiaBuffer::err(2, "Rust panic inside aitia_dispatch_host_frames"),
    }
}

/// Start one resident [`AitiaSession`] (single Gambit runtime thread) and return its handle.
///
/// Returns `NULL` on failure and writes the UTF-8 error buffer into `err_out` if non-null.
///
/// # Safety
/// `err_out` must either be null or point to valid writable memory for one [`AitiaBuffer`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aitia_session_start(err_out: *mut AitiaBuffer) -> *mut AitiaSessionHandle {
    match catch_unwind(AitiaSession::start) {
        Ok(Ok(session)) => Box::into_raw(Box::new(AitiaSessionHandle { session })),
        Ok(Err(error)) => {
            write_optional_err(err_out, 1, error.to_string());
            ptr::null_mut()
        }
        Err(_) => {
            write_optional_err(err_out, 2, "Rust panic inside aitia_session_start");
            ptr::null_mut()
        }
    }
}

/// Invoke a named Scheme/protocol operation on a live [`AitiaSessionHandle`].
///
/// Returns an [`AitiaBuffer`] whose `status` is `0` on success (JSON payload) or non-zero on error.
///
/// # Safety
/// `handle` must be null or a live pointer returned by [`aitia_session_start`] that has not been
/// closed. Any non-empty `(op_ptr, op_len)` or `(req_ptr, req_len)` slice must be readable for
/// the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aitia_session_call(
    handle: *mut AitiaSessionHandle,
    op_ptr: *const u8,
    op_len: usize,
    req_ptr: *const u8,
    req_len: usize,
) -> AitiaBuffer {
    match catch_unwind(AssertUnwindSafe(|| {
        if handle.is_null() {
            return Err("null AitiaSessionHandle".to_owned());
        }
        let op = read_utf8_arg(op_ptr, op_len, "op")?;
        let req = read_utf8_arg(req_ptr, req_len, "request")?;
        // SAFETY: Caller owns a live handle returned by `aitia_session_start` not yet closed.
        let live = unsafe { &*handle };
        dispatch_session_operation(&live.session, op, req)
    })) {
        Ok(Ok(json)) => AitiaBuffer::ok(json),
        Ok(Err(message)) => AitiaBuffer::err(1, message),
        Err(_) => AitiaBuffer::err(2, "Rust panic inside aitia_session_call"),
    }
}

/// Close and free an [`AitiaSessionHandle`], waiting for the resident Scheme thread to exit.
///
/// Returns `0` on success, or non-zero with details written to `err_out` if non-null.
///
/// # Safety
/// `handle` must be null or a live pointer returned by [`aitia_session_start`] and must not be
/// used again after this call. `err_out` must be null or point to writable [`AitiaBuffer`] memory.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aitia_session_close(
    handle: *mut AitiaSessionHandle,
    err_out: *mut AitiaBuffer,
) -> i32 {
    if handle.is_null() {
        return 0;
    }
    match catch_unwind(AssertUnwindSafe(|| {
        // SAFETY: Caller transfers ownership of a live handle returned by `aitia_session_start`.
        let boxed = unsafe { Box::from_raw(handle) };
        boxed.session.close()
    })) {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => {
            write_optional_err(err_out, 1, error.to_string());
            1
        }
        Err(_) => {
            write_optional_err(err_out, 2, "Rust panic inside aitia_session_close");
            2
        }
    }
}

/// Release an [`AitiaBuffer`] returned by any `aitia_*` C ABI function.
///
/// # Safety
/// `buf` must have been returned by an `aitia_*` C ABI function and must be freed at most once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn aitia_buffer_free(buf: AitiaBuffer) {
    if buf.data.is_null() || buf.cap == 0 {
        return;
    }
    let _ = catch_unwind(|| {
        // SAFETY: `buf` was allocated by `AitiaBuffer::from_utf8` with `len + 1` initialized bytes
        // and capacity `buf.cap`, and is freed at most once.
        unsafe {
            let _ = Vec::from_raw_parts(buf.data, buf.len + 1, buf.cap);
        }
    });
}
