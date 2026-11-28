// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

// Formal Quint model for Multi-Repo GitOps Saga Partial-Publish, Durable Checkpoint
// Crash-Recovery, Compensation Honesty, and Signed Human Decision Replay Prevention
// (Pat Helland CIDR 2007 / Gray & Lamport Transaction Commit).
module MultiRepoSaga {
  var basePushCount: int
  var ledgerPushCount: int
  var netPushCount: int
  var nodePushCount: int
  var netFailed: bool
  var compensationPlanned: bool
  var appliedDecisions: Set[int]
  var decisionReplayRejected: bool

  action init = all {
    basePushCount' = 0,
    ledgerPushCount' = 0,
    netPushCount' = 0,
    nodePushCount' = 0,
    netFailed' = false,
    compensationPlanned' = false,
    appliedDecisions' = Set(),
    decisionReplayRejected' = false,
  }

  action pushBase = all {
    basePushCount == 0,
    basePushCount' = 1,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  action pushLedger = all {
    basePushCount == 1,
    ledgerPushCount == 0,
    basePushCount' = basePushCount,
    ledgerPushCount' = 1,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  action failNetworkRemoteHead = all {
    basePushCount == 1,
    netPushCount == 0,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = true,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  // Resume from durable checkpoint after repairing network-mux: skips already-pushed base & ledger
  action resumePushNetwork = all {
    basePushCount == 1,
    netPushCount == 0,
    netFailed,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = 1,
    nodePushCount' = nodePushCount,
    netFailed' = false,
    compensationPlanned' = false,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  action pushNode = all {
    basePushCount == 1 and ledgerPushCount == 1 and netPushCount == 1 and not(netFailed),
    nodePushCount == 0,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = 1,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  // Honest Saga compensation plan: never fabricates rollback of immutable published refs
  action planCompensation = all {
    netFailed,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = true,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  action applySignedDecision(did: int): bool = all {
    not(appliedDecisions.contains(did)),
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions.union(Set(did)),
    decisionReplayRejected' = false,
  }

  action rejectReplayedDecision(did: int): bool = all {
    appliedDecisions.contains(did),
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = true,
  }

  // Negative-control fault 1: ignoring checkpoint and re-pushing ledger
  action unsafeDoublePushLedger = all {
    ledgerPushCount == 1,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount + 1,
    netPushCount' = netPushCount,
    nodePushCount' = nodePushCount,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  // Negative-control fault 2: pushing node-runner while network-mux is failed
  action unsafePushNodeWhileNetFailed = all {
    netFailed,
    basePushCount' = basePushCount,
    ledgerPushCount' = ledgerPushCount,
    netPushCount' = netPushCount,
    nodePushCount' = 1,
    netFailed' = netFailed,
    compensationPlanned' = compensationPlanned,
    appliedDecisions' = appliedDecisions,
    decisionReplayRejected' = decisionReplayRejected,
  }

  val atMostOncePublication =
    basePushCount <= 1 and ledgerPushCount <= 1 and netPushCount <= 1 and nodePushCount <= 1

  val waveBarrierHolds =
    (ledgerPushCount == 0 or basePushCount == 1)
      and (netPushCount == 0 or basePushCount == 1)
      and (nodePushCount == 0 or (ledgerPushCount == 1 and netPushCount == 1 and not(netFailed)))

  val immutableHistoryHonest =
    not(compensationPlanned) or (basePushCount == 1 and nodePushCount == 0)

  run partialWaveBlocksDownstreamTest =
    init.then(pushBase).then(pushLedger).then(failNetworkRemoteHead)
      .expect(waveBarrierHolds and atMostOncePublication and nodePushCount == 0 and netFailed)

  run resumeCompletesWithoutDuplicatePushTest =
    init.then(pushBase).then(pushLedger).then(failNetworkRemoteHead)
      .then(resumePushNetwork).then(pushNode)
      .expect(atMostOncePublication and waveBarrierHolds and basePushCount == 1 and ledgerPushCount == 1 and netPushCount == 1 and nodePushCount == 1)

  run compensationHonestTest =
    init.then(pushBase).then(pushLedger).then(failNetworkRemoteHead).then(planCompensation)
      .expect(immutableHistoryHonest and waveBarrierHolds and atMostOncePublication)

  run decisionReplayRejectedTest =
    init.then(applySignedDecision(42)).then(rejectReplayedDecision(42))
      .expect(decisionReplayRejected and appliedDecisions.contains(42))

  run unsafeDoublePushViolatesAtMostOnceTest =
    init.then(pushBase).then(pushLedger).then(unsafeDoublePushLedger)
      .expect(not(atMostOncePublication))

  run unsafeSkipFailedPeerViolatesBarrierTest =
    init.then(pushBase).then(pushLedger).then(failNetworkRemoteHead).then(unsafePushNodeWhileNetFailed)
      .expect(not(waveBarrierHolds))
}
