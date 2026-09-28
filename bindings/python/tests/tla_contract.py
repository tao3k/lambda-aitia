# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Project test for bounded TLC contracts and typed counterexamples."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
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
WORK_CASES = (
    ("WorkLifecycle.cfg", 0, "Model checking completed. No error has been found."),
    ("WorkCancellation.cfg", 0, "Model checking completed. No error has been found."),
    ("WorkCancellationReachable.cfg", 12, "Error: Invariant NeverCancelled is violated."),
    ("WorkQuiescenceReachable.cfg", 12, "Error: Invariant NeverQuiescent is violated."),
)
RETIREMENT_CASES = (
    ("RetirementReview.cfg", 0, "Model checking completed. No error has been found."),
    ("RetirementReviewCancellation.cfg", 12, "Error: Invariant NoOutstandingWork is violated."),
    ("RetirementReviewStale.cfg", 12, "Error: Invariant NoOutstandingWork is violated."),
    ("RetirementReviewUnknown.cfg", 12, "Error: Invariant InventoryKnown is violated."),
    ("RetirementReviewReachable.cfg", 12, "Error: Invariant NeverRetired is violated."),
)
INGRESS_CASES = (
    ("RetirementIngress.cfg", 0, "Model checking completed. No error has been found."),
    ("RetirementIngressUnfenced.cfg", 12, "Error: Invariant NoPostRetirementStart is violated."),
    ("RetirementIngressCachedGrant.cfg", 12, "Error: Invariant NoPostRetirementStart is violated."),
    ("RetirementIngressRejected.cfg", 12, "Error: Invariant NeverRejectAfterRetirement is violated."),
    ("RetirementIngressStarted.cfg", 12, "Error: Invariant NeverStarted is violated."),
)


class TlaContractTest(unittest.TestCase):
    def test_bounded_lifecycle(self) -> None:
        self.check_cases("AssuranceLifecycle", CASES)

    def test_work(self) -> None:
        self.check_cases("WorkLifecycle", WORK_CASES)

    def test_retirement(self) -> None:
        self.check_cases("RetirementReview", RETIREMENT_CASES)

    def test_ingress(self) -> None:
        self.check_cases("RetirementIngress", INGRESS_CASES)

    def check_cases(self, model: str, cases: tuple) -> None:
        configured = os.environ.get("TLA_TOOLS_JAR")
        self.assertIsNotNone(configured, "TLA_TOOLS_JAR must name v1.7.2")
        jar = Path(configured).resolve(strict=True)
        actual = hashlib.sha256(jar.read_bytes()).hexdigest()
        self.assertEqual(actual, TOOLS_SHA256, "TLA+ tools digest mismatch")
        for config, expected_code, expected_text in cases:
            with self.subTest(config=config):
                with tempfile.TemporaryDirectory(prefix="aitia-tlc-") as directory:
                    result = subprocess.run(
                        ("java", "-XX:+UseParallelGC", "-Xmx512m", "-cp", str(jar),
                         "tlc2.TLC", "-workers", "1", "-metadir", directory,
                         "-config", config, model),
                        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                        text=True, errors="replace", timeout=60, check=False,
                    )
                self.assertEqual(result.returncode, expected_code, result.stdout[-6000:])
                self.assertIn(expected_text, result.stdout[-6000:])
                explored = re.search(
                    r"(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue",
                    result.stdout,
                )
                self.assertIsNotNone(explored, result.stdout[-6000:])
                self.assertGreater(int(explored[2]), 0, "empty state exploration")
                if expected_code == 0:
                    self.assertEqual(int(explored[3]), 0, "incomplete exploration")
                print(f"{config}: generated={explored[1]} distinct={explored[2]} "
                      f"queued={explored[3]} exit={result.returncode}", flush=True)
                if expected_code != 0:
                    self.assertTrue(
                        "counter-example" in result.stdout
                        or "behavior up to this point" in result.stdout,
                        result.stdout[-6000:],
                    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module", nargs="?", default="all",
                        choices=("all", "lifecycle", "work", "retirement", "ingress"))
    selected = parser.parse_args().module
    methods = {"lifecycle": "test_bounded_lifecycle", "work": "test_work",
               "retirement": "test_retirement", "ingress": "test_ingress"}
    target = "TlaContractTest"
    if selected != "all":
        target += "." + methods[selected]
    unittest.main(argv=[__file__, target, "-v"])
