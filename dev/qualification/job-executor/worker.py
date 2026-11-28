# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Qualification worker with a persistent task ledger and HTTP side effect."""

import sqlite3
import sys
from urllib.request import ProxyHandler, Request, build_opener
from uuid import uuid4


def execute(ledger_path: str, endpoint: str, mode: str) -> int:
    if mode not in ("buggy", "fixed"):
        raise ValueError("unknown worker mode")
    with sqlite3.connect(ledger_path) as ledger:
        ledger.execute(
            "create table if not exists tasks (job text primary key, state text not null)"
        )
        ledger.execute("insert or ignore into tasks values ('job-42', 'pending')")
        state = ledger.execute(
            "select state from tasks where job = 'job-42'"
        ).fetchone()[0]
        if state == "complete":
            return 0
    # Bug: regenerating the provider key after restart creates a second effect.
    key = "job-42" if mode == "fixed" else uuid4().hex
    request = Request(endpoint, data=b"commit", headers={"Idempotency-Key": key})
    try:
        with build_opener(ProxyHandler({})).open(request, timeout=3) as response:
            if response.status != 200:
                return 2
    except Exception:
        return 2
    with sqlite3.connect(ledger_path) as ledger:
        ledger.execute("update tasks set state = 'complete' where job = 'job-42'")
    return 0


if __name__ == "__main__":
    raise SystemExit(execute(sys.argv[1], sys.argv[2], sys.argv[3]))
