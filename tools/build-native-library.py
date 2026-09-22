#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Build the Aitia Gambit link unit as a real shared library.

The four phases follow Gambit's embedding contract: ask the compiler for the
Gerbil runtime closure, generate a non-flat gsc link source, compile it with
``___LIBRARY``, then link the complete module/object set with libgambit.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys

def configure_darwin_toolchain() -> None:
    """Align every native phase with the installed Gerbil/Gambit objects."""

    if sys.platform != "darwin":
        return
    product_version = platform.mac_ver()[0]
    if not product_version:
        raise RuntimeError("cannot determine the macOS deployment target")
    host_major = product_version.split(".", 1)[0]
    os.environ.setdefault("MACOSX_DEPLOYMENT_TARGET", f"{host_major}.0")
    os.environ.setdefault("CC", "/usr/bin/cc")


def verify_darwin_deployment_target(output: Path) -> None:
    if sys.platform != "darwin":
        return
    load_commands = run(["otool", "-l", str(output)], cwd=output.parent, capture=True)
    match = re.search(r"^\s*minos\s+([0-9.]+)$", load_commands, re.MULTILINE)
    if match is None:
        raise RuntimeError("native library has no macOS deployment target")
    expected = os.environ["MACOSX_DEPLOYMENT_TARGET"]
    if match.group(1) != expected:
        raise RuntimeError(
            f"native deployment target {match.group(1)} does not match {expected}"
        )


def run(arguments: list[str], *, cwd: Path, capture: bool = False) -> str:
    result = subprocess.run(
        arguments,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=capture,
        env=os.environ,
    )
    return result.stdout if capture else ""


def replace_suffix(path: Path, suffix: str) -> Path:
    return path.with_suffix(suffix)


def unique(paths: list[Path]) -> list[Path]:
    seen: set[Path] = set()
    result: list[Path] = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def unique_link_flags(flags: list[str]) -> list[str]:
    """Preserve linker order while removing repeated idempotent flags."""

    seen: set[str] = set()
    result: list[str] = []
    for flag in flags:
        if flag not in seen:
            seen.add(flag)
            result.append(flag)
    return result


def shared_library_flags(*, system: str, machine: str) -> list[str]:
    if system != "Darwin":
        return ["-shared"]
    flags = ["-dynamiclib", "-Wl,-undefined,dynamic_lookup"]
    # Gambit's complete static closure is large enough for arm64 compact-unwind
    # function offsets to overflow ld's encoding. DWARF unwind remains present;
    # this is an architecture-specific link layout choice, not a macOS floor.
    if machine == "arm64":
        flags.append("-Wl,-no_compact_unwind")
    return flags


def gerbil_home(project: Path) -> Path:
    value = run(
        ["gxi", "-e", "(displayln (gerbil-home))"], cwd=project, capture=True
    ).strip()
    return Path(value).resolve()


def module_closure(project: Path) -> tuple[list[tuple[str, Path]], Path]:
    expression = r'''(let* ((ctx (import-module "bindings/c/aitia-native.ss"))
                             (deps (gxc#find-runtime-module-deps ctx)))
                        (for-each
                         (lambda (dep)
                           (displayln (expander-context-id dep) "\t"
                                      (gxc#find-static-module-file dep)))
                         deps)
                        (displayln "ROOT\t" (gxc#find-static-module-file ctx)))'''
    output = run(
        [
            "gxi",
            "-e",
            "(import :gerbil/compiler/driver :gerbil/expander)",
            "-e",
            expression,
        ],
        cwd=project,
        capture=True,
    )
    dependencies: list[tuple[str, Path]] = []
    root: Path | None = None
    for line in output.splitlines():
        module_id, raw_path = line.split("\t", 1)
        if module_id == "ROOT":
            root = Path(raw_path)
        else:
            dependencies.append((module_id, Path(raw_path)))
    if root is None:
        raise RuntimeError("Gerbil did not report the Aitia native root")
    return dependencies, root.resolve()


def generated_define(link_source: Path, name: str) -> str:
    match = re.search(
        rf"^#define {re.escape(name)} ([A-Za-z0-9_]+)$",
        link_source.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        raise RuntimeError(f"Gambit {name} is absent from {link_source}")
    return match.group(1)


def main() -> int:
    configure_darwin_toolchain()
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    project = Path(__file__).resolve().parents[1]
    output = arguments.output.expanduser().resolve()
    build_dir = output.parent
    build_dir.mkdir(parents=True, exist_ok=True)
    home = gerbil_home(project)
    gerbil_lib = home / "lib"
    dependencies, root = module_closure(project)

    libgerbil_scm = [
        path
        for module_id, path in dependencies
        if (module_id.startswith("gerbil/") or module_id.startswith("std/"))
        and not module_id.startswith("gerbil/core")
    ]
    libgerbil_scm = unique(libgerbil_scm)
    user_scm = unique(
        [
            path
            for module_id, path in dependencies
            if not module_id.startswith("gerbil/")
            and not module_id.startswith("std/")
            and path.is_file()
            and path.stat().st_size > 0
        ]
    )

    link_source = build_dir / "aitia-native_.c"
    link_object = build_dir / "aitia-native_.o"
    runtime_object = build_dir / "aitia-runtime.o"
    run(
        [
            "gsc",
            "-target",
            "C",
            "-link",
            "-o",
            str(link_source),
            *[str(replace_suffix(path, ".c")) for path in libgerbil_scm],
            *[str(path) for path in user_scm],
            str(root),
        ],
        cwd=project,
    )
    run(
        [
            "gsc",
            "-target",
            "C",
            "-cc-options",
            "-D___LIBRARY",
            "-obj",
            "-o",
            str(link_object),
            str(link_source),
        ],
        cwd=project,
    )
    run(
        [
            "gsc",
            "-target",
            "C",
            "-cc-options",
            (
                f"-D___VERSION={generated_define(link_source, '___VERSION')} "
                "-DPOO_FLOW_AITIA_LINKER="
                f"{generated_define(link_source, '___LINKER_ID')}"
            ),
            "-obj",
            "-o",
            str(runtime_object),
            "bindings/c/aitia-runtime.c",
        ],
        cwd=project,
    )

    module_objects = [replace_suffix(path, ".o") for path in user_scm]
    libgerbil_objects = [replace_suffix(path, ".o") for path in libgerbil_scm]
    # Imported POO Flow modules may have a static Scheme/C projection without
    # having been public native entry points in the parent build.  The Aitia
    # production library owns its complete link closure, so materialize only
    # those missing objects from the C sources generated by the link pass.
    object_sources = [*user_scm, root, *libgerbil_scm]
    for scheme_source in object_sources:
        object_path = scheme_source.with_suffix(".o")
        if (
            not object_path.is_file()
            or scheme_source.stat().st_mtime_ns > object_path.stat().st_mtime_ns
        ):
            c_source = object_path.with_suffix(".c")
            if not c_source.is_file():
                raise RuntimeError(f"native closure C source is absent: {c_source}")
            run(
                ["gsc", "-target", "C", "-obj", "-o", str(object_path), str(c_source)],
                cwd=project,
            )
    missing = [
        path
        for path in [*module_objects, root.with_suffix(".o"), *libgerbil_objects]
        if not path.is_file()
    ]
    if missing:
        raise RuntimeError(f"native closure object is absent: {missing[0]}")
    link_flags = unique_link_flags(
        shlex.split((gerbil_lib / "libgerbil.ldd").read_text().strip().strip("()"))
    )
    shared_flags = shared_library_flags(
        system=platform.system(), machine=platform.machine()
    )
    run(
        [
            os.environ.get("CC", "cc"),
            *shared_flags,
            "-o",
            str(output),
            *[str(path) for path in module_objects],
            str(root.with_suffix(".o")),
            str(link_object),
            str(runtime_object),
            *[str(path) for path in libgerbil_objects],
            "-L",
            str(gerbil_lib),
            "-lgambit",
            *link_flags,
        ],
        cwd=project,
    )
    verify_darwin_deployment_target(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
