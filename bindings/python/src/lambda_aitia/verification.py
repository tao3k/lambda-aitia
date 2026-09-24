# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Observable pytest execution, not an Assurance Host admission."""

from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import subprocess
import tempfile
from uuid import uuid4
import xml.etree.ElementTree as ET


_SOURCE_MAGIC = b"lambda-aitia.source-tree.v1\0"
_MAX_SOURCE_BYTES = 64 * 1024 * 1024
_MAX_SOURCE_FILES = 10_000


def _source_payload_digest(payload: bytes) -> str:
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def capture_source_tree(root: Path) -> bytes:
    """Freeze a regular-file tree into canonical, source-lock-compatible bytes.

    Source paths and contents are length-framed, ordered, and bounded. The
    returned bytes can be independently rehashed by the Scheme Host's source
    reader; their digest is not a verification seal.
    """

    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("source root must be a directory")
    entries: list[tuple[bytes, bytes]] = []
    size = len(_SOURCE_MAGIC) + 8
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"source tree contains a symlink: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"source tree contains a non-file: {path}")
        relative = path.relative_to(root).as_posix().encode("utf-8")
        remaining = _MAX_SOURCE_BYTES - size - 4 - len(relative) - 8
        if remaining < 0:
            raise ValueError("source tree exceeds verifier capture limit")
        with path.open("rb") as source:
            contents = source.read(remaining + 1)
        size += 4 + len(relative) + 8 + len(contents)
        if size > _MAX_SOURCE_BYTES or len(entries) >= _MAX_SOURCE_FILES:
            raise ValueError("source tree exceeds verifier capture limit")
        entries.append((relative, contents))
    entries.sort(key=lambda entry: entry[0])
    framed = bytearray(_SOURCE_MAGIC)
    framed.extend(len(entries).to_bytes(8, "big"))
    for relative, contents in entries:
        framed.extend(len(relative).to_bytes(4, "big"))
        framed.extend(relative)
        framed.extend(len(contents).to_bytes(8, "big"))
        framed.extend(contents)
    return bytes(framed)


def _source_entries(payload: bytes) -> tuple[tuple[Path, bytes], ...]:
    if len(payload) > _MAX_SOURCE_BYTES or not payload.startswith(_SOURCE_MAGIC):
        raise ValueError("invalid frozen source payload")
    position = len(_SOURCE_MAGIC)

    def take(length: int) -> bytes:
        nonlocal position
        if length < 0 or position + length > len(payload):
            raise ValueError("truncated frozen source payload")
        result = payload[position : position + length]
        position += length
        return result

    count = int.from_bytes(take(8), "big")
    if count > _MAX_SOURCE_FILES:
        raise ValueError("frozen source file count exceeds limit")
    entries: list[tuple[Path, bytes]] = []
    previous = b""
    for _ in range(count):
        relative = take(int.from_bytes(take(4), "big"))
        if not relative or relative <= previous or b"\\" in relative or b"\0" in relative:
            raise ValueError("invalid frozen source path ordering")
        previous = relative
        try:
            decoded = relative.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError("invalid frozen source path encoding") from error
        path = PurePosixPath(decoded)
        if (
            path.is_absolute()
            or PureWindowsPath(decoded).drive
            or any(part in ("", ".", "..") for part in decoded.split("/"))
        ):
            raise ValueError("frozen source path escapes root")
        contents = take(int.from_bytes(take(8), "big"))
        entries.append((Path(*path.parts), contents))
    if position != len(payload):
        raise ValueError("trailing frozen source payload bytes")
    return tuple(entries)


def source_digest(root: Path) -> str:
    """Hash the canonical frozen bytes of a regular-file tree."""

    return _source_payload_digest(capture_source_tree(root))


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


def _validated_selectors(
    selectors: tuple[str, ...], entries: tuple[tuple[Path, bytes], ...]
) -> None:
    selected_files = {path.as_posix() for path, _ in entries}
    if not selectors:
        raise ValueError("at least one explicit pytest selector is required")
    for selector in selectors:
        filename = selector.split("::", 1)[0]
        if (
            not filename
            or selector.startswith("-")
            or "\\" in filename
            or "\0" in filename
            or any(part in ("", ".", "..") for part in filename.split("/"))
            or filename not in selected_files
        ):
            raise ValueError("pytest selector must name a file in frozen source")


def run_pytest_frozen(
    python: Path,
    source_payload: bytes,
    selectors: tuple[str, ...],
    *,
    timeout_seconds: int = 30,
    environment: dict[str, str] | None = None,
) -> PytestObservation:
    """Run selected tests only from a validated frozen source payload.

    The caller owns the interpreter, dependencies and external services. The
    payload is observable process input, not a Host-issued verification seal.
    """

    entries = _source_entries(source_payload)
    _validated_selectors(selectors, entries)
    if timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be positive")
    before = _source_payload_digest(source_payload)
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
    with tempfile.TemporaryDirectory(prefix="aitia-pytest-") as workspace:
        root = Path(workspace) / "source"
        root.mkdir()
        for relative, contents in entries:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
        report = Path(workspace) / f"{run_id}.xml"
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
            output = (
                (error.stdout or b"").decode("utf-8", "replace")
                if isinstance(error.stdout, bytes)
                else (error.stdout or "")
            )
        try:
            after = source_digest(root)
        except (OSError, ValueError):
            after = None
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


def run_pytest(
    python: Path,
    source_root: Path,
    selectors: tuple[str, ...],
    *,
    timeout_seconds: int = 30,
    environment: dict[str, str] | None = None,
) -> PytestObservation:
    """Capture source, execute its frozen copy, and detect caller-tree drift.

    A changing caller tree invalidates the observation, but even a passing
    observation is not a Scheme Assurance Host admission.
    """

    payload = capture_source_tree(source_root)
    observation = run_pytest_frozen(
        python, payload, selectors,
        timeout_seconds=timeout_seconds, environment=environment,
    )
    if not observation.source_current(source_root):
        return replace(observation, status="source-changed")
    return observation
