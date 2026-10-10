# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Check Quint's fair and unfair lifecycle specs with TLC's native temporal lane.

Quint's ``verify --temporal`` places its default transition spec beside the
selected property; TLC rejects an implication that embeds weak-fairness actions.
Compiling the Quint source and selecting its named spec in a TLC config keeps
the source of truth in Quint while exercising the exact fairness formula.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from process_runner import run


ROOT = Path(__file__).resolve().parent
QUINT = os.environ.get("AITIA_QUINT_BIN") or shutil.which("quint")
APALACHE = (Path(os.environ["QUINT_HOME"]) if "QUINT_HOME" in os.environ
            else Path.home() / ".quint") / "apalache-dist-0.62.1/apalache/lib/apalache.jar"


def main() -> int:
    if not QUINT or not APALACHE.is_file():
        raise SystemExit("Quint 0.33.0 and its Apalache 0.62.1 TLC jar are required")
    version = subprocess.check_output((QUINT, "--version"), text=True, timeout=5).strip()
    if version != "0.33.0":
        raise SystemExit(f"expected Quint 0.33.0, found {version}")
    print("QUINT-PROGRESS: compiling lifecycle to temporary TLA+", flush=True)
    compiled_status, compiled_output = run(
        (QUINT, "compile", str(ROOT / "AssuranceLifecycle.qnt"),
         "--target", "tlaplus", "--step", "stableStep",
         "--temporal", "EventuallyEffect"),
        ROOT, "quint-compile",
    )
    module_start = compiled_output.find("-------------------------- MODULE AssuranceLifecycle")
    source = compiled_output[module_start:] if module_start >= 0 else ""
    if compiled_status or module_start < 0 or not source.rstrip().endswith("===="):
        raise SystemExit(f"Quint compilation failed: {compiled_output[-3000:]}")
    with tempfile.TemporaryDirectory(prefix="aitia-quint-progress-") as directory:
        work = Path(directory)
        (work / "AssuranceLifecycle.tla").write_text(source)
        for name, spec, expected_code, marker in (
            ("fair", "stableSpec", 0, "Model checking completed. No error has been found."),
            ("no-fair", "stableSpecNoFair", 13, "Error: Temporal property EventuallyEffect was violated."),
        ):
            print(f"QUINT-PROGRESS: checking {name}", flush=True)
            config = work / f"{name}.cfg"
            config.write_text(f"SPECIFICATION {spec}\nPROPERTY EventuallyEffect\n")
            meta = work / f"meta-{name}"
            meta.mkdir()
            status, output = run(
                ("java", "-XX:+UseParallelGC", "-Xmx512m", "-cp", str(APALACHE),
                 "tlc2.TLC", "-workers", "1", "-metadir", str(meta),
                 "-config", str(config), str(work / "AssuranceLifecycle.tla")),
                work, f"quint-progress-{name}",
            )
            counts = re.search(r"(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue", output)
            if status != expected_code or marker not in output or not counts:
                raise SystemExit(f"QUINT-PROGRESS-FAILED: {name} exit={status}\n{output[-5000:]}")
            if int(counts[2]) != 18 or int(counts[3]) != 0:
                raise SystemExit(f"QUINT-PROGRESS-FAILED: unexpected {name} state space")
            if expected_code and "counter-example" not in output:
                raise SystemExit(f"QUINT-PROGRESS-FAILED: no counterexample for {name}")
            print(f"QUINT-PROGRESS-OK: {name} distinct={counts[2]}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
