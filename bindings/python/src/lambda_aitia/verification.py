# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Observable pytest execution, not an Assurance Host admission."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
from uuid import uuid4
import xml.etree.ElementTree as ET


def source_digest(root: Path) -> str:
    """Hash the exact regular-file tree selected for a verifier run."""

    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("source root must be a directory")
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"source tree contains a symlink: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"source tree contains a non-file: {path}")
        relative = path.relative_to(root).as_posix().encode("utf-8")
        contents = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(contents).to_bytes(8, "big"))
        digest.update(contents)
    return "sha256:" + digest.hexdigest()


@dataclass(frozen=True, slots=True)
class PytestObservation:
    """One subprocess observation; this value carries no issuing authority."""

    run_id: str
    source_digest: str
    argv: tuple[str, ...]
    exit_code: int | None
    status: str
    collected: int
    passed: int
    skipped: int
    report_digest: str | None
    output: str

    @property
    def passed_obligation(self) -> bool:
        return self.status == "passed"

    def source_current(self, root: Path) -> bool:
        try:
            return source_digest(root) == self.source_digest
        except (OSError, ValueError):
            return False


def run_pytest(
    python: Path,
    source_root: Path,
    selectors: tuple[str, ...],
    *,
    timeout_seconds: int = 30,
    environment: dict[str, str] | None = None,
) -> PytestObservation:
    """Run selected tests in a caller-frozen tree and validate their JUnit report.

    The caller owns the tree, interpreter, dependencies, and external services.
    This function detects source drift, but cannot prove process isolation or
    turn its result into a Host-issued seal.
    """

    if not selectors or any(not item or item.startswith("-") for item in selectors):
        raise ValueError("at least one explicit pytest selector is required")
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    root = source_root.resolve(strict=True)
    before = source_digest(root)
    run_id = uuid4().hex
    interpreter = python.absolute()
    if not interpreter.is_file():
        raise ValueError("Python interpreter is absent")
    safe_environment = os.environ.copy()
    for name in ("PYTHONPATH", "PYTEST_ADDOPTS", "PYTEST_PLUGINS"):
        safe_environment.pop(name, None)
    safe_environment["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    safe_environment["PYTHONDONTWRITEBYTECODE"] = "1"
    if environment:
        if any(not key.startswith("AITIA_QUALIFICATION_") for key in environment):
            raise ValueError("only AITIA_QUALIFICATION_ environment values are allowed")
        safe_environment.update(environment)
    with tempfile.TemporaryDirectory(prefix="aitia-pytest-") as report_directory:
        report = Path(report_directory) / f"{run_id}.xml"
        argv = (
            str(interpreter), "-m", "pytest", "-q",
            "-p", "no:cacheprovider", f"--junitxml={report}", *selectors,
        )
        try:
            completed = subprocess.run(
                argv, cwd=root, env=safe_environment, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, errors="replace",
                timeout=timeout_seconds, check=False,
            )
            exit_code = completed.returncode
            output = completed.stdout
        except subprocess.TimeoutExpired as error:
            exit_code = None
            output = (error.stdout or b"").decode("utf-8", "replace") if isinstance(error.stdout, bytes) else (error.stdout or "")
        after = source_digest(root)
        collected = passed = skipped = 0
        report_digest = None
        report_valid = False
        if report.is_file():
            report_bytes = report.read_bytes()
            report_digest = "sha256:" + hashlib.sha256(report_bytes).hexdigest()
            try:
                suites = ET.fromstring(report_bytes)
                cases = suites.findall(".//testcase")
                collected = len(cases)
                skipped = sum(case.find("skipped") is not None for case in cases)
                failed = sum(
                    case.find("failure") is not None or case.find("error") is not None
                    for case in cases
                )
                passed = collected - skipped - failed
                report_valid = suites.tag in ("testsuite", "testsuites")
            except ET.ParseError:
                pass
        if before != after:
            status = "source-changed"
        elif exit_code is None:
            status = "timeout"
        elif exit_code == 2:
            status = "interrupted"
        elif exit_code == 3:
            status = "internal-error"
        elif exit_code == 4:
            status = "usage-error"
        elif exit_code == 6:
            status = "warnings-exceeded"
        elif not report_valid:
            status = "report-invalid"
        elif collected == 0:
            status = "no-tests"
        elif exit_code != 0 or passed + skipped != collected:
            status = "failed"
        elif passed == 0:
            status = "no-passing-tests"
        elif skipped:
            status = "skipped"
        else:
            status = "passed"
        return PytestObservation(
            run_id, before, argv, exit_code, status, collected, passed,
            skipped, report_digest, output[-8192:],
        )
