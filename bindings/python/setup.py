# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Build Lambda Aitia's out-of-line CFFI extension and native library."""

from __future__ import annotations

import os
from pathlib import Path
import platform
import shutil

from setuptools import setup
from setuptools.command.build_py import build_py

NATIVE_LIBRARY_ENV = "LAMBDA_AITIA_NATIVE_LIBRARY"


def _native_library() -> Path:
    configured = os.environ.get(NATIVE_LIBRARY_ENV)
    if not configured:
        raise RuntimeError(
            f"{NATIVE_LIBRARY_ENV} must name the built Lambda Aitia library"
        )
    library = Path(configured).expanduser().resolve()
    if not library.is_file():
        raise RuntimeError(f"Lambda Aitia native library is absent: {library}")
    return library


class BuildPyWithAitiaLibrary(build_py):
    def run(self) -> None:
        super().run()
        library_name = {
            "Darwin": "libpoo_flow_aitia.dylib",
            "Windows": "poo_flow_aitia.dll",
        }.get(platform.system(), "libpoo_flow_aitia.so")
        target = Path(self.build_lib) / "lambda_aitia" / "_native" / "lib"
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(_native_library(), target / library_name)


setup(
    cffi_modules=["src/lambda_aitia/_native/_build.py:ffibuilder"],
    cmdclass={"build_py": BuildPyWithAitiaLibrary},
)
