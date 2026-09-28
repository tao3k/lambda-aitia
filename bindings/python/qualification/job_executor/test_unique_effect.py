# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Project qualification of acknowledgement loss in real worker processes."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from threading import Thread


def test_unique_effect_after_lost_ack_and_restart() -> None:
    mode = os.environ["AITIA_QUALIFICATION_MODE"]
    with tempfile.TemporaryDirectory(prefix="aitia-worker-state-") as directory:
        state = Path(directory)
        effects = state / "effects.sqlite"
        ledger = state / "tasks.sqlite"

        class EffectHandler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                key = self.headers.get("Idempotency-Key")
                assert key
                with sqlite3.connect(effects) as database:
                    database.execute(
                        "create table if not exists effects "
                        "(key text primary key, payload blob not null)"
                    )
                    previous = database.execute(
                        "select count(*) from effects"
                    ).fetchone()[0]
                    database.execute(
                        "insert or ignore into effects values (?, ?)",
                        (key, self.rfile.read(int(self.headers["Content-Length"]))),
                    )
                if previous == 0:
                    # The service committed; the worker never receives its ACK.
                    self.close_connection = True
                    return
                self.send_response(200)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), EffectHandler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            endpoint = f"http://127.0.0.1:{server.server_port}/effect"
            command = (sys.executable, str(Path(__file__).with_name("worker.py")),
                       str(ledger), endpoint, mode)
            first = subprocess.run(command, check=False, timeout=10)
            second = subprocess.run(command, check=False, timeout=10)
            assert first.returncode == 2
            assert second.returncode == 0
            with sqlite3.connect(effects) as database:
                committed = database.execute("select count(*) from effects").fetchone()[0]
            with sqlite3.connect(ledger) as database:
                final_state = database.execute(
                    "select state from tasks where job = 'job-42'"
                ).fetchone()[0]
            assert committed == 1
            assert final_state == "complete"
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
