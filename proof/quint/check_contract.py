# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Exhaust Quint design models and require typed negative-control traces."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

from process_runner import run


ROOT = Path(__file__).resolve().parent
QUINT = os.environ.get("AITIA_QUINT_BIN") or shutil.which("quint")
COUNTS = re.compile(r"(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue")
SAFE_DISTINCT = {"work-safe": 8, "work-cancellation": 2,
                 "retirement-safe": 42, "ingress-safe": 248,
                 "lifecycle-safe": 2202}
# lane, name, model, transition, invariant(s), expected counterexample
CASES = (
    ("work", "work-safe", "WorkLifecycle", "step", "TypeOK", False),
    ("work", "work-cancellation", "WorkLifecycle", "cancellationStep", "WorkRemains", False),
    ("work", "work-cancel-reachable", "WorkLifecycle", "cancellationStep", "NeverCancelled", True),
    ("work", "work-quiescent-reachable", "WorkLifecycle", "step", "NeverQuiescent", True),
    ("retirement", "retirement-safe", "RetirementReview", "step", "TypeOK,NoOutstandingWork,InventoryKnown", False),
    ("retirement", "retirement-trust-cancel", "RetirementReview", "cancellationStep", "NoOutstandingWork", True),
    ("retirement", "retirement-stale-review", "RetirementReview", "staleStep", "NoOutstandingWork", True),
    ("retirement", "retirement-unknown-inventory", "RetirementReview", "unknownStep", "InventoryKnown", True),
    ("retirement", "retirement-reachable", "RetirementReview", "step", "NeverRetired", True),
    ("ingress", "ingress-safe", "RetirementIngress", "step", "TypeOK,RetiredIsFenced,NoPostRetirementStart,NoOutstandingWork,InventoryKnown", False),
    ("ingress", "ingress-unfenced", "RetirementIngress", "unfencedStep", "NoPostRetirementStart", True),
    ("ingress", "ingress-cached-grant", "RetirementIngress", "cachedGrantStep", "NoPostRetirementStart", True),
    ("ingress", "ingress-reject-reachable", "RetirementIngress", "step", "NeverRejectAfterRetirement", True),
    ("ingress", "ingress-start-reachable", "RetirementIngress", "step", "NeverStarted", True),
    ("lifecycle", "lifecycle-safe", "AssuranceLifecycle", "step", "TypeOK,AdmissionIsCurrent,DecisionRequiresAdmission,GrantRequiresCurrentDecision,NoUnsafeEffectStart", False),
    ("lifecycle", "lifecycle-start-reachable", "AssuranceLifecycle", "step", "NoEffectStarted", True),
    ("lifecycle", "lifecycle-untrusted-report", "AssuranceLifecycle", "unsafeStep", "NoUnsafeEffectStart", True),
    ("lifecycle", "lifecycle-late-admission", "AssuranceLifecycle", "lateAdmitStep", "AdmissionIsCurrent", True),
    ("lifecycle", "lifecycle-early-grant", "AssuranceLifecycle", "earlyGrantStep", "GrantRequiresCurrentDecision", True),
    ("lifecycle", "lifecycle-after-revoke", "AssuranceLifecycle", "afterRevokeStep", "NoUnsafeEffectStart", True),
)


def check_case(case: tuple) -> None:
    lane, name, model, transition, invariants, negative = case
    print(f"QUINT-CHECK: {name}", flush=True)
    command = [QUINT, "verify", str(ROOT / f"{model}.qnt"), "--backend", "tlc",
               "--step", transition, "--tlc-config", str(ROOT / "tlc-config.json"),
               "--verbosity", "3"]
    if "," in invariants:
        command += ["--invariants", *invariants.split(",")]
    else:
        command += ["--invariant", invariants]
    status, output = run(command, ROOT, name)
    counts = COUNTS.search(output)
    expected_code = 1 if negative else 0
    marker = "Error: Invariant q_inv is violated." if negative else "[ok] No violation found"
    if (status != expected_code or marker not in output or not counts
            or int(counts[2]) == 0 or (not negative and int(counts[3]) != 0)
            or (name in SAFE_DISTINCT and int(counts[2]) != SAFE_DISTINCT[name])
            or (negative and ("error: found a counterexample" not in output
                              or "behavior up to this point" not in output))):
        raise SystemExit(f"QUINT-CHECK-FAILED: {name} exit={status}\n{output[-6000:]}")
    print(f"QUINT-CHECK-OK: {name} distinct={counts[2]} exit={status}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lane", nargs="?", default="all",
                        choices=("all", "work", "retirement", "ingress", "lifecycle"))
    selected = parser.parse_args().lane
    if not QUINT:
        parser.error("Quint executable is required")
    version = subprocess.check_output((QUINT, "--version"), text=True, timeout=5).strip()
    if version != "0.33.0":
        parser.error(f"expected Quint 0.33.0, found {version!r}")
    for case in CASES:
        if selected in ("all", case[0]):
            check_case(case)
    if selected in ("all", "lifecycle"):
        result = subprocess.run(("python3", str(ROOT / "check_progress.py")),
                                cwd=ROOT, timeout=120, check=False)
        if result.returncode:
            raise SystemExit(result.returncode)
    print("QUINT-CHECK-OK: selected model contracts complete", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
