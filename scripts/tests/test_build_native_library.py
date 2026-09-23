# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Tests for deterministic native linker inputs."""

from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build-native-library.py"


def build_module():
    spec = importlib.util.spec_from_file_location("build_native_library", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class NativeLinkPolicyTest(unittest.TestCase):
    def test_gambit_compiler_uses_the_gerbil_release_not_path(self) -> None:
        module = build_module()
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / "bin").mkdir()
            (home / "bin" / "gsc").touch()
            with patch.dict(os.environ, {"GAMBOPT": "-:max-heap=512M"}):
                self.assertEqual(
                    module.configure_gambit_compiler(home), str(home / "bin" / "gsc")
                )
                self.assertEqual(
                    os.environ["GAMBOPT"],
                    f"-:max-heap=512M,~~={home},~~bin={home / 'bin'},~~lib={home / 'lib'}",
                )

    def test_missing_release_compiler_does_not_fall_back_to_path(self) -> None:
        module = build_module()
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "no Gambit compiler"):
                module.configure_gambit_compiler(Path(directory))

    def test_link_flags_are_deduplicated_without_reordering(self) -> None:
        module = build_module()

        self.assertEqual(
            module.unique_link_flags(
                ["-L/runtime", "-lcrypto", "-lm", "-lcrypto", "-lm"]
            ),
            ["-L/runtime", "-lcrypto", "-lm"],
        )

    def test_arm64_darwin_uses_dwarf_unwind_for_large_native_closure(self) -> None:
        module = build_module()

        self.assertEqual(
            module.shared_library_flags(system="Darwin", machine="arm64"),
            [
                "-dynamiclib",
                "-Wl,-undefined,dynamic_lookup",
                "-Wl,-no_compact_unwind",
            ],
        )

    def test_compact_unwind_is_not_disabled_on_other_architectures(self) -> None:
        module = build_module()

        self.assertEqual(
            module.shared_library_flags(system="Darwin", machine="x86_64"),
            ["-dynamiclib", "-Wl,-undefined,dynamic_lookup"],
        )
        self.assertEqual(
            module.shared_library_flags(system="Linux", machine="aarch64"),
            ["-shared"],
        )


if __name__ == "__main__":
    unittest.main()
