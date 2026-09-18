# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Build Lambda Aitia's out-of-line CFFI extension and native library."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import platform
import shutil

from setuptools import setup
from setuptools.command.build_ext import build_ext
from setuptools.command.build_py import build_py


_build_support_spec = importlib.util.spec_from_file_location(
    "lambda_aitia_build_support", Path(__file__).with_name("build_support.py")
)
if _build_support_spec is None or _build_support_spec.loader is None:
    raise RuntimeError("cannot load Lambda Aitia Python build support")
_build_support = importlib.util.module_from_spec(_build_support_spec)
_build_support_spec.loader.exec_module(_build_support)

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


class BuildExtWithFreshAitiaAbi(build_ext):
    """Recompile the tiny shim because CFFI cannot track its included headers."""

    def finalize_options(self) -> None:
        super().finalize_options()
        self.force = True

    def build_extensions(self) -> None:
        # uv's standalone CPython currently retains its source-tree HACL
        # search path in LDSHARED.  It is not a distributable library path and
        # produces an ld warning in every extension build after installation.
        self.compiler.linker_so = _build_support.without_stale_cpython_build_paths(
            self.compiler.linker_so
        )
        super().build_extensions()


if __name__ == "__main__":
    setup(
        cffi_modules=["src/lambda_aitia/_native/_build.py:ffibuilder"],
        cmdclass={
            "build_ext": BuildExtWithFreshAitiaAbi,
            "build_py": BuildPyWithAitiaLibrary,
        },
    )
