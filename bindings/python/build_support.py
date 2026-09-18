# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Shared policy for Lambda Aitia's Python native builds."""

from __future__ import annotations

from pathlib import Path
import shlex
import sysconfig
from typing import Sequence


_CPYTHON_SOURCE_LIBRARY_PATH = "-LModules/_hacl"


def without_stale_cpython_build_paths(arguments: Sequence[str]) -> list[str]:
    """Drop a CPython source-tree path only when it is absent."""

    return [
        argument
        for argument in arguments
        if not (
            argument == _CPYTHON_SOURCE_LIBRARY_PATH
            and not Path("Modules/_hacl").is_dir()
        )
    ]


def sanitize_python_linker_config() -> None:
    """Repair installed-Python linker settings before CFFI creates a compiler."""

    variables = sysconfig.get_config_vars()
    for name in ("LDFLAGS", "LDSHARED", "BLDSHARED"):
        value = variables.get(name)
        if isinstance(value, str):
            variables[name] = shlex.join(
                without_stale_cpython_build_paths(shlex.split(value))
            )
