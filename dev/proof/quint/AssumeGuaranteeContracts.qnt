// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0013:
/// OpenSysML v2 Cross-Repo Assume-Guarantee Compositional Contracts
/// (Benveniste et al., 2018) and SysML-Pinned TUF Policy Floor Governance.
module AssumeGuaranteeContracts {
  var baseGuarantees: Set[str]
  var ledgerAssumes: Set[str]
  var ledgerGuarantees: Set[str]
  var nodeAssumes: Set[str]

  var sysmlMinThreshold: int
  var sysmlMinEpoch: int
  var runtimeThreshold: int
  var runtimeMinEpoch: int

  var compositionAdmitted: bool
  var tufPolicyAdmitted: bool
  var actionAuthorized: bool

  pure def contractDischarged(assumesSet: Set[str], upstreamGuarantees: Set[str]): bool =
    assumesSet.subseteq(upstreamGuarantees)

  pure def allContractsDischarged(
    bG: Set[str],
    lA: Set[str],
    lG: Set[str],
    nA: Set[str]
  ): bool =
    and {
      contractDischarged(lA, bG),
      contractDischarged(nA, lG),
    }

  pure def meetsSysmlTufFloor(
    rtThresh: int,
    rtEp: int,
    polThresh: int,
    polEp: int
  ): bool =
    and {
      rtThresh >= polThresh,
      rtEp >= polEp,
      polThresh >= 1,
    }

  action init = all {
    baseGuarantees' = Set("protocol.v1.codecs", "crypto.ed25519"),
    ledgerAssumes' = Set("protocol.v1.codecs"),
    ledgerGuarantees' = Set("ledger.utxo.deterministic"),
    nodeAssumes' = Set("ledger.utxo.deterministic"),
    sysmlMinThreshold' = 2,
    sysmlMinEpoch' = 5,
    runtimeThreshold' = 2,
    runtimeMinEpoch' = 5,
    compositionAdmitted' = true,
    tufPolicyAdmitted' = true,
    actionAuthorized' = false,
  }

  action evaluateComposition(
    bG: Set[str],
    lA: Set[str],
    lG: Set[str],
    nA: Set[str]
  ): bool = all {
    baseGuarantees' = bG,
    ledgerAssumes' = lA,
    ledgerGuarantees' = lG,
    nodeAssumes' = nA,
    compositionAdmitted' = allContractsDischarged(bG, lA, lG, nA),
    sysmlMinThreshold' = sysmlMinThreshold,
    sysmlMinEpoch' = sysmlMinEpoch,
    runtimeThreshold' = runtimeThreshold,
    runtimeMinEpoch' = runtimeMinEpoch,
    tufPolicyAdmitted' = tufPolicyAdmitted,
    actionAuthorized' = false,
  }

  action checkSysmlTufPolicy(rtThresh: int, rtEp: int): bool = all {
    runtimeThreshold' = rtThresh,
    runtimeMinEpoch' = rtEp,
    tufPolicyAdmitted' = meetsSysmlTufFloor(rtThresh, rtEp, sysmlMinThreshold, sysmlMinEpoch),
    baseGuarantees' = baseGuarantees,
    ledgerAssumes' = ledgerAssumes,
    ledgerGuarantees' = ledgerGuarantees,
    nodeAssumes' = nodeAssumes,
    sysmlMinThreshold' = sysmlMinThreshold,
    sysmlMinEpoch' = sysmlMinEpoch,
    compositionAdmitted' = compositionAdmitted,
    actionAuthorized' = false,
  }

  /// Negative control: admit composition even when ledger assumes an unguaranteed property.
  action unsafeIgnoreMissingGuarantee(lA: Set[str]): bool = all {
    ledgerAssumes' = lA,
    compositionAdmitted' = true,
    baseGuarantees' = baseGuarantees,
    ledgerGuarantees' = ledgerGuarantees,
    nodeAssumes' = nodeAssumes,
    sysmlMinThreshold' = sysmlMinThreshold,
    sysmlMinEpoch' = sysmlMinEpoch,
    runtimeThreshold' = runtimeThreshold,
    runtimeMinEpoch' = runtimeMinEpoch,
    tufPolicyAdmitted' = tufPolicyAdmitted,
    actionAuthorized' = false,
  }

  val assumeGuaranteeAndPolicySafety: bool = and {
    not(actionAuthorized),
    compositionAdmitted implies allContractsDischarged(
      baseGuarantees, ledgerAssumes, ledgerGuarantees, nodeAssumes
    ),
    tufPolicyAdmitted implies meetsSysmlTufFloor(
      runtimeThreshold, runtimeMinEpoch, sysmlMinThreshold, sysmlMinEpoch
    ),
  }

  run satisfiedContractsAdmittedTest =
    init
      .then(evaluateComposition(
        Set("protocol.v1.codecs", "crypto.ed25519"),
        Set("protocol.v1.codecs"),
        Set("ledger.utxo.deterministic"),
        Set("ledger.utxo.deterministic")
      ))
      .expect(compositionAdmitted and assumeGuaranteeAndPolicySafety)

  run missingUpstreamGuaranteeFailsClosedTest =
    init
      .then(evaluateComposition(
        Set("protocol.v1.codecs"),
        Set("protocol.v1.codecs", "zero-copy.framing"),
        Set("ledger.utxo.deterministic"),
        Set("ledger.utxo.deterministic")
      ))
      .expect(not(compositionAdmitted) and assumeGuaranteeAndPolicySafety)

  run upstreamExportsGuaranteeRestoresClosureTest =
    init
      .then(evaluateComposition(
        Set("protocol.v1.codecs", "zero-copy.framing"),
        Set("protocol.v1.codecs", "zero-copy.framing"),
        Set("ledger.utxo.deterministic"),
        Set("ledger.utxo.deterministic")
      ))
      .expect(compositionAdmitted and assumeGuaranteeAndPolicySafety)

  run weakenedThresholdRejectedBySysmlPolicyTest =
    init
      .then(checkSysmlTufPolicy(1, 5))
      .expect(not(tufPolicyAdmitted) and assumeGuaranteeAndPolicySafety)

  run weakenedMinEpochRejectedBySysmlPolicyTest =
    init
      .then(checkSysmlTufPolicy(2, 4))
      .expect(not(tufPolicyAdmitted) and assumeGuaranteeAndPolicySafety)

  run unsafeIgnoreGapViolatesInvariantTest =
    init
      .then(unsafeIgnoreMissingGuarantee(Set("protocol.v1.codecs", "unproven.claim")))
      .expect(not(assumeGuaranteeAndPolicySafety))
}
