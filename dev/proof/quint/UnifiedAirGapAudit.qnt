// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0018:
/// Unified Witness-Backed Air-Gapped Audit Verification composing:
/// - RFC 0014 TUF chain + OpenSysML policy floor + repo inventory,
/// - RFC 0015 per-repo Merkle inclusion proofs,
/// - RFC 0016 RFC 6962 append-only consistency transitions,
/// - RFC 0017 witness-cosigned STH checkpoints & cross-auditor gossip anti-equivocation,
/// with zero-authority verdict invariants (`actionAuthorized == false`).
module UnifiedAirGapAudit {
  var tufChainValid: bool
  var witnessQuorumMet: bool
  var consistencyValid: bool
  var headBoundToLog: bool
  var merkleInclusionValid: bool
  var gossipEquivocationDetected: bool
  var gossipUnresolvedPeer: bool
  var unifiedAuditVerified: bool
  var actionAuthorized: bool

  pure def unifiedAdmissible(
    tufOk: bool,
    witnessOk: bool,
    consOk: bool,
    headBound: bool,
    merkleOk: bool,
    equivDetected: bool,
    unresolvedPeer: bool
  ): bool =
    and {
      tufOk,
      witnessOk,
      consOk,
      headBound,
      merkleOk,
      not(equivDetected),
      not(unresolvedPeer),
    }

  action init = all {
    tufChainValid' = false,
    witnessQuorumMet' = false,
    consistencyValid' = false,
    headBoundToLog' = false,
    merkleInclusionValid' = false,
    gossipEquivocationDetected' = false,
    gossipUnresolvedPeer' = false,
    unifiedAuditVerified' = false,
    actionAuthorized' = false,
  }

  action evaluateUnifiedAudit(
    tufOk: bool,
    witnessOk: bool,
    consOk: bool,
    headBound: bool,
    merkleOk: bool,
    equivDetected: bool,
    unresolvedPeer: bool
  ): bool = all {
    tufChainValid' = tufOk,
    witnessQuorumMet' = witnessOk,
    consistencyValid' = consOk,
    headBoundToLog' = headBound,
    merkleInclusionValid' = merkleOk,
    gossipEquivocationDetected' = equivDetected,
    gossipUnresolvedPeer' = unresolvedPeer,
    unifiedAuditVerified' = unifiedAdmissible(
      tufOk,
      witnessOk,
      consOk,
      headBound,
      merkleOk,
      equivDetected,
      unresolvedPeer
    ),
    actionAuthorized' = false,
  }

  /// Negative control: admit unified audit while ignoring peer gossip equivocation!
  action unsafeIgnoreGossipEquivocation(
    tufOk: bool,
    witnessOk: bool,
    consOk: bool,
    headBound: bool,
    merkleOk: bool
  ): bool = all {
    tufChainValid' = tufOk,
    witnessQuorumMet' = witnessOk,
    consistencyValid' = consOk,
    headBoundToLog' = headBound,
    merkleInclusionValid' = merkleOk,
    gossipEquivocationDetected' = true,
    gossipUnresolvedPeer' = false,
    unifiedAuditVerified' = (tufOk and witnessOk and consOk and headBound and merkleOk),
    actionAuthorized' = false,
  }

  val invUnifiedAirGapSafe: bool = and {
    not(actionAuthorized),
    unifiedAuditVerified implies unifiedAdmissible(
      tufChainValid,
      witnessQuorumMet,
      consistencyValid,
      headBoundToLog,
      merkleInclusionValid,
      gossipEquivocationDetected,
      gossipUnresolvedPeer
    ),
  }

  run completeUnifiedAuditAcceptedTest =
    init
      .then(evaluateUnifiedAudit(true, true, true, true, true, false, false))
      .expect(unifiedAuditVerified and invUnifiedAirGapSafe)

  run gossipEquivocationBlocksUnifiedAuditTest =
    init
      .then(evaluateUnifiedAudit(true, true, true, true, true, true, false))
      .expect(not(unifiedAuditVerified) and invUnifiedAirGapSafe)

  run unresolvedGossipPeerBlocksUnifiedAuditTest =
    init
      .then(evaluateUnifiedAudit(true, true, true, true, true, false, true))
      .expect(not(unifiedAuditVerified) and invUnifiedAirGapSafe)

  run unboundHeadAttestationBlocksUnifiedAuditTest =
    init
      .then(evaluateUnifiedAudit(true, true, true, false, true, false, false))
      .expect(not(unifiedAuditVerified) and invUnifiedAirGapSafe)

  run brokenMerkleInclusionBlocksUnifiedAuditTest =
    init
      .then(evaluateUnifiedAudit(true, true, true, true, false, false, false))
      .expect(not(unifiedAuditVerified) and invUnifiedAirGapSafe)

  run unsafeIgnoreGossipEquivocationViolatesInvariantTest =
    init
      .then(unsafeIgnoreGossipEquivocation(true, true, true, true, true))
      .expect(not(invUnifiedAirGapSafe))
}
