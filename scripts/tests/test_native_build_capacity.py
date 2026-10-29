# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Observe real SDK frontend/backend settings in independent bounded processes."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "check-native-build-capacity.ss"

@unittest.skipUnless(shutil.which("gxi"), "native Gerbil SDK required")
class NativeCapacityTest(unittest.TestCase):
    def run_sdk(self, selected):
        env = dict(os.environ, GAMBOPT="max-heap=2G,debug=q")
        env.pop("GERBIL_BUILD_CORES", None)
        if selected is not None:
            env["GERBIL_BUILD_CORES"] = selected
        return subprocess.run(
            ["gxi", "-:max-heap=2G,debug=q", str(SCRIPT)], env=env,
            capture_output=True, text=True, timeout=180)

    def test_native_owners_preserve_explicit_capacity(self):
        for count in ("1", "3"):
            with self.subTest(count=count):
                result = self.run_sdk(count)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"declared={count} make={count} compiler={count}", result.stdout)

    def test_missing_declaration_refuses_before_compilation(self):
        result = self.run_sdk(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner must declare a positive native compiler capacity", result.stderr)
        self.assertNotIn("AITIA-NATIVE-CAPACITY-OK", result.stdout)
