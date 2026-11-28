// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

// RFC 0009: Formal Quint model of the 4-repo Cardano/Bazel diamond
// (`protocol-base -> {ledger-core, network-mux} -> node-runner`):
//   1. Two-level bitemporal Early Cutoff (Bazel Skyframe Change Pruning)
//   2. Interface-breaking drift -> localized repair (never falsely pruned)
//   3. Transitive diamond pin conflict -> fail-closed need-human-decision
//   4. Wave dependency barrier (with negative-control counterexample)
//   5. io-sim-style concurrent peer schedule confluence
module MultiRepoDiamond {
  var baseCommit: int
  var baseIface: int
  var ledgerPinCommit: int
  var ledgerPinIface: int
  var netPinCommit: int
  var netPinIface: int
  var baseQuiescent: bool
  var ledgerQuiescent: bool
  var netQuiescent: bool
  var nodeQuiescent: bool
  var earlyCutoffPruned: bool
  var state: str

  pure def hasDiamondConflict(lIface: int, nIface: int): bool =
    lIface != nIface

  pure def isEarlyCutoff(upCommit: int, upIface: int, pinCommit: int, pinIface: int): bool =
    upCommit != pinCommit and upIface == pinIface

  pure def isBreakingDrift(upIface: int, pinIface: int): bool =
    upIface != pinIface

  action init = all {
    baseCommit' = 1,
    baseIface' = 1,
    ledgerPinCommit' = 1,
    ledgerPinIface' = 1,
    netPinCommit' = 1,
    netPinIface' = 1,
    baseQuiescent' = false,
    ledgerQuiescent' = false,
    netQuiescent' = false,
    nodeQuiescent' = false,
    earlyCutoffPruned' = false,
    state' = "need-fenced-frames",
  }

  // Wave 0: protocol-base advances internal commit (1 -> 2) with unchanged ABI (iface 1)
  action advanceBaseInternalOnly = all {
    baseCommit' = 2,
    baseIface' = 1,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = true,
    ledgerQuiescent' = true,
    netQuiescent' = true,
    nodeQuiescent' = true,
    earlyCutoffPruned' =
      (isEarlyCutoff(2, 1, ledgerPinCommit, ledgerPinIface)
        and isEarlyCutoff(2, 1, netPinCommit, netPinIface)),
    state' = "quiescent",
  }

  // Breaking ABI change on protocol-base (iface 1 -> 2) invalidates downstream
  action breakBaseInterface = all {
    baseCommit' = 2,
    baseIface' = 2,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = true,
    ledgerQuiescent' = false,
    netQuiescent' = false,
    nodeQuiescent' = false,
    earlyCutoffPruned' = false,
    state' = "need-agent-synthesis",
  }

  // Divergent branch pins: ledger upgrades to iface 2 while network still pins iface 1
  action introduceDiamondConflict = all {
    baseCommit' = 2,
    baseIface' = 2,
    ledgerPinCommit' = 2,
    ledgerPinIface' = 2,
    netPinCommit' = 1,
    netPinIface' = 1,
    baseQuiescent' = true,
    ledgerQuiescent' = false,
    netQuiescent' = false,
    nodeQuiescent' = false,
    earlyCutoffPruned' = false,
    state' = "need-human-decision",
  }

  // Safe Wave 0 -> Wave 1 -> Wave 2 transitions (testing both peer orderings)
  action applyBase = all {
    not(baseQuiescent),
    baseCommit' = baseCommit,
    baseIface' = baseIface,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = true,
    ledgerQuiescent' = ledgerQuiescent,
    netQuiescent' = netQuiescent,
    nodeQuiescent' = nodeQuiescent,
    earlyCutoffPruned' = false,
    state' = "need-fenced-frames",
  }

  action applyLedger = all {
    baseQuiescent,
    not(ledgerQuiescent),
    not(hasDiamondConflict(ledgerPinIface, netPinIface)),
    not(isBreakingDrift(baseIface, ledgerPinIface)),
    baseCommit' = baseCommit,
    baseIface' = baseIface,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = baseQuiescent,
    ledgerQuiescent' = true,
    netQuiescent' = netQuiescent,
    nodeQuiescent' = nodeQuiescent,
    earlyCutoffPruned' = earlyCutoffPruned,
    state' = "need-fenced-frames",
  }

  action applyNetwork = all {
    baseQuiescent,
    not(netQuiescent),
    not(hasDiamondConflict(ledgerPinIface, netPinIface)),
    not(isBreakingDrift(baseIface, netPinIface)),
    baseCommit' = baseCommit,
    baseIface' = baseIface,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = baseQuiescent,
    ledgerQuiescent' = ledgerQuiescent,
    netQuiescent' = true,
    nodeQuiescent' = nodeQuiescent,
    earlyCutoffPruned' = earlyCutoffPruned,
    state' = "need-fenced-frames",
  }

  action applyNode = all {
    baseQuiescent and ledgerQuiescent and netQuiescent,
    not(nodeQuiescent),
    not(hasDiamondConflict(ledgerPinIface, netPinIface)),
    baseCommit' = baseCommit,
    baseIface' = baseIface,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = baseQuiescent,
    ledgerQuiescent' = ledgerQuiescent,
    netQuiescent' = netQuiescent,
    nodeQuiescent' = true,
    earlyCutoffPruned' = earlyCutoffPruned,
    state' = "quiescent",
  }

  // Negative-control fault: applying node-runner before Wave 1 peers are quiescent
  action unsafeApplyNodeEarly = all {
    baseQuiescent and not(netQuiescent),
    baseCommit' = baseCommit,
    baseIface' = baseIface,
    ledgerPinCommit' = ledgerPinCommit,
    ledgerPinIface' = ledgerPinIface,
    netPinCommit' = netPinCommit,
    netPinIface' = netPinIface,
    baseQuiescent' = baseQuiescent,
    ledgerQuiescent' = ledgerQuiescent,
    netQuiescent' = netQuiescent,
    nodeQuiescent' = true,
    earlyCutoffPruned' = earlyCutoffPruned,
    state' = "quiescent",
  }

  val waveBarrierHolds =
    (not(ledgerQuiescent) or baseQuiescent)
      and (not(netQuiescent) or baseQuiescent)
      and (not(nodeQuiescent) or (ledgerQuiescent and netQuiescent))

  val earlyCutoffSound =
    not(earlyCutoffPruned) or (baseIface == ledgerPinIface and baseIface == netPinIface)

  val diamondConflictFailsClosed =
    not(hasDiamondConflict(ledgerPinIface, netPinIface))
      or (state == "need-human-decision" and not(nodeQuiescent))

  run earlyCutoffPrunesDownstreamTest =
    init.then(advanceBaseInternalOnly)
      .expect(earlyCutoffPruned and earlyCutoffSound and state == "quiescent" and waveBarrierHolds)

  run breakingInterfaceTriggersRepairTest =
    init.then(breakBaseInterface)
      .expect(not(earlyCutoffPruned) and earlyCutoffSound and state == "need-agent-synthesis" and not(nodeQuiescent))

  run diamondConflictFailsClosedTest =
    init.then(introduceDiamondConflict)
      .expect(diamondConflictFailsClosed and state == "need-human-decision" and not(nodeQuiescent))

  run scheduleConfluenceLedgerFirstTest =
    init.then(applyBase).then(applyLedger).then(applyNetwork).then(applyNode)
      .expect(waveBarrierHolds and state == "quiescent" and nodeQuiescent)

  run scheduleConfluenceNetworkFirstTest =
    init.then(applyBase).then(applyNetwork).then(applyLedger).then(applyNode)
      .expect(waveBarrierHolds and state == "quiescent" and nodeQuiescent)

  run unsafeEarlyNodeViolatesBarrierTest =
    init.then(applyBase).then(applyLedger).then(unsafeApplyNodeEarly)
      .expect(not(waveBarrierHolds))
}
