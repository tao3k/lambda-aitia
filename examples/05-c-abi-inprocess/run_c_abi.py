#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Use Case 5: Language-Agnostic Ultra-Thin C ABI (`include/aitia.h`).

Loads the pre-compiled `liblambda_aitia_rust.{so,dylib}` purely via `ctypes.CDLL` (without
importing PyO3 and with zero `GERBIL_LOADPATH`), exercising the exact 7-symbol C ABI available
to C/C++, Go (`cgo`), Node, Zig, and Swift hosts.
"""

import ctypes
import json
import os
import sys
from pathlib import Path


class AitiaBuffer(ctypes.Structure):
    _fields_ = [
        ("status", ctypes.c_int32),
        ("data", ctypes.c_void_p),
        ("len", ctypes.c_size_t),
        ("cap", ctypes.c_size_t),
    ]


def resolve_cdylib() -> str:
    explicit = os.environ.get("AITIA_CDYLIB")
    if explicit and Path(explicit).is_file():
        return explicit
    repo_root = Path(__file__).resolve().parents[2]
    for name in ("liblambda_aitia_rust.dylib", "liblambda_aitia_rust.so"):
        candidate = repo_root / "rust" / "target" / "debug" / name
        if candidate.is_file():
            return str(candidate)
    raise SystemExit("Set AITIA_CDYLIB to liblambda_aitia_rust.{dylib,so}")


def main() -> None:
    lib_path = sys.argv[1] if len(sys.argv) > 1 else resolve_cdylib()
    lib = ctypes.CDLL(lib_path)
    lib.aitia_abi_version.restype = ctypes.c_uint32
    lib.aitia_host_capabilities.restype = AitiaBuffer
    lib.aitia_dispatch_host_frames.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.aitia_dispatch_host_frames.restype = AitiaBuffer
    lib.aitia_session_start.argtypes = [ctypes.POINTER(AitiaBuffer)]
    lib.aitia_session_start.restype = ctypes.c_void_p
    lib.aitia_session_call.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    lib.aitia_session_call.restype = AitiaBuffer
    lib.aitia_session_close.argtypes = [ctypes.c_void_p, ctypes.POINTER(AitiaBuffer)]
    lib.aitia_session_close.restype = ctypes.c_int32
    lib.aitia_buffer_free.argtypes = [AitiaBuffer]
    lib.aitia_buffer_free.restype = None

    def take_buf(buf: AitiaBuffer) -> tuple[int, str]:
        try:
            text = ctypes.string_at(buf.data, buf.len).decode("utf-8") if buf.data and buf.len else ""
            return buf.status, text
        finally:
            lib.aitia_buffer_free(buf)

    abi_ver = lib.aitia_abi_version()
    assert abi_ver == 1

    st, caps_json = take_buf(lib.aitia_host_capabilities())
    assert st == 0, caps_json
    caps = json.loads(caps_json)
    assert len(caps["capabilities"]) == 12
    assert caps["actionAuthorized"] is False

    err_buf = AitiaBuffer()
    handle = lib.aitia_session_start(ctypes.byref(err_buf))
    assert handle, f"aitia_session_start failed: {take_buf(err_buf)}"
    try:
        op = b"drive_multi_repo_protocol"
        req = json.dumps(
            {
                "repos": [
                    {"repoId": "service-a", "dependsOn": ["service-b"]},
                    {"repoId": "service-b", "dependsOn": ["service-a"]},
                ]
            }
        ).encode("utf-8")
        st, out_json = take_buf(lib.aitia_session_call(handle, op, len(op), req, len(req)))
        assert st == 0, out_json
        res = json.loads(out_json)
        assert res["state"] == "need-human-decision"
        assert res["escalationReason"] == "dependency-cycle"
        assert res["actionAuthorized"] is False
    finally:
        close_err = AitiaBuffer()
        rc = lib.aitia_session_close(handle, ctypes.byref(close_err))
        assert rc == 0, f"aitia_session_close failed: {take_buf(close_err)}"

    print(
        json.dumps(
            {
                "example": "05-c-abi-inprocess",
                "abiVersion": abi_ver,
                "registeredCapabilities": len(caps["capabilities"]),
                "cycleDetectionState": res["state"],
                "escalationReason": res["escalationReason"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
