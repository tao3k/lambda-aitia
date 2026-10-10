# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Run a model checker with real output and a bounded silence watchdog."""

from __future__ import annotations

import os
import selectors
import signal
import subprocess
import time
from pathlib import Path
from typing import Sequence


PROGRESS = (
    "Compiling to TLA+", "Starting checker server", "SanyParser",
    "Running TLC", "Computing initial states", "states generated",
    "Model checking completed", "No violation found", "Invariant q_inv is violated",
    "found a counterexample", "Checking temporal properties", "Temporal property",
)


def run(command: Sequence[str], cwd: Path, label: str, *, timeout: float = 60,
        silence: float = 12) -> tuple[int, str]:
    """Return status and exact output; never count a silent checker as progress."""
    process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    chunks: list[bytes] = []
    pending = b""
    began = last_output = time.monotonic()
    try:
        while selector.get_map():
            now = time.monotonic()
            if now - began > timeout or now - last_output > silence:
                reason = "total timeout" if now - began > timeout else "silent checker"
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise TimeoutError(f"{label}: {reason} after {now - last_output:.1f}s without output")
            events = selector.select(timeout=min(1.0, silence))
            for key, _ in events:
                data = os.read(key.fd, 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                last_output = time.monotonic()
                chunks.append(data)
                pending += data
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    decoded = line.decode(errors="replace")
                    if any(marker in decoded for marker in PROGRESS):
                        print(f"{label}: {decoded.strip()}", flush=True)
        if pending and any(marker in pending.decode(errors="replace") for marker in PROGRESS):
            print(f"{label}: {pending.decode(errors='replace').strip()}", flush=True)
        return process.wait(timeout=3), b"".join(chunks).decode(errors="replace")
    finally:
        selector.close()
        process.stdout.close()
