# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Project test for bounded TLC contracts and typed counterexamples."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3] / "proof/tla"
TOOLS_SHA256 = "fa18543e44ed5974a85bd2c60c0dc16620ae117680ea8e693d2691999ed90b22"
CASES = (
    ("AssuranceLifecycle.cfg", 0, "Model checking completed. No error has been found."),
    ("AssuranceLifecycleProgress.cfg", 0, "Model checking completed. No error has been found."),
    ("AssuranceLifecycleNoFair.cfg", 13, "Error: Temporal properties were violated."),
    ("AssuranceLifecycleReachable.cfg", 12, "Error: Invariant NoEffectStarted is violated."),
    ("AssuranceLifecycleUnsafe.cfg", 12, "Error: Invariant NoUnsafeEffectStart is violated."),
    ("AssuranceLifecycleLateAdmit.cfg", 12, "Error: Invariant AdmissionIsCurrent is violated."),
    ("AssuranceLifecycleEarlyGrant.cfg", 12, "Error: Invariant GrantRequiresCurrentDecision is violated."),
    ("AssuranceLifecycleAfterRevoke.cfg", 12, "Error: Invariant NoUnsafeEffectStart is violated."),
)


class TlaContractTest(unittest.TestCase):
    def test_bounded_lifecycle(self) -> None:
        configured = os.environ.get("TLA_TOOLS_JAR")
        self.assertIsNotNone(configured, "TLA_TOOLS_JAR must name v1.7.2")
        jar = Path(configured).resolve(strict=True)
        actual = hashlib.sha256(jar.read_bytes()).hexdigest()
        self.assertEqual(actual, TOOLS_SHA256, "TLA+ tools digest mismatch")
        for config, expected_code, expected_text in CASES:
            with self.subTest(config=config):
                with tempfile.TemporaryDirectory(prefix="aitia-tlc-") as directory:
                    result = subprocess.run(
                        ("java", "-XX:+UseParallelGC", "-Xmx512m", "-cp", str(jar),
                         "tlc2.TLC", "-workers", "1", "-metadir", directory,
                         "-config", config, "AssuranceLifecycle"),
                        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, errors="replace", timeout=60, check=False,
                    )
                self.assertEqual(result.returncode, expected_code, result.stdout[-6000:])
                self.assertIn(expected_text, result.stdout[-6000:])
                if expected_code != 0:
                    self.assertTrue(
                        "counter-example" in result.stdout
                        or "behavior up to this point" in result.stdout,
                        result.stdout[-6000:],
                    )
