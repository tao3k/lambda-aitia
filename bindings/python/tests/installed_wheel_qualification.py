# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Project qualification of an installed wheel outside the checkout."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parents[3]
PYTHON = PROJECT / "bindings/python/.venv/bin/python"
WHEELS = PROJECT / "bindings/python/dist"
SCENARIO = PROJECT / "bindings/python/qualification/job_executor"


def run(
    *argv: str,
    cwd: Path,
    environment: dict[str, str] | None = None,
    quiet: bool = False,
) -> None:
    subprocess.run(
        argv, cwd=cwd, env=environment, check=True, timeout=90,
        stdout=subprocess.DEVNULL if quiet else None,
    )


def test_installed_wheel_qualification() -> None:
    wheels = list(WHEELS.glob("lambda_aitia-*.whl"))
    if not wheels:
        raise RuntimeError("build the Aitia wheel before qualification")
    wheel = max(wheels, key=lambda path: path.stat().st_mtime_ns)
    with tempfile.TemporaryDirectory(prefix="aitia-installed-wheel-") as directory:
        root = Path(directory)
        venv = root / "venv"
        scenario = root / "scenario"
        requirements = root / "requirements.txt"
        shutil.copytree(SCENARIO, scenario)
        run("uv", "export", "--offline", "--locked", "--extra", "test",
            "--no-emit-project", "--output-file", str(requirements),
            cwd=PROJECT / "bindings/python", quiet=True)
        run("uv", "venv", "--python", str(PYTHON), str(venv), cwd=root)
        interpreter = venv / "bin/python"
        # A fresh CI cache can lack a locked wheel even when the source-tree
        # environment already has it. Resolve only hashes from uv.lock;
        # reuse cached wheels and fetch missing ones when needed.
        run("uv", "pip", "install", "--python", str(interpreter),
            "-r", str(requirements), cwd=root)
        run("uv", "pip", "install", "--offline", "--no-deps", "--python",
            str(interpreter), str(wheel), cwd=root)
        environment = os.environ.copy()
        for name in ("PYTHONPATH", "LAMBDA_AITIA_NATIVE_LIBRARY", "VIRTUAL_ENV"):
            environment.pop(name, None)
        # Import, native invocation, verifier and stale-source test all occur
        # with cwd outside the checkout and no development path override.
        code = """
from pathlib import Path
from lambda_aitia import AitiaNativeSession, SdlcRuntime
from lambda_aitia.verification import run_pytest
root = Path('scenario').resolve()
assert SdlcRuntime().plan('qualification/job-42').lifecycle_id == 'qualification/job-42'
with AitiaNativeSession() as session:
    runtime = SdlcRuntime(session=session)
    assert runtime.plan('qualification/job-42/first').lifecycle_id == 'qualification/job-42/first'
    assert runtime.plan('qualification/job-42/second').lifecycle_id == 'qualification/job-42/second'
assert session.closed
selector = ('test_unique_effect.py::test_unique_effect_after_lost_ack_and_restart',)
buggy = run_pytest(Path(__import__('sys').executable), root, selector,
    environment={'AITIA_QUALIFICATION_MODE': 'buggy'})
assert buggy.status == 'failed', buggy
assert 'assert 2 == 1' in buggy.output, buggy.output
fixed = run_pytest(Path(__import__('sys').executable), root, selector,
    environment={'AITIA_QUALIFICATION_MODE': 'fixed'})
assert fixed.passed_obligation and fixed.collected == 1, fixed
assert fixed.source_current(root)
worker = root / 'worker.py'
worker.write_bytes(worker.read_bytes() + b'\\n# changed after verification\\n')
assert not fixed.source_current(root)
print('installed-wheel-qualification: buggy=reproduced fixed=passed stale=rejected')
"""
        run(str(interpreter), "-c", code, cwd=root, environment=environment)
