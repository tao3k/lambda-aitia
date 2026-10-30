# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Replay pinned Quint MBT traces through the actual serialized Scheme Host.

Sampling is not exhaustive refinement. Require all safe actions and both real
unsafe-model counterexamples; compare every projected state, not just outcomes.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from process_runner import run

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
ACTIONS = {"RequestCancellation", "ObserveCompletion", "ObserveQueueDrained",
           "CompleteInventory", "ReviewCut", "ObserveLateActivity",
           "ObserveInventoryGap", "CloseIngress", "Request", "Start", "Reject",
           "Retire", "Terminal"}
FIELDS = (("active?", "work", "active"), ("queued?", "work", "queued"),
          ("cancellation-requested?", "work", "cancelRequested"),
          ("inventory-known?", "known"), ("reviewed?", "reviewed"),
          ("late-activity-found?", "lateFound"), ("inventory-gap-found?", "gapFound"),
          ("retired?", "retired"), ("ingress-open?", "ingressOpen"),
          ("authority-epoch", "epoch"), ("cached-grant-epoch", "grantEpoch"),
          ("pending?", "pending"), ("attempted?", "attempted"))


def scalar(value):
    if isinstance(value, bool):
        return "#t" if value else "#f"
    if isinstance(value, dict) and set(value) == {"#bigint"}:
        return str(int(value["#bigint"]))
    raise ValueError(f"unexpected ITF scalar: {value!r}")


def state_row(state):
    q = state["q"]
    expected_keys = {path[1] for path in FIELDS} | {"rejectedAfterRetirement", "startedAfterRetirement"}
    if set(q) != expected_keys or set(q["work"]) != {"active", "queued", "cancelRequested"}:
        raise ValueError("model state schema changed; update the explicit correspondence")
    fields = []
    for slot, *path in FIELDS:
        value = q
        for key in path:
            value = value[key]
        fields.append(f"({slot} {scalar(value)})")
    # MBT action names are a closed set, never arbitrary executable Scheme.
    action = state["mbt::actionTaken"]
    if action not in ACTIONS | {"init", "TrustCachedGrant", "RetireWithoutFence"}:
        raise ValueError(f"unknown Quint action: {action!r}")
    return f"({action} ({' '.join(fields)}))"


def generate(quint, directory, name, step, invariant, samples):
    print(f"QUINT-SCHEME: generate {name}", flush=True)
    negative = step != "step"
    status, output = run(
        [quint, "run", str(ROOT / "RetirementIngress.qnt"), "--backend", "typescript",
         "--seed", "34", "--max-samples", str(samples),
         "--n-traces", "1" if negative else str(samples),
         "--max-steps", "18", "--mbt", "--step", step, "--invariant", invariant,
         "--verbosity", "1", "--out-itf", str(directory / f"{name}_{{seq}}.json")],
        REPO, name)
    marker = "Invariant violated" if negative else "[ok] No violation found"
    if status != int(negative) or marker not in output:
        raise RuntimeError(f"{name}: unexpected Quint result exit={status}\n{output[-2000:]}")
    traces = [json.loads(path.read_text())["states"]
              for path in sorted(directory.glob(f"{name}_*.json"))]
    if not traces or (not negative and len(traces) != samples):
        raise RuntimeError(f"{name}: incomplete trace output ({len(traces)})")
    if negative:
        # Quint may retain passing samples too. Only actual failing traces
        # belong to the negative lane; their final unsafe action is refused.
        fault = "RetireWithoutFence" if step == "unfencedStep" else "TrustCachedGrant"
        traces = [trace for trace in traces if trace[-1]["mbt::actionTaken"] == fault
                  and (trace[-1]["q"]["retired"] if fault == "RetireWithoutFence"
                       else trace[-1]["q"]["startedAfterRetirement"])]
        if not traces:
            raise RuntimeError(f"{name}: missing typed unsafe counterexample")
    return traces


def main():
    quint = os.environ.get("AITIA_QUINT_BIN") or shutil.which("quint")
    if not quint:
        quint = str(ROOT / "node_modules/.bin/quint")
    version = subprocess.check_output([quint, "--version"], text=True, timeout=5).strip()
    if version != "0.33.0":
        raise RuntimeError(f"expected Quint 0.33.0, found {version!r}")
    with tempfile.TemporaryDirectory(prefix="aitia-quint-replay-") as temporary:
        directory = Path(temporary)
        safe = generate(quint, directory, "safe", "step",
                        "TypeOK and RetiredIsFenced and NoPostRetirementStart and NoOutstandingWork and InventoryKnown", 512)
        covered = {state["mbt::actionTaken"] for trace in safe for state in trace[1:]}
        if covered != ACTIONS:
            raise RuntimeError(f"safe action coverage mismatch: {covered ^ ACTIONS}")
        witnesses = [state["q"] for trace in safe for state in trace]
        distinct = len({json.dumps(q, sort_keys=True) for q in witnesses})
        if distinct < 177:
            raise RuntimeError(f"safe state coverage regressed: {distinct} < 177")
        if not any(q["rejectedAfterRetirement"] for q in witnesses):
            raise RuntimeError("missing post-retirement rejection witness")
        unfenced = generate(quint, directory, "unfenced", "unfencedStep", "RetiredIsFenced", 512)
        cached = generate(quint, directory, "cached", "cachedGrantStep", "NoPostRetirementStart", 512)
        lanes = (("safe", safe), ("unfenced", unfenced), ("cached", cached))
        fixture = directory / "traces.scm"
        fixture.write_text("(" + "\n".join(
            f"({name} ({' '.join('(' + ' '.join(map(state_row, trace)) + ')' for trace in traces)}))"
            for name, traces in lanes) + ")\n")
        environment = dict(os.environ, AITIA_QUINT_REPLAY=str(fixture))
        result = subprocess.run(["just", "test-scheme-atomic", "formal", "retirement-replay-test.ss"],
                                cwd=REPO, env=environment, timeout=65, check=False)
        if result.returncode:
            raise SystemExit(result.returncode)
        print(f"QUINT-SCHEME-OK: safe-traces={len(safe)} states={distinct}/248 "
              f"actions={len(covered)} negative-traces={len(unfenced) + len(cached)}", flush=True)


if __name__ == "__main__":
    main()
