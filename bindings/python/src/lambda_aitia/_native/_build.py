# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

from __future__ import annotations

from pathlib import Path

from cffi import FFI

ffibuilder = FFI()
ffibuilder.cdef(
    """
    typedef struct lambda_aitia_python_session lambda_aitia_python_session;
    lambda_aitia_python_session *lambda_aitia_python_open(
        const char *library_path, char *error, size_t error_capacity);
    void lambda_aitia_python_close(lambda_aitia_python_session *session);
    int lambda_aitia_python_session_call(
        lambda_aitia_python_session *session,
        const char *operation,
        const uint8_t *payload,
        size_t payload_length,
        uint8_t **output,
        size_t *output_length,
        char *error,
        size_t error_capacity);
    int lambda_aitia_python_call(
        const char *library_path,
        const char *operation,
        const uint8_t *payload,
        size_t payload_length,
        uint8_t **output,
        size_t *output_length,
        char *error,
        size_t error_capacity);
    void lambda_aitia_python_release(uint8_t *output);
    """
)

native_dir = Path(__file__).resolve().parent
c_binding_dir = native_dir.parents[3] / "c"
ffibuilder.set_source(
    "lambda_aitia._native._aitia_cffi",
    '#include "aitia_shim.c"',
    include_dirs=[str(native_dir), str(c_binding_dir / "include")],
)

if __name__ == "__main__":
    import sys
    import sysconfig

    python_project = Path(__file__).resolve().parents[3]
    if str(python_project) not in sys.path:
        sys.path.insert(0, str(python_project))
    from build_support import sanitize_python_linker_config

    sanitize_python_linker_config()
    ffibuilder.compile(
        tmpdir=str(native_dir / "_build_temp"),
        target=str(
            native_dir / ("_aitia_cffi" + sysconfig.get_config_var("EXT_SUFFIX"))
        ),
        verbose=True,
    )
