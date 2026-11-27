// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of DE G2 Git Diff & Git Staged Anti-Defensive-Programming
/// Auditing + FunFlow/ASCENT Observability Telemetry (`aitia sidecar audit-diff` &
/// staged pre-commit gate in `aitia sidecar commit`).
module DiffDefenseFunFlowObservability {
  var stagedSilentFallbacks: int
  var stagedDeletedAssertions: int
  var stagedFloorWeakenings: int
  var stagedFabricatedEvidence: int
  var unstagedG2Defects: int
  var funflowTraceEmitted: bool
  var repairPacketEmitted: bool
  var stagedCommitAdmitted: bool
  var actionAuthorized: bool

  pure def stagedClean(
    silent: int,
    deleted: int,
    weakened: int,
    fabricated: int
  ): bool =
    and {
      silent == 0,
      deleted == 0,
      weakened == 0,
      fabricated == 0,
    }

  action init = all {
    stagedSilentFallbacks' = 0,
    stagedDeletedAssertions' = 0,
    stagedFloorWeakenings' = 0,
    stagedFabricatedEvidence' = 0,
    unstagedG2Defects' = 1,
    funflowTraceEmitted' = true,
    repairPacketEmitted' = true,
    stagedCommitAdmitted' = false,
    actionAuthorized' = false,
  }

  action auditDiffAndStaged(
    silent: int,
    deleted: int,
    weakened: int,
    fabricated: int,
    unstaged: int
  ): bool = {
    val clean = stagedClean(silent, deleted, weakened, fabricated)
    all {
      stagedSilentFallbacks' = silent,
      stagedDeletedAssertions' = deleted,
      stagedFloorWeakenings' = weakened,
      stagedFabricatedEvidence' = fabricated,
      unstagedG2Defects' = unstaged,
      funflowTraceEmitted' = true,
      repairPacketEmitted' = (not(clean) or unstaged > 0),
      stagedCommitAdmitted' = clean,
      actionAuthorized' = false,
    }
  }

  /// Negative control: commit admitted while staged diff deletes an assertion or adds silent fallback.
  action unsafeAdmitStagedG2Defect: bool = all {
    stagedSilentFallbacks' = 1,
    stagedDeletedAssertions' = 1,
    stagedFloorWeakenings' = 0,
    stagedFabricatedEvidence' = 0,
    unstagedG2Defects' = 0,
    funflowTraceEmitted' = true,
    repairPacketEmitted' = false,
    stagedCommitAdmitted' = true,
    actionAuthorized' = false,
  }

  val invDiffDefenseSafe: bool = and {
    not(actionAuthorized),
    funflowTraceEmitted,
    stagedCommitAdmitted implies stagedClean(
      stagedSilentFallbacks,
      stagedDeletedAssertions,
      stagedFloorWeakenings,
      stagedFabricatedEvidence
    ),
    (unstagedG2Defects > 0) implies repairPacketEmitted,
  }

  run cleanStagedAndUnstagedAdmittedTest =
    init
      .then(auditDiffAndStaged(0, 0, 0, 0, 0))
      .expect(stagedCommitAdmitted and not(repairPacketEmitted) and invDiffDefenseSafe)

  run stagedSilentFallbackRefusedTest =
    init
      .then(auditDiffAndStaged(1, 0, 0, 0, 0))
      .expect(not(stagedCommitAdmitted) and repairPacketEmitted and invDiffDefenseSafe)

  run stagedDeletedAssertionRefusedTest =
    init
      .then(auditDiffAndStaged(0, 1, 0, 0, 0))
      .expect(not(stagedCommitAdmitted) and repairPacketEmitted and invDiffDefenseSafe)

  run stagedFabricatedEvidenceRefusedTest =
    init
      .then(auditDiffAndStaged(0, 0, 0, 1, 0))
      .expect(not(stagedCommitAdmitted) and repairPacketEmitted and invDiffDefenseSafe)

  run unstagedG2DefectEmitsRepairPacketTest =
    init
      .then(auditDiffAndStaged(0, 0, 0, 0, 2))
      .expect(repairPacketEmitted and funflowTraceEmitted and invDiffDefenseSafe)

  run unsafeStagedDefectViolatesInvariantTest =
    init
      .then(unsafeAdmitStagedG2Defect)
      .expect(not(invDiffDefenseSafe))
}
