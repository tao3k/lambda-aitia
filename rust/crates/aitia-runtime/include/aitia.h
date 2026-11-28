/* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
 * SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
 *
 * Ultra-thin C ABI for Lambda Aitia's pre-compiled AOT Scheme/Rust runtime.
 * Exported directly by `liblambda_aitia_rust.{so,dylib}` so C, Go, Node, Zig,
 * Swift, and `ctypes` hosts can invoke `AitiaSession` in-process with zero
 * CLI startup cost and zero downstream Gerbil/Gambit compilation.
 */

#ifndef LAMBDA_AITIA_C_ABI_H
#define LAMBDA_AITIA_C_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AitiaSessionHandle AitiaSessionHandle;

typedef struct AitiaBuffer {
    int32_t status;   /* 0 = OK, non-zero = error message in data[0..len] */
    uint8_t *data;    /* UTF-8 JSON or error message, NUL-terminated */
    size_t len;       /* Byte length excluding trailing NUL */
    size_t cap;       /* Allocation capacity for aitia_buffer_free */
} AitiaBuffer;

/* Return stable C ABI version (currently 1). */
uint32_t aitia_abi_version(void);

/* List all registered HostCapabilityRegistry entries (actionAuthorized: false). */
AitiaBuffer aitia_host_capabilities(void);

/* Validate and dispatch a JSON array of Scheme-emitted host capability frames. */
AitiaBuffer aitia_dispatch_host_frames(const uint8_t *frames_ptr, size_t frames_len);

/* Start one resident AitiaSession (single Gambit thread). Returns NULL on error. */
AitiaSessionHandle *aitia_session_start(AitiaBuffer *err_out);

/* Invoke a named operation ("workflow_protocol_step", "drive_multi_repo_protocol",
 * "drive_multi_repo_protocol_fenced", "drive_protocol", "flow_graph",
 * "gitops_evaluate", "org_contract_evaluate", "project_config_validate",
 * "evidence_lineage", "workflow_reconcile") on a live session. */
AitiaBuffer aitia_session_call(
    AitiaSessionHandle *handle,
    const uint8_t *op_ptr,
    size_t op_len,
    const uint8_t *req_ptr,
    size_t req_len);

/* Close and release a live AitiaSessionHandle. Returns 0 on success. */
int32_t aitia_session_close(AitiaSessionHandle *handle, AitiaBuffer *err_out);

/* Free any AitiaBuffer returned by this ABI. */
void aitia_buffer_free(AitiaBuffer buf);

#ifdef __cplusplus
}
#endif

#endif /* LAMBDA_AITIA_C_ABI_H */
