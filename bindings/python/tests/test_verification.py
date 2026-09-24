# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

from pathlib import Path
import hashlib
import sys

import pytest

from lambda_aitia.verification import (
    capture_source_tree,
    run_pytest,
    run_pytest_frozen,
    source_digest,
)


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
    # The verifier mutated only the frozen execution tree, not caller source.
    assert observed.source_current(tmp_path)
    assert source.read_text().startswith("from pathlib import Path")


def test_frozen_execution_uses_captured_bytes_not_later_source(tmp_path: Path) -> None:
    source = tmp_path / "test_case.py"
    source.write_text("def test_ok():\n    assert True\n")
    payload = capture_source_tree(tmp_path)
    assert source_digest(tmp_path) == "sha256:" + hashlib.sha256(payload).hexdigest()
    source.write_text("def test_no():\n    assert False\n")
    observed = run_pytest_frozen(Path(sys.executable), payload, ("test_case.py",))
    assert observed.status == "passed"
    assert not observed.source_current(tmp_path)
    assert observed.source_digest != source_digest(tmp_path)


def test_frozen_source_rejects_escaping_selectors_and_malformed_bytes(
    tmp_path: Path,
) -> None:
    (tmp_path / "test_case.py").write_text("def test_ok():\n    assert True\n")
    payload = capture_source_tree(tmp_path)
    with pytest.raises(ValueError, match="selector"):
        run_pytest_frozen(Path(sys.executable), payload, ("../test_case.py",))
    with pytest.raises(ValueError, match="trailing"):
        run_pytest_frozen(Path(sys.executable), payload + b"forged", ("test_case.py",))


def test_frozen_source_orders_paths_by_canonical_bytes(tmp_path: Path) -> None:
    nested = tmp_path / "a"
    nested.mkdir()
    (nested / "test_case.py").write_text("def test_ok():\n    assert True\n")
    (tmp_path / "a.txt").write_text("sibling")
    payload = capture_source_tree(tmp_path)
    observed = run_pytest_frozen(Path(sys.executable), payload, ("a/test_case.py",))
    assert observed.status == "passed"


def test_caller_tree_change_during_frozen_run_invalidates_observation(
    tmp_path: Path,
) -> None:
    source = tmp_path / "test_case.py"
    source.write_text(
        "from pathlib import Path\n"
        "def test_mutate_caller():\n"
        f"    Path({str(source)!r}).write_text('changed')\n"
    )
    observed = run_pytest(Path(sys.executable), tmp_path, ("test_case.py",))
    assert observed.status == "source-changed"
    assert not observed.source_current(tmp_path)


def test_source_capture_refuses_symlink(tmp_path: Path) -> None:
    (tmp_path / "real.py").write_text("x = 1\n")
    (tmp_path / "alias.py").symlink_to(tmp_path / "real.py")
    with pytest.raises(ValueError, match="symlink"):
        capture_source_tree(tmp_path)


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
