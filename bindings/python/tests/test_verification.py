# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

from pathlib import Path
import sys

import pytest

from lambda_aitia.verification import run_pytest


@pytest.mark.parametrize(
    ("body", "status"),
    [
        ("def test_ok():\n    assert True\n", "passed"),
        ("def test_no():\n    assert False\n", "failed"),
        ("import pytest\n@pytest.mark.skip\ndef test_skip():\n    pass\n", "no-passing-tests"),
    ],
)
def test_pytest_observation_classifies_execution(
    tmp_path: Path, body: str, status: str
) -> None:
    (tmp_path / "test_case.py").write_text(body)
    observed = run_pytest(Path(sys.executable), tmp_path, ("test_case.py",))
    assert observed.status == status
    assert observed.passed_obligation is (status == "passed")
    assert observed.collected == 1
    assert observed.report_digest is not None
    assert observed.source_current(tmp_path)


def test_pytest_observation_rejects_no_collection(tmp_path: Path) -> None:
    (tmp_path / "test_case.py").write_text("x = 1\n")
    observed = run_pytest(Path(sys.executable), tmp_path, ("test_case.py",))
    assert observed.status == "no-tests"
    assert observed.exit_code == 5


def test_pytest_observation_detects_source_drift(tmp_path: Path) -> None:
    source = tmp_path / "test_case.py"
    source.write_text(
        "from pathlib import Path\n"
        "def test_change():\n"
        "    Path(__file__).write_text('changed')\n"
    )
    observed = run_pytest(Path(sys.executable), tmp_path, ("test_case.py",))
    assert observed.status == "source-changed"
    assert not observed.passed_obligation
    assert not observed.source_current(tmp_path)


def test_pytest_observation_rejects_timeout(tmp_path: Path) -> None:
    (tmp_path / "test_case.py").write_text(
        "from time import sleep\n"
        "def test_slow():\n"
        "    sleep(5)\n"
    )
    observed = run_pytest(
        Path(sys.executable), tmp_path, ("test_case.py",), timeout_seconds=1
    )
    assert observed.status == "timeout"
    assert observed.exit_code is None
    assert not observed.passed_obligation
