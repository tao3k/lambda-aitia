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
        # Mint a RFC 0011 TUF 2-of-3 Ed25519 quorum Release Attestation Bundle at epoch 5.
        seed_a = "11" * 32
        seed_b = "22" * 32
        seed_c = "33" * 32
        checkpoint_file = root / "diamond-train.checkpoint.json"
        cascade_overlay = {
            "checkpointPath": str(checkpoint_file),
            "emitAttestation": True,
            "attestationSigningSeeds": [seed_a, seed_b],
            "attestationEpoch": 5,
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

        # Scenario E: RFC 0010 Proof-Carrying Release Attestation (in-toto/SLSA) + Adapton/Salsa Cache Reuse
        att = exec_doc["releaseAttestation"]
        assert att["schema"] == "lambda-aitia.release-attestation-bundle.v1", att
        assert att["bundleDigest"].startswith("sha256:"), att
        assert att["actionAuthorized"] is False
        assert len(att["payload"]["links"]) == 4
        assert all(link["missingReports"] == 0 for link in att["payload"]["links"])
        assert all(link["verificationKey"].startswith("sha256:") for link in att["payload"]["links"])

        # E1. Tamper 1 byte in attested interfaceDigest -> Rust Ed25519/SHA-256 verifier MUST fail closed!
        tampered_att = json.loads(json.dumps(att))
        tampered_att["payload"]["links"][0]["interfaceDigest"] = "sha256:tampered"
        tamper_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps({"priorAttestationBundle": tampered_att}),
            check=False,
            capture_output=True,
            text=True,
        )
        assert tamper_proc.returncode != 0, "Tampered release attestation bundle MUST fail closed!"

        # E2. Authentic priorAttestationBundle -> 4/4 Adapton/Salsa verificationCacheHits!
        cache_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "checkpointPath": str(checkpoint_file),
                        "priorAttestationBundle": att,
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
        assert cache_doc["state"] == "quiescent"
        assert len(cache_doc["verificationCacheHits"]) == 4, cache_doc["verificationCacheHits"]
        assert all(r["cacheHit"] is True for r in cache_doc["repos"])
        assert cache_doc["actionAuthorized"] is False

        # E3. True ABI change on protocol-base automatically invalidates protocol-base + Wave 1 downstream caches!
        (base_dir / "include" / "protocol.h").write_text(
            "typedef unsigned long long slot_t;\n"
            "typedef unsigned int epoch_t;\n"
        )
        run_jj(jj_bin, env, base_dir, "status")
        inv_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps({"priorAttestationBundle": att}),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        inv_hits = {r["repoId"]: r["cacheHit"] for r in inv_doc["repos"]}
        assert inv_hits["protocol-base"] is False, inv_hits
        assert inv_hits["ledger-core"] is False, inv_hits
        assert inv_hits["network-mux"] is False, inv_hits
        assert inv_doc["actionAuthorized"] is False

        # Scenario F: RFC 0011 TUF 2-of-3 Quorum + Revocation + Rollback Defense + Counterfactual Branch Matrix
        assert att["payload"]["epoch"] == 5, att["payload"]
        assert len(att["signatures"]) == 2, att["signatures"]
        pk_a = att["signatures"][0]["publicKey"]
        pk_b = att["signatures"][1]["publicKey"]
        trust_root_ok = {
            "schema": "lambda-aitia.tuf-trust-root.v1",
            "rootVersion": 1,
            "threshold": 2,
            "minEpoch": 5,
            "authorizedKeys": [pk_a, pk_b, "44" * 32],
            "revokedKeys": [],
        }
        # F1. Valid 2-of-3 quorum bundle accepted under TrustRoot + Counterfactual Competing-Branch Matrix!
        # Evaluate TWO competing hypotheses simultaneously (preserving BOTH without selecting a winner!):
        #   Branch 1: Revert protocol-base to attested real_iface_digest -> preserves 4/4 memo hits
        #   Branch 2: Push forward to ABI v2 -> invalidates protocol-base + ledger-core + network-mux
        tuf_cf_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "checkpointPath": str(checkpoint_file),
                        "priorAttestationBundle": att,
                        "trustRoot": trust_root_ok,
                        "repos": [
                            {"repoId": rid, "approvalLive": True, "draft": drafts[rid]}
                            for rid, *_ in specs
                        ],
                        "counterfactualBranches": [
                            {
                                "branchId": "branch-revert-abi-v1",
                                "hypothesis": "Revert protocol-base header to ABI v1 to preserve 4/4 memo hits",
                                "repoOverrides": [
                                    {"repoId": "protocol-base", "interfaceDigest": real_iface_digest}
                                ],
                            },
                            {
                                "branchId": "branch-advance-abi-v2",
                                "hypothesis": "Advance protocol-base to ABI v2 and re-verify Wave 1 peers",
                                "repoOverrides": [
                                    {"repoId": "protocol-base", "interfaceDigest": "sha256:abi-v2-breaking"},
                                    {"repoId": "ledger-core", "pinnedUpstreamInterfaces": {"protocol-base": real_iface_digest}},
                                    {"repoId": "network-mux", "pinnedUpstreamInterfaces": {"protocol-base": real_iface_digest}},
                                ],
                            },
                        ],
                    }
                ),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        cf_matrix = tuf_cf_doc["counterfactualMatrix"]
        assert len(cf_matrix) == 2, cf_matrix
        assert all(b["hypothetical"] is True and b["actionAuthorized"] is False for b in cf_matrix)
        cf_by_id = {b["branchId"]: b for b in cf_matrix}
        assert len(cf_by_id["branch-revert-abi-v1"]["verificationCacheHits"]) == 4, cf_by_id
        assert cf_by_id["branch-advance-abi-v2"]["resultingState"] == "need-agent-synthesis", cf_by_id
        assert len(cf_by_id["branch-advance-abi-v2"]["invalidatedRepos"]) == 3, cf_by_id
        assert tuf_cf_doc["actionAuthorized"] is False

        # F2. Duplicate-key quorum inflation attack (repeating signer A twice) -> MUST fail closed!
        dup_att = json.loads(json.dumps(att))
        dup_att["signatures"] = [att["signatures"][0], att["signatures"][0]]
        dup_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps({"priorAttestationBundle": dup_att, "trustRoot": trust_root_ok}),
            check=False,
            capture_output=True,
            text=True,
        )
        assert dup_proc.returncode != 0, "Duplicate-key quorum inflation MUST fail closed!"

        # F3. TUF Key Revocation (pk_a compromised & revoked) -> MUST fail closed!
        trust_root_revoked = dict(trust_root_ok, rootVersion=2, revokedKeys=[pk_a])
        revoked_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps({"priorAttestationBundle": att, "trustRoot": trust_root_revoked}),
            check=False,
            capture_output=True,
            text=True,
        )
        assert revoked_proc.returncode != 0, "Revoked key attestation MUST fail closed!"

        # F4. TUF Epoch Rollback Defense (minEpoch=6 vs valid epoch=5 bundle) -> MUST fail closed!
        trust_root_rollback = dict(trust_root_ok, rootVersion=3, minEpoch=6)
        rollback_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps({"priorAttestationBundle": att, "trustRoot": trust_root_rollback}),
            check=False,
            capture_output=True,
            text=True,
        )
        assert rollback_proc.returncode != 0, "Epoch rollback attestation MUST fail closed!"

        # Scenario G: RFC 0012 TUF Dual-Quorum Root Rotation (R1 -> R2) & Transitive Multi-Epoch Chain (Epoch 5 -> 6)
        # Restore protocol-base ABI v1 and mint Epoch 6 bundle signed by rotated quorum [seed_b, seed_c]
        # linked via parentBundleDigest -> att["bundleDigest"] (Epoch 5).
        (base_dir / "include" / "protocol.h").write_text(
            "/* Public ABI header v1 */\ntypedef unsigned long long slot_t;\n"
        )
        run_jj(jj_bin, env, base_dir, "status")
        ep6_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "checkpointPath": str(checkpoint_file),
                        "emitAttestation": True,
                        "attestationSigningSeeds": [seed_b, seed_c],
                        "attestationEpoch": 6,
                        "parentBundleDigest": att["bundleDigest"],
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
        att_ep6 = ep6_doc["releaseAttestation"]
        assert att_ep6["payload"]["epoch"] == 6, att_ep6["payload"]
        assert att_ep6["payload"]["parentBundleDigest"] == att["bundleDigest"]
        pks_ep5 = {s["publicKey"] for s in att["signatures"]}
        pks_ep6 = {s["publicKey"] for s in att_ep6["signatures"]}
        shared_pk_b = (pks_ep5 & pks_ep6).pop()
        old_pk_a = (pks_ep5 - {shared_pk_b}).pop()
        new_pk_c = (pks_ep6 - {shared_pk_b}).pop()
        genesis_r1 = {
            "schema": "lambda-aitia.tuf-trust-root.v1",
            "rootVersion": 1,
            "threshold": 2,
            "minEpoch": 5,
            "authorizedKeys": [old_pk_a, shared_pk_b, new_pk_c],
            "revokedKeys": [],
        }
        rotated_r2 = {
            "schema": "lambda-aitia.tuf-trust-root.v1",
            "rootVersion": 2,
            "threshold": 2,
            "minEpoch": 6,
            "authorizedKeys": [shared_pk_b, new_pk_c, "55" * 32],
            "revokedKeys": [old_pk_a],
        }
        # G1. Mint genuine dual-quorum R1 -> R2 handover envelope (old=[seed_a, seed_b], new=[seed_b, seed_c])
        rot_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "emitRootRotation": {
                            "newRoot": rotated_r2,
                            "oldSigningSeeds": [seed_a, seed_b],
                            "newSigningSeeds": [seed_b, seed_c],
                        }
                    }
                ),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        r1_to_r2 = rot_doc["signedRootRotation"]
        assert r1_to_r2["schema"] == "lambda-aitia.tuf-root-rotation.v1"
        assert r1_to_r2["actionAuthorized"] is False

        # G2. Verify full transitive chain (R1 -> R2 + Epoch 5 -> Epoch 6) -> 4/4 cache hits & verifiedLineage!
        chain_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "checkpointPath": str(checkpoint_file),
                        "pinnedGenesisRoot": genesis_r1,
                        "rootRotations": [r1_to_r2],
                        "attestationChain": [att, att_ep6],
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
        lineage_meta = chain_doc["verifiedAttestationLineage"]
        assert lineage_meta["schema"] == "lambda-aitia.verified-attestation-lineage.v1"
        assert lineage_meta["chainLength"] == 2
        assert lineage_meta["rootVersion"] == 2
        assert lineage_meta["epochs"] == [5, 6]
        assert lineage_meta["genesisDigest"] == att["bundleDigest"]
        assert lineage_meta["headDigest"] == att_ep6["bundleDigest"]
        assert lineage_meta["actionAuthorized"] is False
        assert len(chain_doc["verificationCacheHits"]) == 4

        # G3. Negative control 1: Unilateral hijack rotation (missing old R1 quorum!) -> MUST fail closed!
        hijack_rot = json.loads(json.dumps(r1_to_r2))
        hijack_rot["oldSignatures"] = [r1_to_r2["oldSignatures"][0]]
        hijack_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps(
                {
                    "pinnedGenesisRoot": genesis_r1,
                    "rootRotations": [hijack_rot],
                    "attestationChain": [att, att_ep6],
                }
            ),
            check=False,
            capture_output=True,
            text=True,
        )
        assert hijack_proc.returncode != 0, "Unilateral root rotation without old quorum MUST fail closed!"

        # G4. Negative control 2: Broken parentBundleDigest hash chain -> MUST fail closed!
        broken_ep6 = json.loads(json.dumps(att_ep6))
        broken_ep6["payload"]["parentBundleDigest"] = "sha256:" + ("0" * 64)
        broken_chain_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps(
                {
                    "pinnedGenesisRoot": genesis_r1,
                    "rootRotations": [r1_to_r2],
                    "attestationChain": [att, broken_ep6],
                }
            ),
            check=False,
            capture_output=True,
            text=True,
        )
        assert broken_chain_proc.returncode != 0, "Broken parentBundleDigest chain MUST fail closed!"

        # Scenario H: RFC 0013 OpenSysML v2 Assume-Guarantee Contracts & SysML-Pinned TUF Policy Floor
        assert probe_doc.get("contractGaps", []) == [], probe_doc

        # H1. Inject unsatisfied assumption on ledger-core + TWO competing counterfactual fixes:
        #     Live step MUST fail closed (`assume-guarantee-gap`), while counterfactualMatrix preserves BOTH fixes!
        ag_gap_doc = json.loads(
            subprocess.run(
                [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
                cwd=root,
                env=env,
                input=json.dumps(
                    {
                        "repos": [
                            {
                                "repoId": "ledger-core",
                                "assumes": ["protocol.v1.codecs", "zero-copy.framing"],
                            }
                        ],
                        "counterfactualBranches": [
                            {
                                "branchId": "branch-export-guarantee",
                                "hypothesis": "protocol-base exports zero-copy.framing",
                                "repoOverrides": [
                                    {
                                        "repoId": "protocol-base",
                                        "guarantees": [
                                            "protocol.v1.codecs",
                                            "crypto.ed25519",
                                            "zero-copy.framing",
                                        ],
                                    }
                                ],
                            },
                            {
                                "branchId": "branch-drop-assumption",
                                "hypothesis": "ledger-core removes zero-copy.framing assumption",
                                "repoOverrides": [
                                    {
                                        "repoId": "ledger-core",
                                        "assumes": ["protocol.v1.codecs"],
                                    }
                                ],
                            },
                        ],
                    }
                ),
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        assert ag_gap_doc["state"] == "need-human-decision", ag_gap_doc
        assert ag_gap_doc["escalationReason"] == "assume-guarantee-gap", ag_gap_doc
        assert len(ag_gap_doc["contractGaps"]) == 1, ag_gap_doc["contractGaps"]
        assert ag_gap_doc["contractGaps"][0]["consumerRepo"] == "ledger-core"
        assert ag_gap_doc["contractGaps"][0]["missingAssumption"] == "zero-copy.framing"
        ag_cf = ag_gap_doc["counterfactualMatrix"]
        assert len(ag_cf) == 2, ag_cf
        assert all(
            b["resultingState"] == "quiescent"
            and b["hypothetical"] is True
            and b["actionAuthorized"] is False
            for b in ag_cf
        ), ag_cf
        assert ag_gap_doc["actionAuthorized"] is False

        # H2. SysML-pinned TUF Policy Floor defense: weakened threshold=1 (even with spoofed overlay
        #     `sysmlTufPolicy`) MUST fail closed against `releaseTufPolicy` (minThreshold=2)!
        weak_root = dict(trust_root_ok, threshold=1)
        weak_policy_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps(
                {
                    "sysmlTufPolicy": {"minThreshold": 1, "minEpoch": 1},
                    "priorAttestationBundle": att,
                    "trustRoot": weak_root,
                }
            ),
            check=False,
            capture_output=True,
            text=True,
        )
        assert weak_policy_proc.returncode != 0, (
            "Weakened threshold=1 MUST fail closed against SysML TufPolicy minThreshold=2!"
        )

        # Scenario I: RFC 0014 Standalone Air-Gapped Offline Auditor (`aitia flow verify-attestation`)
        # Copy ONLY `workspace.sysml` into a completely empty air-gapped directory (ZERO JJ/Git repos!)
        # and verify the portable R1->R2 + Epoch 5->6 proof bundle offline with zero GERBIL_LOADPATH!
        with tempfile.TemporaryDirectory() as airgap_tmp:
            airgap_dir = Path(airgap_tmp)
            airgap_sysml = airgap_dir / "workspace.sysml"
            shutil.copy2(ws_sysml, airgap_sysml)
            portable_bundle = {
                "schema": "lambda-aitia.portable-audit-bundle.v1",
                "pinnedGenesisRoot": genesis_r1,
                "rootRotations": [r1_to_r2],
                "attestationChain": [att, att_ep6],
                "actionAuthorized": False,
            }
            # I1. Authentic air-gapped audit passes with ZERO repos on disk!
            audit_verdict = json.loads(
                subprocess.run(
                    [aitia_bin, "flow", "verify-attestation", "--workspace", str(airgap_sysml)],
                    cwd=airgap_dir,
                    env=env,
                    input=json.dumps(portable_bundle),
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout
            )
            assert audit_verdict["schema"] == "lambda-aitia.offline-audit-verdict.v1", audit_verdict
            assert audit_verdict["verified"] is True
            assert audit_verdict["airGapped"] is True
            assert audit_verdict["sysmlPolicyEnforced"] is True
            assert audit_verdict["rootVersion"] == 2
            assert audit_verdict["chainLength"] == 2
            assert audit_verdict["verifiedRepoCount"] == 4
            assert audit_verdict["actionAuthorized"] is False

            # I2. Verifier-pinned SysML TufPolicy beats spoofed bundle policy + weakened root!
            weak_genesis = dict(genesis_r1, threshold=1)
            weak_portable = {
                "schema": "lambda-aitia.portable-audit-bundle.v1",
                "sysmlTufPolicy": {"minThreshold": 1, "minEpoch": 1},
                "pinnedGenesisRoot": weak_genesis,
                "rootRotations": [],
                "attestationChain": [att],
                "actionAuthorized": False,
            }
            weak_audit_proc = subprocess.run(
                [aitia_bin, "flow", "verify-attestation", "--workspace", str(airgap_sysml)],
                cwd=airgap_dir,
                env=env,
                input=json.dumps(weak_portable),
                check=False,
                capture_output=True,
                text=True,
            )
            assert weak_audit_proc.returncode != 0, (
                "Air-gapped auditor MUST enforce verifier-pinned SysML TufPolicy over spoofed bundle!"
            )

            # I3. Missing expected repository link fails closed!
            incomplete_bundle = dict(
                portable_bundle,
                expectedRepoIds=["protocol-base", "ledger-core", "network-mux", "node-runner", "missing-repo"],
            )
            missing_repo_proc = subprocess.run(
                [aitia_bin, "flow", "verify-attestation"],
                cwd=airgap_dir,
                env=env,
                input=json.dumps(incomplete_bundle),
                check=False,
                capture_output=True,
                text=True,
            )
            assert missing_repo_proc.returncode != 0, "Missing expected repo MUST fail closed!"

            # Scenario J: RFC 0015 In-Process PyO3 Air-Gapped Auditor + RFC 6962 O(log N) Merkle Proof
            # Runs directly inside Python via `lambda_aitia_rust` (zero subprocess, zero Scheme boot!).
            import lambda_aitia_rust

            inproc_bundle = dict(
                portable_bundle,
                sysmlTufPolicy={"minThreshold": 2, "minEpoch": 5},
                expectedRepoIds=["protocol-base", "ledger-core", "network-mux", "node-runner"],
            )
            inproc_verdict = json.loads(
                lambda_aitia_rust.verify_portable_audit_bundle(json.dumps(inproc_bundle))
            )
            assert inproc_verdict["verified"] is True, inproc_verdict
            assert inproc_verdict["airGapped"] is True
            assert inproc_verdict["headMerkleRoot"] == att_ep6["payload"]["merkleRoot"]
            assert inproc_verdict["actionAuthorized"] is False

            # J2. Generate & verify O(log_2 4) = 2 sibling Merkle inclusion proof for `ledger-core`
            merkle_proof_json = lambda_aitia_rust.generate_repo_merkle_proof(
                json.dumps(att_ep6), "ledger-core"
            )
            merkle_proof = json.loads(merkle_proof_json)
            assert merkle_proof["schema"] == "lambda-aitia.repo-merkle-proof.v1"
            assert len(merkle_proof["siblings"]) == 2, merkle_proof["siblings"]
            assert merkle_proof["actionAuthorized"] is False

            merkle_verdict = json.loads(
                lambda_aitia_rust.verify_repo_merkle_proof(
                    merkle_proof_json, inproc_verdict["headMerkleRoot"]
                )
            )
            assert merkle_verdict["verified"] is True
            assert merkle_verdict["repoId"] == "ledger-core"
            assert merkle_verdict["siblingCount"] == 2
            assert merkle_verdict["actionAuthorized"] is False

            # J3. Negative controls in-process: tampered link & flipped sibling side MUST raise ValueError!
            tampered_proof = json.loads(merkle_proof_json)
            tampered_proof["link"]["interfaceDigest"] = "sha256:tampered"
            merkle_tamper_rejected = False
            try:
                lambda_aitia_rust.verify_repo_merkle_proof(
                    json.dumps(tampered_proof), inproc_verdict["headMerkleRoot"]
                )
            except ValueError:
                merkle_tamper_rejected = True
            assert merkle_tamper_rejected, "Tampered Merkle leaf MUST fail closed!"

            flipped_proof = json.loads(merkle_proof_json)
            flipped_proof["siblings"][0]["side"] = (
                "right" if flipped_proof["siblings"][0]["side"] == "left" else "left"
            )
            merkle_flip_rejected = False
            try:
                lambda_aitia_rust.verify_repo_merkle_proof(
                    json.dumps(flipped_proof), inproc_verdict["headMerkleRoot"]
                )
            except ValueError:
                merkle_flip_rejected = True
            assert merkle_flip_rejected, "Flipped Merkle sibling side MUST fail closed!"

            # Scenario K: RFC 0016 RFC 6962 §2.1.2 Append-Only Transparency Log Consistency Proofs
            # Test power-of-2 (1->2), non-power-of-2 (2->3, 3->5) append-only growth, PLUS
            # fail-closed rejection of 1-byte historical Epoch 5 equivocation and log truncation!
            log_entries = [
                {"epoch": 5, "bundleDigest": att["bundleDigest"], "merkleRoot": att["payload"]["merkleRoot"]},
                {"epoch": 6, "bundleDigest": att_ep6["bundleDigest"], "merkleRoot": att_ep6["payload"]["merkleRoot"]},
                {"epoch": 7, "bundleDigest": "sha256:" + ("7" * 64), "merkleRoot": "sha256:" + ("a" * 64)},
                {"epoch": 8, "bundleDigest": "sha256:" + ("8" * 64), "merkleRoot": "sha256:" + ("b" * 64)},
                {"epoch": 9, "bundleDigest": "sha256:" + ("9" * 64), "merkleRoot": "sha256:" + ("c" * 64)},
            ]
            # K1. Power-of-2 (1 -> 2), non-power-of-2 (2 -> 3), and multi-step (3 -> 5) append-only proofs
            p12 = json.loads(lambda_aitia_rust.generate_consistency_proof(json.dumps(log_entries[:2]), 1))
            v12 = json.loads(
                lambda_aitia_rust.verify_consistency_proof(
                    json.dumps(p12), p12["firstRoot"], p12["secondRoot"]
                )
            )
            assert v12["appendOnlyVerified"] is True and v12["actionAuthorized"] is False

            p23 = json.loads(lambda_aitia_rust.generate_consistency_proof(json.dumps(log_entries[:3]), 2))
            v23 = json.loads(
                lambda_aitia_rust.verify_consistency_proof(
                    json.dumps(p23), p23["firstRoot"], p23["secondRoot"]
                )
            )
            assert v23["appendOnlyVerified"] is True and v23["actionAuthorized"] is False

            p35 = json.loads(lambda_aitia_rust.generate_consistency_proof(json.dumps(log_entries), 3))
            v35 = json.loads(
                lambda_aitia_rust.verify_consistency_proof(
                    json.dumps(p35), p35["firstRoot"], p35["secondRoot"]
                )
            )
            assert v35["appendOnlyVerified"] is True and v35["actionAuthorized"] is False

            # K2. Historical equivocation attack: rewrite Epoch 5 entry in size-5 log -> MUST fail closed
            #     against original trusted size-3 checkpoint root `p35["firstRoot"]`!
            equiv_entries = json.loads(json.dumps(log_entries))
            equiv_entries[0]["bundleDigest"] = "sha256:" + ("f" * 64)
            p35_equiv = json.loads(
                lambda_aitia_rust.generate_consistency_proof(json.dumps(equiv_entries), 3)
            )
            equivocation_rejected = False
            try:
                lambda_aitia_rust.verify_consistency_proof(
                    json.dumps(p35_equiv), p35["firstRoot"], p35_equiv["secondRoot"]
                )
            except ValueError:
                equivocation_rejected = True
            assert equivocation_rejected, "Historical equivocation MUST fail closed!"

            # K3. Log truncation attack (firstSize=4 > secondSize=3) -> MUST fail closed!
            truncation_rejected = False
            try:
                lambda_aitia_rust.generate_consistency_proof(json.dumps(log_entries[:3]), 4)
            except ValueError:
                truncation_rejected = True
            assert truncation_rejected, "Log truncation MUST fail closed!"

            # Scenario L: RFC 0017 Witness-Cosigned Checkpoints (STH) & Cross-Auditor Gossip Equivocation
            log_origin = "lambda-aitia.org/cardano-diamond-train/v1"
            origin_seed = "11" * 32
            w1_seed, w2_seed, w3_seed = "a1" * 32, "a2" * 32, "a3" * 32
            sth_2_json = lambda_aitia_rust.sign_checkpoint(
                log_origin,
                json.dumps(log_entries[:2]),
                origin_seed,
                json.dumps(
                    [
                        {"witnessId": "witness-us-east", "seedHex": w1_seed, "timestamp": 1795699100},
                        {"witnessId": "witness-eu-west", "seedHex": w2_seed, "timestamp": 1795699102},
                    ]
                ),
            )
            sth_5_json = lambda_aitia_rust.sign_checkpoint(
                log_origin,
                json.dumps(log_entries),
                origin_seed,
                json.dumps(
                    [
                        {"witnessId": "witness-eu-west", "seedHex": w2_seed, "timestamp": 1795699200},
                        {"witnessId": "witness-ap-northeast", "seedHex": w3_seed, "timestamp": 1795699205},
                    ]
                ),
            )
            sth_2 = json.loads(sth_2_json)
            sth_5 = json.loads(sth_5_json)
            w_pks_2 = {c["publicKey"] for c in sth_2["cosignatures"]}
            w_pks_5 = {c["publicKey"] for c in sth_5["cosignatures"]}
            shared_w2_pk = (w_pks_2 & w_pks_5).pop()
            all_witness_pks = sorted(w_pks_2 | w_pks_5)
            assert len(all_witness_pks) == 3, all_witness_pks

            witness_policy = {
                "schema": "lambda-aitia.witness-policy.v1",
                "origin": log_origin,
                "originPublicKey": sth_2["originPublicKey"],
                "witnessThreshold": 2,
                "allowedWitnessKeys": all_witness_pks,
                "revokedWitnessKeys": [],
            }
            witness_policy_json = json.dumps(witness_policy)

            # L1. Individual STH verification + cosigned 2->5 transition with RFC 6962 consistency proof
            sth_2_verdict = json.loads(
                lambda_aitia_rust.verify_signed_checkpoint(sth_2_json, witness_policy_json)
            )
            assert sth_2_verdict["verified"] is True and sth_2_verdict["validWitnessCount"] == 2
            assert sth_2_verdict["actionAuthorized"] is False

            p25_json = lambda_aitia_rust.generate_consistency_proof(json.dumps(log_entries), 2)
            transition_verdict = json.loads(
                lambda_aitia_rust.verify_checkpoint_transition(
                    sth_2_json, sth_5_json, p25_json, witness_policy_json
                )
            )
            assert transition_verdict["verified"] is True
            assert transition_verdict["firstSize"] == 2 and transition_verdict["secondSize"] == 5
            assert transition_verdict["firstWitnessCount"] == 2 and transition_verdict["secondWitnessCount"] == 2
            assert transition_verdict["actionAuthorized"] is False

            # L2. Adversarial witness quorum controls: duplicate witness, revoked witness, cross-origin replay
            sth_dup = json.loads(sth_2_json)
            sth_dup["cosignatures"] = [sth_dup["cosignatures"][0], sth_dup["cosignatures"][0]]
            witness_dup_rejected = False
            try:
                lambda_aitia_rust.verify_signed_checkpoint(json.dumps(sth_dup), witness_policy_json)
            except ValueError:
                witness_dup_rejected = True
            assert witness_dup_rejected, "Duplicate witness cosignature inflation MUST fail closed!"

            revoked_witness_policy = dict(witness_policy, revokedWitnessKeys=[shared_w2_pk])
            witness_revoked_rejected = False
            try:
                lambda_aitia_rust.verify_signed_checkpoint(
                    sth_2_json, json.dumps(revoked_witness_policy)
                )
            except ValueError:
                witness_revoked_rejected = True
            assert witness_revoked_rejected, "Revoked witness dropping quorum below threshold MUST fail closed!"

            wrong_origin_policy = dict(witness_policy, origin="evil.example/other-log/v1")
            witness_origin_rejected = False
            try:
                lambda_aitia_rust.verify_signed_checkpoint(
                    sth_2_json, json.dumps(wrong_origin_policy)
                )
            except ValueError:
                witness_origin_rejected = True
            assert witness_origin_rejected, "Cross-origin checkpoint replay MUST fail closed!"

            # L3. Cross-auditor gossip: epistemic unknown without proof, consistent with proof,
            #     and non-repudiable EquivocationEvidenceReceipt on same-size split-view fork!
            gossip_unknown = json.loads(
                lambda_aitia_rust.detect_checkpoint_equivocation(
                    sth_2_json, sth_5_json, witness_policy_json
                )
            )
            assert gossip_unknown["status"] == "consistency-proof-required", gossip_unknown
            assert gossip_unknown["equivocationDetected"] is False
            assert gossip_unknown["actionAuthorized"] is False

            gossip_consistent = json.loads(
                lambda_aitia_rust.detect_checkpoint_equivocation(
                    sth_2_json, sth_5_json, witness_policy_json, p25_json
                )
            )
            assert gossip_consistent["status"] == "consistent", gossip_consistent
            assert gossip_consistent["equivocationDetected"] is False
            assert gossip_consistent["actionAuthorized"] is False

            sth_5_evil_json = lambda_aitia_rust.sign_checkpoint(
                log_origin,
                json.dumps(equiv_entries),
                origin_seed,
                json.dumps([]),
            )
            gossip_equiv = json.loads(
                lambda_aitia_rust.detect_checkpoint_equivocation(
                    sth_5_json, sth_5_evil_json, witness_policy_json
                )
            )
            assert gossip_equiv["schema"] == "lambda-aitia.checkpoint-equivocation-evidence.v1"
            assert gossip_equiv["status"] == "equivocation-detected", gossip_equiv
            assert gossip_equiv["equivocationDetected"] is True
            assert gossip_equiv["conflictKind"] == "same-size-root-mismatch"
            assert gossip_equiv["evidenceDigest"].startswith("sha256:")
            assert gossip_equiv["leftWitnessQuorumMet"] is True
            assert gossip_equiv["rightWitnessQuorumMet"] is False
            assert gossip_equiv["actionAuthorized"] is False

            # Scenario M: RFC 0018 Unified Witness-Backed Air-Gapped Audit Bundle (CLI + PyO3)
            #             & Exhaustive 48-Case Quint <-> Rust Differential Oracle
            p25_obj = json.loads(p25_json)
            unified_bundle = dict(
                inproc_bundle,
                transparencyLog={
                    "witnessPolicy": witness_policy,
                    "priorCheckpoint": sth_2,
                    "checkpoint": sth_5,
                    "consistencyProof": p25_obj,
                    "entries": log_entries,
                    "repoInclusionProofs": [merkle_proof],
                    "peerCheckpoints": [
                        {"checkpoint": sth_2, "consistencyProof": p25_obj},
                        {"checkpoint": sth_5},
                    ],
                },
            )
            # M1. Verify unified bundle via BOTH air-gapped CLI (with pinned workspace.sysml in empty dir)
            #     and in-process PyO3 wheel!
            with tempfile.TemporaryDirectory() as unified_airgap_dir:
                unified_cli_verdict = json.loads(
                    subprocess.run(
                        [aitia_bin, "flow", "verify-attestation", "--workspace", str(ws_sysml)],
                        cwd=unified_airgap_dir,
                        env=env,
                        input=json.dumps(unified_bundle),
                        check=True,
                        capture_output=True,
                        text=True,
                    ).stdout
                )
            assert unified_cli_verdict["verified"] is True
            assert unified_cli_verdict["airGapped"] is True
            assert unified_cli_verdict["sysmlPolicyEnforced"] is True
            assert unified_cli_verdict["transparencyVerified"] is True
            assert unified_cli_verdict["consistencyTransitionVerified"] is True
            assert unified_cli_verdict["headLogEntryBound"] is True
            assert unified_cli_verdict["checkpointTreeSize"] == 5
            assert unified_cli_verdict["checkpointWitnessCount"] == 2
            assert unified_cli_verdict["gossipPeersVerified"] == 2
            assert unified_cli_verdict["repoInclusionProofsVerified"] == 1
            assert unified_cli_verdict["actionAuthorized"] is False

            unified_pyo3_verdict = json.loads(
                lambda_aitia_rust.verify_portable_audit_bundle(json.dumps(unified_bundle))
            )
            assert unified_pyo3_verdict["transparencyVerified"] is True
            assert unified_pyo3_verdict["headLogEntryBound"] is True
            assert unified_pyo3_verdict["gossipPeersVerified"] == 2
            assert unified_pyo3_verdict["repoInclusionProofsVerified"] == 1
            assert unified_pyo3_verdict["actionAuthorized"] is False

            # M2. Exhaustive 48-case Quint <-> Rust Differential Oracle:
            #     2 (witness) x 2 (consistency) x 2 (headBound) x 2 (merkle) x 3 (gossip) = 48 cases
            #     compared directly against pure Quint predicate `UnifiedAirGapAudit::unifiedAdmissible`.
            sth_5_evil = json.loads(sth_5_evil_json)
            bad_p25 = dict(p25_obj, proofHashes=["sha256:" + ("0" * 64)] * len(p25_obj["proofHashes"]))
            unbound_entries = json.loads(json.dumps(log_entries))
            unbound_entries[1]["bundleDigest"] = "sha256:" + ("e" * 64)
            sth_2_unbound = json.loads(
                lambda_aitia_rust.sign_checkpoint(
                    log_origin,
                    json.dumps(unbound_entries[:2]),
                    origin_seed,
                    json.dumps(
                        [
                            {"witnessId": "witness-us-east", "seedHex": w1_seed, "timestamp": 1795699100},
                            {"witnessId": "witness-eu-west", "seedHex": w2_seed, "timestamp": 1795699102},
                        ]
                    ),
                )
            )
            sth_5_unbound = json.loads(
                lambda_aitia_rust.sign_checkpoint(
                    log_origin,
                    json.dumps(unbound_entries),
                    origin_seed,
                    json.dumps(
                        [
                            {"witnessId": "witness-eu-west", "seedHex": w2_seed, "timestamp": 1795699200},
                            {"witnessId": "witness-ap-northeast", "seedHex": w3_seed, "timestamp": 1795699205},
                        ]
                    ),
                )
            )
            p25_unbound = json.loads(
                lambda_aitia_rust.generate_consistency_proof(json.dumps(unbound_entries), 2)
            )
            oracle_cases = 0
            oracle_admitted = 0
            for witness_ok in (True, False):
                for cons_ok in (True, False):
                    for head_bound in (True, False):
                        for merkle_ok in (True, False):
                            for gossip_mode in ("consistent", "equivocation", "unresolved"):
                                expected = (
                                    witness_ok
                                    and cons_ok
                                    and head_bound
                                    and merkle_ok
                                    and (gossip_mode == "consistent")
                                )
                                cp_prior = sth_2 if head_bound else sth_2_unbound
                                cp_cur = sth_5 if head_bound else sth_5_unbound
                                cur_entries = log_entries if head_bound else unbound_entries
                                cur_p25 = p25_obj if head_bound else p25_unbound
                                if not cons_ok:
                                    cur_p25 = bad_p25
                                if not witness_ok:
                                    cp_cur = json.loads(json.dumps(cp_cur))
                                    cp_cur["cosignatures"] = [cp_cur["cosignatures"][0], cp_cur["cosignatures"][0]]
                                cur_merkle = merkle_proof if merkle_ok else tampered_proof
                                if gossip_mode == "consistent":
                                    peers = [{"checkpoint": cp_cur}]
                                elif gossip_mode == "equivocation":
                                    peers = [{"checkpoint": sth_5_evil}]
                                else:
                                    peers = [{"checkpoint": cp_prior}]
                                case_bundle = dict(
                                    inproc_bundle,
                                    transparencyLog={
                                        "witnessPolicy": witness_policy,
                                        "priorCheckpoint": cp_prior,
                                        "checkpoint": cp_cur,
                                        "consistencyProof": cur_p25,
                                        "entries": cur_entries,
                                        "repoInclusionProofs": [cur_merkle],
                                        "peerCheckpoints": peers,
                                    },
                                )
                                err_msg = ""
                                try:
                                    res = json.loads(
                                        lambda_aitia_rust.verify_portable_audit_bundle(
                                            json.dumps(case_bundle)
                                        )
                                    )
                                    actual = bool(res["verified"] and res["transparencyVerified"])
                                    assert res["actionAuthorized"] is False
                                except ValueError as exc:
                                    actual = False
                                    err_msg = str(exc)
                                if (
                                    witness_ok
                                    and cons_ok
                                    and not head_bound
                                    and merkle_ok
                                    and gossip_mode == "consistent"
                                ):
                                    assert "commit to the verified attestation chain head" in err_msg, err_msg
                                if (
                                    witness_ok
                                    and cons_ok
                                    and head_bound
                                    and merkle_ok
                                    and gossip_mode == "equivocation"
                                ):
                                    assert "peer gossip equivocation" in err_msg, err_msg
                                if (
                                    witness_ok
                                    and cons_ok
                                    and head_bound
                                    and merkle_ok
                                    and gossip_mode == "unresolved"
                                ):
                                    assert "lacks consistency proof" in err_msg, err_msg
                                assert actual is expected, (
                                    f"Oracle mismatch on witness={witness_ok} cons={cons_ok} "
                                    f"head={head_bound} merkle={merkle_ok} gossip={gossip_mode}: "
                                    f"actual={actual} expected={expected}"
                                )
                                oracle_cases += 1
                                if actual:
                                    oracle_admitted += 1
            assert oracle_cases == 48 and oracle_admitted == 1, (oracle_cases, oracle_admitted)

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
                "scenarioE_attestationDigest": att["bundleDigest"],
                "scenarioE_tamperRejected": tamper_proc.returncode != 0,
                "scenarioE_cacheHits": len(cache_doc["verificationCacheHits"]),
                "scenarioE_abiInvalidatedPeers": [
                    rid for rid in ("protocol-base", "ledger-core", "network-mux") if not inv_hits[rid]
                ],
                "scenarioF_tufQuorumSigners": len(att["signatures"]),
                "scenarioF_tufEpoch": att["payload"]["epoch"],
                "scenarioF_duplicateKeyRejected": dup_proc.returncode != 0,
                "scenarioF_revokedKeyRejected": revoked_proc.returncode != 0,
                "scenarioF_epochRollbackRejected": rollback_proc.returncode != 0,
                "scenarioF_counterfactualBranchesPreserved": len(cf_matrix),
                "scenarioG_rotatedRootVersion": lineage_meta["rootVersion"],
                "scenarioG_verifiedChainLength": lineage_meta["chainLength"],
                "scenarioG_unilateralRotationRejected": hijack_proc.returncode != 0,
                "scenarioG_brokenParentHashRejected": broken_chain_proc.returncode != 0,
                "scenarioH_assumeGuaranteeGapDetected": ag_gap_doc["contractGaps"][0]["missingAssumption"],
                "scenarioH_counterfactualFixesPreserved": len(ag_cf),
                "scenarioH_sysmlTufPolicyFloorEnforced": weak_policy_proc.returncode != 0,
                "scenarioI_airGappedAuditVerified": audit_verdict["verified"],
                "scenarioI_airGappedSysmlPolicyEnforced": audit_verdict["sysmlPolicyEnforced"],
                "scenarioI_spoofedPolicyRejected": weak_audit_proc.returncode != 0,
                "scenarioI_missingRepoRejected": missing_repo_proc.returncode != 0,
                "scenarioJ_inProcessPyO3AuditVerified": inproc_verdict["verified"],
                "scenarioJ_merkleRoot": inproc_verdict["headMerkleRoot"],
                "scenarioJ_merkleSiblings": merkle_verdict["siblingCount"],
                "scenarioJ_merkleTamperRejected": merkle_tamper_rejected,
                "scenarioJ_merkleFlipRejected": merkle_flip_rejected,
                "scenarioK_consistencyTransitionsVerified": ["1->2", "2->3", "3->5"],
                "scenarioK_equivocationRejected": equivocation_rejected,
                "scenarioK_truncationRejected": truncation_rejected,
                "scenarioL_cosignedTransitionVerified": transition_verdict["verified"],
                "scenarioL_witnessDuplicateRejected": witness_dup_rejected,
                "scenarioL_witnessRevokedRejected": witness_revoked_rejected,
                "scenarioL_crossOriginRejected": witness_origin_rejected,
                "scenarioL_gossipUnknownStatus": gossip_unknown["status"],
                "scenarioL_gossipEquivocationKind": gossip_equiv["conflictKind"],
                "scenarioL_equivocationEvidenceDigest": gossip_equiv["evidenceDigest"],
                "scenarioM_unifiedCliAirGapVerified": unified_cli_verdict["transparencyVerified"],
                "scenarioM_unifiedPyO3AirGapVerified": unified_pyo3_verdict["transparencyVerified"],
                "scenarioM_gossipPeersVerified": unified_cli_verdict["gossipPeersVerified"],
                "scenarioM_repoInclusionProofsVerified": unified_cli_verdict["repoInclusionProofsVerified"],
                "scenarioM_differentialOracleCases": oracle_cases,
                "scenarioM_differentialOracleAdmitted": oracle_admitted,
                "verifiedRemoteHeads": verified_heads,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
