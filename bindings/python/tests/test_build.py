# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Build-policy tests for the production Python distribution."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def build_support_module():
    spec = importlib.util.spec_from_file_location(
        "lambda_aitia_build_support", ROOT / "build_support.py"
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_stale_cpython_source_library_path_is_removed(monkeypatch, tmp_path) -> None:
    monkeypatch.chdir(tmp_path)
    module = build_support_module()

    assert module.without_stale_cpython_build_paths(
        ["cc", "-bundle", "-LModules/_hacl", "-Wl,-headerpad,40"]
    ) == ["cc", "-bundle", "-Wl,-headerpad,40"]


def test_existing_cpython_source_library_path_is_preserved(monkeypatch, tmp_path) -> None:
    (tmp_path / "Modules" / "_hacl").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)
    module = build_support_module()

    assert module.without_stale_cpython_build_paths(
        ["cc", "-LModules/_hacl"]
    ) == ["cc", "-LModules/_hacl"]


def test_installed_python_linker_configuration_is_repaired(
    monkeypatch, tmp_path
) -> None:
    monkeypatch.chdir(tmp_path)
    module = build_support_module()
    variables = module.sysconfig.get_config_vars()
    monkeypatch.setitem(
        variables,
        "LDSHARED",
        "cc -bundle -LModules/_hacl -Wl,-headerpad,40",
    )

    module.sanitize_python_linker_config()

    assert variables["LDSHARED"] == "cc -bundle -Wl,-headerpad,40"
