# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Thin JSON transport over the Lambda Aitia native ABI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import platform
from threading import get_ident
from types import TracebackType
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


def _decode_call(
    status: int, output: Any, output_length: Any, error: Any
) -> dict[str, Any]:
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
    return _decode_call(status, output, output_length, error)


class AitiaNativeSession:
    """Own one process-exclusive Gambit transport session, not Host authority.

    Calls and close must run on the thread that opened the session. Its lifetime
    keeps Scheme state alive, but only Scheme-issued opaque capabilities can
    establish verification/admission authority in a later ABI revision.
    """

    def __init__(self) -> None:
        error = ffi.new("char[512]")
        handle = lib.lambda_aitia_python_open(
            os.fsencode(_library_path()), error, 512
        )
        if handle == ffi.NULL:
            raise AitiaNativeError(ffi.string(error).decode("utf-8", errors="replace"))
        self._handle = handle
        self._owner_thread = get_ident()

    @property
    def closed(self) -> bool:
        return self._handle == ffi.NULL

    def _require_owner(self) -> None:
        if get_ident() != self._owner_thread:
            raise AitiaNativeError("Aitia native session belongs to another thread")

    def close(self) -> None:
        self._require_owner()
        if not self.closed:
            handle = self._handle
            self._handle = ffi.NULL
            lib.lambda_aitia_python_close(handle)

    def _call(self, operation: str, payload: bytes = b"") -> dict[str, Any]:
        self._require_owner()
        if self.closed:
            raise AitiaNativeError("Aitia native session is closed")
        output = ffi.new("uint8_t **")
        output_length = ffi.new("size_t *")
        error = ffi.new("char[512]")
        payload_pointer = ffi.from_buffer(payload) if payload else ffi.NULL
        status = lib.lambda_aitia_python_session_call(
            self._handle,
            operation.encode("ascii"),
            payload_pointer,
            len(payload),
            output,
            output_length,
            error,
            512,
        )
        return _decode_call(status, output, output_length, error)

    def __enter__(self) -> AitiaNativeSession:
        self._require_owner()
        if self.closed:
            raise AitiaNativeError("Aitia native session is closed")
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    def __del__(self) -> None:
        if getattr(self, "_handle", ffi.NULL) != ffi.NULL:
            # Gambit cleanup is thread-affine. Refuse silent cross-thread cleanup.
            if get_ident() == self._owner_thread:
                self.close()


def descriptor() -> dict[str, Any]:
    """Return the native ABI descriptor published by Scheme."""

    return _call("descriptor")


def sdlc_flow_plan(
    lifecycle_id: str, *, session: AitiaNativeSession | None = None
) -> dict[str, Any]:
    """Ask Scheme to project an SDLC lifecycle onto the POO Flow DAG."""

    payload = json.dumps(
        {"lifecycle-id": lifecycle_id}, separators=(",", ":"), ensure_ascii=False
    ).encode()
    return (session._call if session is not None else _call)("sdlc-flow-plan", payload)


def _evaluate_gitops_payload(
    change: Mapping[str, Any], *, session: AitiaNativeSession | None = None
) -> dict[str, Any]:
    """Ask Scheme to evaluate one GitOps change and its check evidence."""

    payload = json.dumps(change, separators=(",", ":"), ensure_ascii=False).encode()
    return (session._call if session is not None else _call)("gitops-evaluate", payload)
