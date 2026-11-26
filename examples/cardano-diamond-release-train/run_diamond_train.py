#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Flagship IOHK/Bazel Diamond Release Train (4 Real JJ Repos, 4 Bare Remotes, 3 Waves).

Demonstrates RFC 0009 end-to-end with ZERO `GERBIL_LOADPATH` and ZERO downstream Gerbil build:
  A. Bazel Skyframe Early Cutoff: upstream commit changes, `interfaceDigest` unchanged -> pruned.
  B. Bazel Bzlmod / IOHK CHaP Diamond Conflict: Wave 1 peers disagree on `protocol-base` ABI ->
     fail-closed `need-human-decision` (`diamond-pin-conflict`) at `node-runner`.
  C. 3-Wave Diamond Cascading Fenced Commit + Push (`protocol-base` -> `{ledger-core, network-mux}`
     -> `node-runner`) driven by SysML v2 `workspace.sysml`, verifying `repoEvidenceLineages` and
     `git rev-parse refs/heads/reviewed` across all 4 real bare Git remotes.
"""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def clean_env(jj_bin: str) -> dict[str, str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in ("GERBIL_LOADPATH", "GERBIL_PATH", "GERBIL_HOME")
    }
    env["AITIA_JJ_BIN"] = jj_bin
    return env


def run_jj(jj_bin: str, env: dict[str, str], cwd: Path, *args: str) -> None:
    subprocess.run(
        [
            jj_bin,
            "--config",
            "user.name='Diamond Train'",
            "--config",
            "user.email='diamond@example.invalid'",
            *args,
        ],
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
    )


def init_repo(
    jj_bin: str,
    env: dict[str, str],
    repo_dir: Path,
    bare_remote: Path,
    project: str,
    key: str,
    scope: str,
    code_file: str,
) -> None:
    subprocess.run(["git", "init", "--bare", str(bare_remote)], check=True, capture_output=True)
    repo_dir.mkdir(parents=True, exist_ok=True)
    run_jj(jj_bin, env, repo_dir, "git", "init", "--colocate")
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
                                    {"identity": "RFC-9", "source": "work.org", "element": "work9"}
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
    (repo_dir / "README.org").write_text(f"* {project}\nEnglish documentation.\n", encoding="utf-8")
    (repo_dir / "work.org").write_text(
        "* Diamond RFC\n:PROPERTIES:\n:ID: work9\n:ENGINEERING_ID: RFC-9\n:END:\n",
        encoding="utf-8",
    )
    (repo_dir / code_file).write_text("// base\n", encoding="utf-8")
    run_jj(jj_bin, env, repo_dir, "describe", "-m", f"base {project}")
    run_jj(jj_bin, env, repo_dir, "bookmark", "create", "reviewed", "-r", "@")
    run_jj(jj_bin, env, repo_dir, "git", "remote", "add", "origin", str(bare_remote))
    run_jj(jj_bin, env, repo_dir, "git", "push", "--remote", "origin", "--bookmark", "reviewed")

    run_jj(jj_bin, env, repo_dir, "new", "-m", f"candidate {project}")
    (repo_dir / code_file).write_text(f"// updated {project}\n", encoding="utf-8")
    run_jj(jj_bin, env, repo_dir, "describe", "-m", f"candidate {project}")


def preview_draft(
    aitia_bin: str,
    env: dict[str, str],
    repo_dir: Path,
    identity: str,
    scope: str,
    summary: str,
) -> dict:
    cut_doc = json.loads(
        subprocess.run(
            [aitia_bin, "jj", "commit"],
            cwd=repo_dir,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    draft = {
        "context": cut_doc["review"]["context"],
        "proposal": {
            "identity": identity,
            "reference": "RFC-9",
            "type": "feat",
            "scope": scope,
            "summary": summary,
            "rationale": "IOHK/Bazel 4-repo diamond release train with early cutoff and coherence.",
            "language": "en",
            "languageSource": "README.org",
        },
        "narration": {
            "change": summary,
            "evidence": [
                {"obligation": "sdlc.change-record", "text": "JJ recorded the workspace cut."},
                {"obligation": "sdlc.config-audit", "text": "JJ audited project configuration."},
            ],
            "open": [],
        },
        "org": (
            f"* {identity} feat({scope}): {summary}\n"
            ":PROPERTIES:\n:AITIA_SUPPORT: sdlc.config-audit\n:END:\n"
            "** Change\n:PROPERTIES:\n:AITIA_SUPPORT: sdlc.change-record\n:END:\n"
        ),
    }
    prev_doc = json.loads(
        subprocess.run(
            [aitia_bin, "jj", "commit", "preview"],
            cwd=repo_dir,
            env=env,
            input=json.dumps(draft),
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    assert prev_doc["review"]["draftValid"] is True
    draft["context"] = prev_doc["review"]["context"]
    return draft


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    aitia_bin = os.environ.get("AITIA_BIN") or str(repo_root / "rust" / "target" / "debug" / "aitia")
    jj_bin = os.environ.get("AITIA_JJ_BIN") or shutil.which("jj")
    if not jj_bin:
        raise SystemExit("jj binary not found (set AITIA_JJ_BIN or put jj on PATH)")
    if not Path(aitia_bin).is_file():
        raise SystemExit(f"aitia binary not found at {aitia_bin} (set AITIA_BIN)")

    env = clean_env(jj_bin)
    specs = [
        ("protocol-base", "diamond/protocol-base", "BASE", "base", "src/protocol.rs", "Add typed protocol codecs"),
        ("ledger-core", "diamond/ledger-core", "LEDG", "ledger", "src/ledger.rs", "Validate EUTxO state rules"),
        ("network-mux", "diamond/network-mux", "NETW", "net", "src/mux.rs", "Multiplex typed mini-protocols"),
        ("node-runner", "diamond/node-runner", "NODE", "node", "src/node.rs", "Assemble consensus node binary"),
    ]
    sysml_template = Path(__file__).resolve().parent / "workspace.sysml"

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        remotes: dict[str, Path] = {}
        drafts: dict[str, dict] = {}
        for rid, proj, key, scope, code_file, summary in specs:
            repo_dir = root / rid
            remote_dir = root / "remotes" / f"{rid}.git"
            init_repo(jj_bin, env, repo_dir, remote_dir, proj, key, scope, code_file)
            remotes[rid] = remote_dir
            drafts[rid] = preview_draft(aitia_bin, env, repo_dir, f"{key}-RFC-9", scope, summary)

        ws_sysml = root / "workspace.sysml"
        shutil.copy2(sysml_template, ws_sysml)

        # Scenario A: Bazel Skyframe Early Cutoff (protocol-base commit drifted, interfaceDigest unchanged)
        cutoff_overlay = {
            "repos": [
                {"repoId": "protocol-base", "interfaceDigest": "abi:protocol-v1"},
                {
                    "repoId": "ledger-core",
                    "pinnedUpstreamCommits": {"protocol-base": "0000000000000000000000000000000000000000"},
                    "pinnedUpstreamInterfaces": {"protocol-base": "abi:protocol-v1"},
                },
                {
                    "repoId": "network-mux",
                    "pinnedUpstreamCommits": {"protocol-base": "0000000000000000000000000000000000000000"},
                    "pinnedUpstreamInterfaces": {"protocol-base": "abi:protocol-v1"},
                },
            ]
        }
        cutoff_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(cutoff_overlay),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        assert cutoff_doc["waves"] == [["protocol-base"], ["ledger-core", "network-mux"], ["node-runner"]]
        assert len(cutoff_doc["earlyCutoffs"]) == 2
        assert cutoff_doc["pinDrifts"] == []
        assert cutoff_doc["actionAuthorized"] is False

        # Scenario B: Bazel Bzlmod / IOHK CHaP Diamond Conflict (Wave 1 peers disagree on protocol-base ABI)
        conflict_overlay = {
            "repos": [
                {"repoId": "protocol-base", "interfaceDigest": "abi:protocol-v2"},
                {"repoId": "ledger-core", "pinnedUpstreamInterfaces": {"protocol-base": "abi:protocol-v2"}},
                {"repoId": "network-mux", "pinnedUpstreamInterfaces": {"protocol-base": "abi:protocol-v1"}},
            ]
        }
        conflict_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(conflict_overlay),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        assert conflict_doc["state"] == "need-human-decision"
        assert conflict_doc["escalationReason"] == "diamond-pin-conflict"
        assert conflict_doc["diamondConflicts"][0]["consumerRepo"] == "node-runner"
        assert conflict_doc["diamondConflicts"][0]["upstreamRepo"] == "protocol-base"
        assert conflict_doc["actionAuthorized"] is False

        # Scenario C: 3-Wave Diamond Cascading Fenced Commit + Push across ALL 4 Real JJ Repos!
        cascade_overlay = {
            "repos": [
                {"repoId": rid, "approvalLive": True, "draft": drafts[rid]}
                for rid, *_ in specs
            ]
        }
        exec_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "submit-decision", "--workspace", str(ws_sysml), "--execute-fenced"],
                cwd=root,
                env=env,
                input=json.dumps(cascade_overlay),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        assert exec_doc["state"] == "quiescent"
        assert exec_doc["actionAuthorized"] is False
        assert exec_doc["waves"] == [["protocol-base"], ["ledger-core", "network-mux"], ["node-runner"]]
        lineages = exec_doc["repoEvidenceLineages"]
        verified_heads: dict[str, str] = {}
        for rid, *_ in specs:
            assert lineages[rid]["missingReports"] == []
            rev = lineages[rid]["revision"]
            remote_head = subprocess.run(
                ["git", "rev-parse", "refs/heads/reviewed"],
                cwd=remotes[rid],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            assert remote_head == rev, f"{rid}: remote {remote_head} != {rev}"
            verified_heads[rid] = rev

    print(
        json.dumps(
            {
                "case": "cardano-diamond-release-train",
                "waves": exec_doc["waves"],
                "scenarioA_earlyCutoffs": len(cutoff_doc["earlyCutoffs"]),
                "scenarioB_diamondConflict": conflict_doc["escalationReason"],
                "scenarioC_finalState": exec_doc["state"],
                "verifiedRemoteHeads": verified_heads,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
