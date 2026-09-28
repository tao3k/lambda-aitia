# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

from __future__ import annotations

from pathlib import Path
import os

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
    typedef struct {
        int64_t id;
        int64_t parent_id;
        const char *kind;
        const char *field_name;
        const char *field_value;
    } orgize_element_row;
    typedef struct {
        int32_t status;
        uint32_t matched_count;
        int32_t passed;
    } orgize_contract_result;
    int lambda_aitia_python_session_org_contract(
        lambda_aitia_python_session *session, const orgize_element_row *rows,
        uint32_t row_count, int64_t scope_id, const char *query_kind,
        const char *field_name, const char *field_value,
        uint32_t expectation, uint32_t expected_count,
        orgize_contract_result *result, char *error, size_t error_capacity);
    """
)

native_dir = Path(__file__).resolve().parent
c_binding_dir = native_dir.parents[3] / "c"
gerbil_path = os.environ.get("GERBIL_PATH")
if gerbil_path is None:
    raise RuntimeError("GERBIL_PATH must identify the installed Orgize dependency")
orgize_c_dir = (
    Path(gerbil_path).resolve()
    / "pkg/github.com/tao3k/orgize/bindings/c/include"
)
if not (orgize_c_dir / "orgize.h").is_file():
    raise RuntimeError("Orgize's public C header is absent; install POO Flow dependencies")
ffibuilder.set_source(
    "lambda_aitia._native._aitia_cffi",
    '#include "aitia_shim.c"',
    include_dirs=[str(native_dir), str(c_binding_dir / "include"), str(orgize_c_dir)],
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
