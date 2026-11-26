#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Use Case 2: First-Class SysML v2 Multi-Repo GitOps (`aitia flow run --workspace workspace.sysml`).

Creates two ephemeral JJ repositories (`upstream-core` -> `downstream-app`), copies the
authoritative `workspace.sysml` topology next to them, and executes the standalone pre-compiled
Rust `aitia` binary with ZERO `GERBIL_LOADPATH` and ZERO hand-written JSON manifest.
"""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def run_jj(jj_bin: str, cwd: Path, *args: str) -> None:
    subprocess.run(
        [
            jj_bin,
            "--config",
            "user.name='AITIA Example'",
            "--config",
            "user.email='example@example.invalid'",
            *args,
        ],
        cwd=cwd,
        check=True,
        capture_output=True,
    )


def init_repo(jj_bin: str, repo_dir: Path, project: str, key: str, scope: str, code_file: str) -> None:
    repo_dir.mkdir(parents=True, exist_ok=True)
    run_jj(jj_bin, repo_dir, "git", "init", "--colocate")
    (repo_dir / ".agents" / "aita").mkdir(parents=True, exist_ok=True)
    (repo_dir / Path(code_file).parent).mkdir(parents=True, exist_ok=True)
    (repo_dir / ".agents" / "aita" / "project.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "programs": {
                    "jj": {
                        "enable": True,
                        "settings": {
                            "project": project,
                            "profile": "lambda-aitia/sdlc",
                            "primary": "sdlc.config-audit",
                            "checks": [
                                {"requirement": "sdlc.change-record", "method": "jj.recorded-change"},
                                {"requirement": "sdlc.config-audit", "method": "jj.configuration-audit"},
                            ],
                            "naming": {
                                "projectKey": key,
                                "primaryLanguage": "en",
                                "languageSources": ["README.org"],
                                "types": ["feat"],
                                "scopes": [
                                    {
                                        "name": scope,
                                        "paths": [
                                            str(Path(code_file).parent),
                                            ".agents/aita",
                                            "README.org",
                                            "work.org",
                                        ],
                                    }
                                ],
                                "references": [
                                    {"identity": "RFC-1", "source": "work.org", "element": "work1"}
                                ],
                            },
                        },
                    }
                },
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (repo_dir / "README.org").write_text(f"* {project}\nEnglish project readme.\n", encoding="utf-8")
    (repo_dir / "work.org").write_text(
        "* Work RFC\n:PROPERTIES:\n:ID: work1\n:ENGINEERING_ID: RFC-1\n:END:\n",
        encoding="utf-8",
    )
    (repo_dir / code_file).write_text("pub fn example() {}\n", encoding="utf-8")
    run_jj(jj_bin, repo_dir, "describe", "-m", f"{project} candidate")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    aitia_bin = os.environ.get("AITIA_BIN") or str(repo_root / "rust" / "target" / "debug" / "aitia")
    jj_bin = os.environ.get("AITIA_JJ_BIN") or shutil.which("jj")
    if not jj_bin:
        raise SystemExit("jj binary not found (set AITIA_JJ_BIN or put jj on PATH)")
    if not Path(aitia_bin).is_file():
        raise SystemExit(f"aitia binary not found at {aitia_bin} (set AITIA_BIN)")

    sysml_template = Path(__file__).resolve().parent / "workspace.sysml"
    with tempfile.TemporaryDirectory() as tmp:
        ws_root = Path(tmp)
        init_repo(jj_bin, ws_root / "upstream-core", "example/upstream-core", "CORE", "core", "src/lib.rs")
        init_repo(jj_bin, ws_root / "downstream-app", "example/downstream-app", "APP", "app", "app/main.rs")
        ws_file = ws_root / "workspace.sysml"
        shutil.copy2(sysml_template, ws_file)

        # Strip all Gerbil environment variables to prove zero downstream Gerbil dependency!
        clean_env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("GERBIL_LOADPATH", "GERBIL_PATH", "GERBIL_HOME")
        }
        clean_env["AITIA_JJ_BIN"] = jj_bin
        proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_file)],
            cwd=ws_root,
            env=clean_env,
            check=True,
            capture_output=True,
            text=True,
        )
        result = json.loads(proc.stdout)
        assert result["caseId"] == "aitia/case/multi-repo-gitops"
        assert result["waves"] == [["upstream-core"], ["downstream-app"]]
        assert len(result["repos"]) == 2
        assert result["actionAuthorized"] is False
        print(
            json.dumps(
                {
                    "example": "02-sysml-multi-repo-gitops",
                    "caseId": result["caseId"],
                    "waves": result["waves"],
                    "state": result["state"],
                    "repos": [
                        {"repoId": r["repoId"], "state": r["state"], "upstreamReady": r["upstreamReady"]}
                        for r in result["repos"]
                    ],
                },
                indent=2,
            )
        )


if __name__ == "__main__":
    main()
