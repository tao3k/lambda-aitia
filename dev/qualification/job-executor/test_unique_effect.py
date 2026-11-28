# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Project qualification of acknowledgement loss in real worker processes."""

from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer
import sqlite3
import subprocess
import sys
import tempfile
from threading import Barrier, Event, Thread
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener

import pytest


class LoopbackEffectServer(ThreadingHTTPServer):
    def server_bind(self) -> None:
        # The fixture uses a numeric loopback endpoint. No DNS is required.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address


@pytest.mark.parametrize("mode", ["fixed", "buggy"])
def test_unique_effect_after_lost_ack_and_restart(mode: str) -> None:
    exercise_provider(mode, competing_first=False)
    if mode == "fixed":
        exercise_provider(mode, competing_first=True)


def exercise_provider(mode: str, *, competing_first: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="aitia-worker-state-") as directory:
        state = Path(directory)
        effects = state / "effects.sqlite"
        ledger = state / "tasks.sqlite"
        ack_lost = Event()
        workers_arrived = Barrier(2, timeout=3)

        class EffectHandler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                key = self.headers.get("Idempotency-Key")
                assert key
                payload = self.rfile.read(int(self.headers["Content-Length"]))
                if mode == "fixed" and payload == b"commit":
                    if competing_first or ack_lost.is_set():
                        # Both workers must reach the Provider before either
                        # can receive an ACK and mark the task complete.
                        workers_arrived.wait()
                with sqlite3.connect(effects) as database:
                    # Take the write lock before reading the effect inventory.
                    # Only the transaction that sees an empty ledger loses its ACK.
                    database.execute("begin immediate")
                    database.execute(
                        "create table if not exists effects "
                        "(key text primary key, payload blob not null)"
                    )
                    previous = database.execute(
                        "select count(*) from effects"
                    ).fetchone()[0]
                    database.execute(
                        "insert or ignore into effects values (?, ?)",
                        (key, payload),
                    )
                    recorded_payload = database.execute(
                        "select payload from effects where key = ?", (key,)
                    ).fetchone()[0]
                if recorded_payload != payload:
                    self.send_error(409, "Idempotency key already binds a different payload")
                    return
                if previous == 0:
                    # The service committed; the worker never receives its ACK.
                    ack_lost.set()
                    self.close_connection = True
                    return
                self.send_response(200)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                pass

        server = LoopbackEffectServer(("127.0.0.1", 0), EffectHandler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            endpoint = f"http://127.0.0.1:{server.server_port}/effect"
            command = (sys.executable, str(Path(__file__).with_name("worker.py")),
                       str(ledger), endpoint, mode)
            def run_worker() -> int:
                return subprocess.run(command, check=False, timeout=10).returncode

            def run_concurrently() -> list[int]:
                with ThreadPoolExecutor(max_workers=2) as workers:
                    attempts = [workers.submit(run_worker) for _ in range(2)]
                    return sorted(attempt.result() for attempt in attempts)

            if competing_first:
                assert run_concurrently() == [0, 2]
            else:
                assert run_worker() == 2
                if mode == "fixed":
                    with sqlite3.connect(effects) as database:
                        (key, recorded_payload), = database.execute(
                            "select key, payload from effects"
                        ).fetchall()
                    assert recorded_payload == b"commit"
                    changed = Request(
                        endpoint, data=b"different intent", headers={"Idempotency-Key": key}
                    )
                    with pytest.raises(HTTPError) as conflict:
                        build_opener(ProxyHandler({})).open(changed, timeout=3)
                    with conflict.value as response:
                        assert response.code == 409
                    assert run_concurrently() == [0, 0]
                else:
                    assert run_worker() == 0
            with sqlite3.connect(effects) as database:
                payloads = database.execute("select payload from effects").fetchall()
                committed = len(payloads)
            with sqlite3.connect(ledger) as database:
                final_state = database.execute(
                    "select state from tasks where job = 'job-42'"
                ).fetchone()[0]
            assert committed == 1, f"ADR0008 duplicate effects: expected 1, observed {committed}"
            assert payloads == [(b"commit",)]
            assert final_state == "complete"
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
