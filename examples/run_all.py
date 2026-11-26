#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Execute all Lambda Aitia Use-Case examples in isolated processes with zero GERBIL_LOADPATH."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

EXAMPLES = [
    "01-sdlc-profiles/run_profiles.py",
    "02-sysml-multi-repo-gitops/run_workspace_demo.py",
    "03-python-leaf-pytest-capability/run_leaf_pytest.py",
    "04-agent-repair-loop/run_agent_loop.py",
    "05-c-abi-inprocess/run_c_abi.py",
]


def main() -> None:
    examples_dir = Path(__file__).resolve().parent
    repo_root = examples_dir.parent
    clean_env = {
        k: v
        for k, v in os.environ.items()
        if k not in ("GERBIL_LOADPATH", "GERBIL_PATH", "GERBIL_HOME")
    }

    with tempfile.TemporaryDirectory() as py_stage:
        cdylib = clean_env.get("AITIA_CDYLIB")
        if not cdylib:
            for name in ("liblambda_aitia_rust.dylib", "liblambda_aitia_rust.so"):
                candidate = repo_root / "rust" / "target" / "debug" / name
                if candidate.is_file():
                    cdylib = str(candidate)
                    clean_env["AITIA_CDYLIB"] = cdylib
                    break
        if cdylib and Path(cdylib).is_file():
            so_link = Path(py_stage) / "lambda_aitia_rust.so"
            so_link.symlink_to(Path(cdylib).resolve())
            existing = clean_env.get("PYTHONPATH", "")
            clean_env["PYTHONPATH"] = f"{py_stage}:{existing}" if existing else py_stage

        for rel in EXAMPLES:
            script = examples_dir / rel
            print(f"=== Running {rel} ===", flush=True)
            subprocess.run([sys.executable, str(script)], env=clean_env, check=True)

    print("AITIA-EXAMPLES-ALL-OK")


if __name__ == "__main__":
    main()
