#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Flagship SDLC Engineering Case: Billing Core -> Checkout Service Release Train.

Walks a real two-repository engineering change through all 4 SDLC stages with ZERO
`GERBIL_LOADPATH` and ZERO downstream Gerbil/Gambit compilation:
  Stage 1: Architecture & OpenSecurity design gate (competing worlds preserved -> resolved)
  Stage 2: Implementation cut in 2 real JJ repos + SysML `workspace.sysml` pin-drift detection
  Stage 3: Reviewed commit drafts (`aitia jj commit` + `preview`) before human approval
  Stage 4: Cascading Wave 0 -> Wave 1 fenced commit/push (`--workspace workspace.sysml --execute-fenced`)
           with per-repo `repoEvidenceLineages` and bare Git remote head verification on BOTH repos.
"""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from lambda_aitia_rust import Session


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
            "user.name='SDLC Release Train'",
            "--config",
            "user.email='release-train@example.invalid'",
            *args,
        ],
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
    )


def init_service_repo(
    jj_bin: str,
    env: dict[str, str],
    repo_dir: Path,
    bare_remote: Path,
    project: str,
    key: str,
    scope: str,
    base_file: str,
    change_file: str,
    change_code: str,
) -> None:
    subprocess.run(["git", "init", "--bare", str(bare_remote)], check=True, capture_output=True)
    repo_dir.mkdir(parents=True, exist_ok=True)
    run_jj(jj_bin, env, repo_dir, "git", "init", "--colocate")
    (repo_dir / ".agents" / "aita").mkdir(parents=True, exist_ok=True)
    (repo_dir / Path(base_file).parent).mkdir(parents=True, exist_ok=True)
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
                                            str(Path(base_file).parent),
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
    (repo_dir / "README.org").write_text(f"* {project}\nEnglish service documentation.\n", encoding="utf-8")
    (repo_dir / "work.org").write_text(
        "* Release Train RFC\n:PROPERTIES:\n:ID: work1\n:ENGINEERING_ID: RFC-1\n:END:\n",
        encoding="utf-8",
    )
    (repo_dir / base_file).write_text("// base module\n", encoding="utf-8")
    run_jj(jj_bin, env, repo_dir, "describe", "-m", f"base {project}")
    run_jj(jj_bin, env, repo_dir, "bookmark", "create", "reviewed", "-r", "@")
    run_jj(jj_bin, env, repo_dir, "git", "remote", "add", "origin", str(bare_remote))
    run_jj(jj_bin, env, repo_dir, "git", "push", "--remote", "origin", "--bookmark", "reviewed")

    run_jj(jj_bin, env, repo_dir, "new", "-m", f"candidate {project}")
    (repo_dir / change_file).write_text(change_code, encoding="utf-8")
    run_jj(jj_bin, env, repo_dir, "describe", "-m", f"candidate {project}")


def preview_reviewed_draft(
    aitia_bin: str,
    env: dict[str, str],
    repo_dir: Path,
    identity: str,
    scope: str,
    summary: str,
) -> tuple[str, dict]:
    cut_proc = subprocess.run(
        [aitia_bin, "jj", "commit"],
        cwd=repo_dir,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    cut_doc = json.loads(cut_proc.stdout)
    cut_commit = cut_doc["cut"]["commit"]
    draft = {
        "context": cut_doc["review"]["context"],
        "proposal": {
            "identity": identity,
            "reference": "RFC-1",
            "type": "feat",
            "scope": scope,
            "summary": summary,
            "rationale": "Coordinated SDLC release-train delivery governed by SysML v2 and FunFlow.",
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
    prev_proc = subprocess.run(
        [aitia_bin, "jj", "commit", "preview"],
        cwd=repo_dir,
        env=env,
        input=json.dumps(draft),
        check=True,
        capture_output=True,
        text=True,
    )
    prev_doc = json.loads(prev_proc.stdout)
    assert prev_doc["review"]["draftValid"] is True
    draft["context"] = prev_doc["review"]["context"]
    return cut_commit, draft


def run_stage1_architecture_gate() -> dict:
    sec_obligations = [
        "sec.sbom-provenance",
        "sec.dependency-audit",
        "sec.threat-model-review",
    ]
    with Session() as session:
        # 1a. Missing security obligations -> AI Agent synthesis (never interrupts human prematurely)
        sec_gap = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "release-train/billing-core",
                        "profile": "lambda-aitia/sdlc/open-security",
                        "changeId": "change:billing-v2",
                        "designAlternatives": ["sync-rpc", "async-outbox"],
                        "verified": True,
                        "observedObligations": ["sec.sbom-provenance"],
                    }
                )
            )
        )
        assert sec_gap["state"] == "need-agent-synthesis"
        assert len(sec_gap["repairTasks"]) == 2

        # 1b. Security checks discharged, competing architecture hypotheses stay preserved -> Human gate
        competing = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "release-train/billing-core",
                        "profile": "lambda-aitia/sdlc/open-security",
                        "changeId": "change:billing-v2",
                        "designAlternatives": ["sync-rpc", "async-outbox"],
                        "verified": True,
                        "observedObligations": sec_obligations,
                        "approvalLive": True,
                    }
                )
            )
        )
        assert competing["state"] == "need-human-decision"
        assert competing["epistemicSummary"]["worldCount"] == 2

        # 1c. Once a single design + all open-security obligations are discharged -> quiescent
        resolved = json.loads(
            session.workflow_protocol_step(
                json.dumps(
                    {
                        "caseId": "aitia/case/sdlc-lifecycle",
                        "project": "release-train/billing-core",
                        "profile": "lambda-aitia/sdlc/open-security",
                        "changeId": "change:billing-v2",
                        "designAlternatives": ["async-outbox"],
                        "verified": True,
                        "observedObligations": sec_obligations,
                        "approvalLive": True,
                        "releasePublished": True,
                    }
                )
            )
        )
        assert resolved["state"] == "quiescent"
        assert resolved["actionAuthorized"] is False
    return {
        "securityRepairTasksBeforeDecision": len(sec_gap["repairTasks"]),
        "competingWorldsPreserved": competing["epistemicSummary"]["worldCount"],
        "resolvedProfile": resolved["profile"],
        "resolvedState": resolved["state"],
    }


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    aitia_bin = os.environ.get("AITIA_BIN") or str(repo_root / "rust" / "target" / "debug" / "aitia")
    jj_bin = os.environ.get("AITIA_JJ_BIN") or shutil.which("jj")
    if not jj_bin:
        raise SystemExit("jj binary not found (set AITIA_JJ_BIN or put jj on PATH)")
    if not Path(aitia_bin).is_file():
        raise SystemExit(f"aitia binary not found at {aitia_bin} (set AITIA_BIN)")

    env = clean_env(jj_bin)
    stage1 = run_stage1_architecture_gate()

    sysml_template = Path(__file__).resolve().parent / "workspace.sysml"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        billing_dir = root / "billing-core"
        checkout_dir = root / "checkout-service"
        billing_remote = root / "remotes" / "billing-core.git"
        checkout_remote = root / "remotes" / "checkout-service.git"

        init_service_repo(
            jj_bin,
            env,
            billing_dir,
            billing_remote,
            "release-train/billing-core",
            "BILL",
            "billing",
            "src/lib.rs",
            "src/outbox.rs",
            "pub fn publish_invoice_event() {}\n",
        )
        init_service_repo(
            jj_bin,
            env,
            checkout_dir,
            checkout_remote,
            "release-train/checkout-service",
            "CHK",
            "checkout",
            "src/app.py",
            "src/handler.py",
            "def handle_checkout() -> str:\n    return 'outbox-v2'\n",
        )
        ws_sysml = root / "workspace.sysml"
        shutil.copy2(sysml_template, ws_sysml)

        # Stage 2: Preview reviewed drafts + detect cross-repo pin drift via SysML `--workspace`
        billing_cut, billing_draft = preview_reviewed_draft(
            aitia_bin, env, billing_dir, "BILL-RFC-1", "billing", "Add async outbox invoice publisher"
        )
        _, checkout_draft = preview_reviewed_draft(
            aitia_bin, env, checkout_dir, "CHK-RFC-1", "checkout", "Consume billing outbox v2 events"
        )

        stale_overlay = {
            "repos": [
                {
                    "repoId": "checkout-service",
                    "pinnedUpstreamCommits": {"billing-core": "0000000000000000000000000000000000000000"},
                }
            ]
        }
        drift_proc = subprocess.run(
            [aitia_bin, "flow", "run", "--workspace", str(ws_sysml), "--proposal-stdin"],
            cwd=root,
            env=env,
            input=json.dumps(stale_overlay),
            check=True,
            capture_output=True,
            text=True,
        )
        drift_doc = json.loads(drift_proc.stdout)
        assert drift_doc["state"] == "need-agent-synthesis"
        assert drift_doc["escalationReason"] == "cross-repo-pin-drift"
        assert drift_doc["waves"] == [["billing-core"], ["checkout-service"]]
        assert drift_doc["pinDrifts"][0]["actualCommit"] == billing_cut
        assert drift_doc["actionAuthorized"] is False

        # Stage 4: Human authorizes release train -> cascading Wave 0 -> Wave 1 commit & bare-remote push!
        decision_overlay = {
            "repos": [
                {"repoId": "billing-core", "approvalLive": True, "draft": billing_draft},
                {"repoId": "checkout-service", "approvalLive": True, "draft": checkout_draft},
            ]
        }
        exec_proc = subprocess.run(
            [aitia_bin, "flow", "submit-decision", "--workspace", str(ws_sysml), "--execute-fenced"],
            cwd=root,
            env=env,
            input=json.dumps(decision_overlay),
            check=True,
            capture_output=True,
            text=True,
        )
        exec_doc = json.loads(exec_proc.stdout)
        assert exec_doc["state"] == "quiescent"
        assert exec_doc["actionAuthorized"] is False
        assert exec_doc["waves"] == [["billing-core"], ["checkout-service"]]
        lineages = exec_doc["repoEvidenceLineages"]
        assert lineages["billing-core"]["missingReports"] == []
        assert lineages["checkout-service"]["missingReports"] == []

        billing_rev = lineages["billing-core"]["revision"]
        checkout_rev = lineages["checkout-service"]["revision"]
        for remote_path, expected_rev in ((billing_remote, billing_rev), (checkout_remote, checkout_rev)):
            head = subprocess.run(
                ["git", "rev-parse", "refs/heads/reviewed"],
                cwd=remote_path,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            assert head == expected_rev, f"{remote_path} head {head} != {expected_rev}"

    print(
        json.dumps(
            {
                "case": "sdlc-release-train",
                "stage1ArchitectureGate": stage1,
                "stage2PinDriftDetected": drift_doc["escalationReason"],
                "stage4Waves": exec_doc["waves"],
                "stage4FinalState": exec_doc["state"],
                "verifiedRemoteHeads": {
                    "billing-core": billing_rev,
                    "checkout-service": checkout_rev,
                },
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
