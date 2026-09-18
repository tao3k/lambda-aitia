# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Tests for deterministic native linker inputs."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


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
    def test_link_flags_are_deduplicated_without_reordering(self) -> None:
        module = build_module()

        self.assertEqual(
            module.unique_link_flags(
                ["-L/runtime", "-lcrypto", "-lm", "-lcrypto", "-lm"]
            ),
            ["-L/runtime", "-lcrypto", "-lm"],
        )


if __name__ == "__main__":
    unittest.main()
