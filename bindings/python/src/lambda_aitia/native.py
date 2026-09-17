# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Thin JSON transport over the Lambda Aitia native ABI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import platform
from typing import Any, Mapping

from ._native._aitia_cffi import ffi, lib

NATIVE_LIBRARY_ENV = "LAMBDA_AITIA_NATIVE_LIBRARY"


class AitiaNativeError(RuntimeError):
    """The native Aitia library could not execute the requested operation."""


def _library_path() -> Path:
    configured = os.environ.get(NATIVE_LIBRARY_ENV)
    if configured:
        candidate = Path(configured).expanduser().resolve()
    else:
        library_name = {
            "Darwin": "libpoo_flow_aitia.dylib",
            "Windows": "poo_flow_aitia.dll",
        }.get(platform.system(), "libpoo_flow_aitia.so")
        candidate = Path(__file__).parent / "_native" / "lib" / library_name
    if not candidate.is_file():
        raise AitiaNativeError(f"Lambda Aitia native library is absent: {candidate}")
    return candidate


def _call(operation: str, payload: bytes = b"") -> dict[str, Any]:
    output = ffi.new("uint8_t **")
    output_length = ffi.new("size_t *")
    error = ffi.new("char[512]")
    payload_pointer = ffi.from_buffer(payload) if payload else ffi.NULL
    status = lib.lambda_aitia_python_call(
        os.fsencode(_library_path()),
        operation.encode("ascii"),
        payload_pointer,
        len(payload),
        output,
        output_length,
        error,
        512,
    )
    try:
        response_bytes = (
            bytes(ffi.buffer(output[0], output_length[0]))
            if output[0] != ffi.NULL
            else b""
        )
    finally:
        lib.lambda_aitia_python_release(output[0])
    if status != 0:
        detail = response_bytes.decode("utf-8", errors="replace")
        if not detail:
            detail = ffi.string(error).decode("utf-8", errors="replace")
        raise AitiaNativeError(detail or f"Lambda Aitia call failed: {status}")
    try:
        value = json.loads(response_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exception:
        raise AitiaNativeError("Lambda Aitia returned invalid JSON") from exception
    if not isinstance(value, dict):
        raise AitiaNativeError("Lambda Aitia returned a non-object JSON value")
    return value


def descriptor() -> dict[str, Any]:
    """Return the native ABI descriptor published by Scheme."""

    return _call("descriptor")


def sdlc_flow_plan(lifecycle_id: str) -> dict[str, Any]:
    """Ask Scheme to project an SDLC lifecycle onto the POO Flow DAG."""

    payload = json.dumps(
        {"lifecycle-id": lifecycle_id}, separators=(",", ":"), ensure_ascii=False
    ).encode()
    return _call("sdlc-flow-plan", payload)


def evaluate_gitops(change: Mapping[str, Any]) -> dict[str, Any]:
    """Ask Scheme to evaluate one GitOps change and its check evidence."""

    payload = json.dumps(change, separators=(",", ":"), ensure_ascii=False).encode()
    return _call("gitops-evaluate", payload)
