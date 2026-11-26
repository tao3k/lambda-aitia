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
            if rid == "protocol-base":
                (repo_dir / "include").mkdir(parents=True, exist_ok=True)
                (repo_dir / "include" / "protocol.h").write_text(
                    "/* Public ABI header v1 */\ntypedef unsigned long long slot_t;\n"
                )
                proj_path = repo_dir / ".agents" / "aita" / "project.json"
                proj_cfg = json.loads(proj_path.read_text())
                proj_cfg["programs"]["jj"]["settings"]["naming"]["scopes"][0]["paths"].append("include")
                proj_path.write_text(json.dumps(proj_cfg, indent=2))
                run_jj(jj_bin, env, repo_dir, "describe", "-m", "Add public protocol ABI header")
            remotes[rid] = remote_dir
            drafts[rid] = preview_draft(aitia_bin, env, repo_dir, f"{key}-RFC-9", scope, summary)

        ws_sysml = root / "workspace.sysml"
        shutil.copy2(sysml_template, ws_sysml)

        # Scenario A: REAL Semantic Source-File Early Cutoff (`interface.project-digest`)
        # Step A1: Observe protocol-base's real semantic SHA-256 interfaceDigest via SysML `interfacePaths`.
        probe_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml)],
                cwd=root,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        base_summary = next(r for r in probe_doc["repos"] if r["repoId"] == "protocol-base")
        real_iface_digest = base_summary["interfaceDigest"]
        assert real_iface_digest.startswith("sha256:"), real_iface_digest

        # Step A1b: Mutate ONLY comments/whitespace in `include/protocol.h` (semantic ABI unchanged!)
        # and verify semantic normalization preserves the EXACT SAME `interfaceDigest` across a new JJ cut!
        base_dir = root / "protocol-base"
        (base_dir / "include" / "protocol.h").write_text(
            "/* Public ABI header v1 — expanded doc comment */\n\n"
            "// Internal formatting change must NOT invalidate downstream repos!\n"
            "typedef   unsigned long long   slot_t;\n"
        )
        run_jj(jj_bin, env, base_dir, "describe", "-m", "Reformat protocol ABI header comments")
        drafts["protocol-base"] = preview_draft(
            aitia_bin, env, base_dir, "BASE-RFC-9", "base", "Add typed protocol codecs"
        )
        probe_after_comment = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml)],
                cwd=root,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        base_after_comment = next(r for r in probe_after_comment["repos"] if r["repoId"] == "protocol-base")
        assert base_after_comment["interfaceDigest"] == real_iface_digest, (
            f"Comment-only edit broke semantic early cutoff: "
            f"{base_after_comment['interfaceDigest']} != {real_iface_digest}"
        )

        # Step A2: Downstream peers pinned an older protocol-base commit but the SAME real SHA-256 ABI -> Early Cutoff!
        cutoff_overlay = {
            "repos": [
                {
                    "repoId": "ledger-core",
                    "pinnedUpstreamCommits": {"protocol-base": "0000000000000000000000000000000000000000"},
                    "pinnedUpstreamInterfaces": {"protocol-base": real_iface_digest},
                },
                {
                    "repoId": "network-mux",
                    "pinnedUpstreamCommits": {"protocol-base": "0000000000000000000000000000000000000000"},
                    "pinnedUpstreamInterfaces": {"protocol-base": real_iface_digest},
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
        assert cutoff_doc["earlyCutoffs"][0]["interfaceDigest"] == real_iface_digest
        assert cutoff_doc["pinDrifts"] == []
        assert cutoff_doc["actionAuthorized"] is False

        # Scenario B1: Stale ABI digest triggers `need-agent-synthesis` with structured `agentHandoff` envelope
        drift_overlay = {
            "repos": [
                {"repoId": "ledger-core", "pinnedUpstreamInterfaces": {"protocol-base": "sha256:stale-abi"}},
                {"repoId": "network-mux", "pinnedUpstreamInterfaces": {"protocol-base": "sha256:stale-abi"}},
            ]
        }
        drift_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(drift_overlay),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        assert drift_doc["state"] == "need-agent-synthesis"
        assert drift_doc["escalationReason"] == "cross-repo-pin-drift"
        assert drift_doc["agentHandoff"]["schema"] == "lambda-aitia.agent-synthesis-handoff.v1"
        assert drift_doc["agentHandoff"]["actionAuthorized"] is False
        assert "execute-fenced-effect" in drift_doc["agentHandoff"]["forbiddenActions"]

        # Scenario B2: Bazel Bzlmod / IOHK CHaP Diamond Conflict (Wave 1 peers disagree on protocol-base ABI)
        conflict_overlay = {
            "repos": [
                {"repoId": "ledger-core", "pinnedUpstreamInterfaces": {"protocol-base": real_iface_digest}},
                {"repoId": "network-mux", "pinnedUpstreamInterfaces": {"protocol-base": "sha256:stale-abi"}},
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

        # Scenario C: 3-Wave Cascading Fenced Commit + Push + Durable Crash-Recovery Checkpoint Ledger!
        checkpoint_file = root / "diamond-train.checkpoint.json"
        cascade_overlay = {
            "checkpointPath": str(checkpoint_file),
            "repos": [
                {"repoId": rid, "approvalLive": True, "draft": drafts[rid]}
                for rid, *_ in specs
            ],
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
        assert exec_doc["checkpoint"]["persistedReceiptCount"] > 0
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

        # Crash-recovery idempotent resume: re-running against the persisted checkpoint skips already-applied waves
        resume_doc = json.loads(
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
        assert resume_doc["state"] == "quiescent"
        assert resume_doc["checkpoint"]["resumedReceiptCount"] == exec_doc["checkpoint"]["persistedReceiptCount"]

        # Scenario D: Mid-Wave Partial Failure -> Wave Barrier Enforcement (Saga partial checkpoint)
        # Simulate Wave 0 (`protocol-base`) + Wave 1 peer A (`ledger-core`) succeeded, while Wave 1
        # peer B (`network-mux`) failed before apply/push: Wave 2 (`node-runner`) MUST stay blocked!
        full_cp = json.loads(checkpoint_file.read_text())
        partial_receipts = {
            k: v
            for k, v in full_cp["completedReceipts"].items()
            if not (
                k.startswith("repo:network-mux:gitops.jj.apply-description")
                or k.startswith("repo:network-mux:gitops.jj.push-reviewed")
                or k.startswith("repo:node-runner:gitops.jj.apply-description")
                or k.startswith("repo:node-runner:gitops.jj.push-reviewed")
            )
        }
        partial_cp_file = root / "partial-midwave.checkpoint.json"
        partial_cp_file.write_text(
            json.dumps(
                {
                    "schema": "lambda-aitia.multi-repo-checkpoint.v1",
                    "lastState": "need-fenced-frames",
                    "completedReceipts": partial_receipts,
                    "appliedDecisions": [],
                    "actionAuthorized": False,
                },
                indent=2,
            )
        )
        midwave_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "checkpointPath": str(partial_cp_file),
                        "repos": [
                            {"repoId": rid, "approvalLive": True, "draft": drafts[rid]}
                            for rid, *_ in specs
                        ],
                    }
                ),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        repo_states = {r["repoId"]: r["state"] for r in midwave_doc["repos"]}
        assert repo_states["protocol-base"] == "quiescent", repo_states
        assert repo_states["ledger-core"] == "quiescent", repo_states
        assert repo_states["node-runner"] == "blocked-on-upstream", repo_states
        assert midwave_doc["actionAuthorized"] is False

    print(
        json.dumps(
            {
                "case": "cardano-diamond-release-train",
                "waves": exec_doc["waves"],
                "realInterfaceDigest": real_iface_digest,
                "semanticCommentCutoffPreserved": True,
                "scenarioA_earlyCutoffs": len(cutoff_doc["earlyCutoffs"]),
                "scenarioB1_agentHandoff": drift_doc["agentHandoff"]["schema"],
                "scenarioB2_diamondConflict": conflict_doc["escalationReason"],
                "scenarioC_finalState": exec_doc["state"],
                "scenarioC_resumedReceipts": resume_doc["checkpoint"]["resumedReceiptCount"],
                "scenarioD_midWaveNodeState": repo_states["node-runner"],
                "verifiedRemoteHeads": verified_heads,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
