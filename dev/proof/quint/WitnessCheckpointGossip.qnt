// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0017:
/// Witness-Cosigned Signed Tree Heads (STH), Distinct Non-Revoked Witness Quorum,
/// Origin Separation, Cross-Auditor Gossip Split-View Equivocation Detection,
/// and Zero-Authority Verdict Invariants.
module WitnessCheckpointGossip {
  val PINNED_ORIGIN: int = 1
  val ALLOWED_WITNESSES: Set[int] = Set(1, 2, 3)

  var originMatches: bool
  var originSigValid: bool
  var threshold: int
  var distinctSigners: Set[int]
  var revokedSigners: Set[int]
  var consistencyValid: bool
  var transitionVerified: bool
  var leftSize: int
  var rightSize: int
  var leftRoot: int
  var rightRoot: int
  var equivocationDetected: bool
  var evidenceRecorded: bool
  var actionAuthorized: bool

  pure def validWitnessCount(signers: Set[int], revoked: Set[int]): int =
    size(signers.intersect(ALLOWED_WITNESSES).exclude(revoked))

  pure def quorumMet(signers: Set[int], revoked: Set[int], k: int): bool =
    and {
      k >= 1,
      validWitnessCount(signers, revoked) >= k,
    }

  pure def transitionAdmissible(
    origOk: bool,
    sigOk: bool,
    signers: Set[int],
    revoked: Set[int],
    k: int,
    consOk: bool
  ): bool =
    and {
      origOk,
      sigOk,
      quorumMet(signers, revoked, k),
      consOk,
    }

  pure def sameSizeEquivocation(
    origOk: bool,
    sigOk: bool,
    lSize: int,
    rSize: int,
    lRoot: int,
    rRoot: int
  ): bool =
    and {
      origOk,
      sigOk,
      lSize >= 1,
      lSize == rSize,
      lRoot != rRoot,
    }

  action init = all {
    originMatches' = true,
    originSigValid' = true,
    threshold' = 2,
    distinctSigners' = Set(),
    revokedSigners' = Set(),
    consistencyValid' = false,
    transitionVerified' = false,
    leftSize' = 5,
    rightSize' = 5,
    leftRoot' = 100,
    rightRoot' = 100,
    equivocationDetected' = false,
    evidenceRecorded' = false,
    actionAuthorized' = false,
  }

  action verifyCosignedTransition(
    origin: int,
    sigOk: bool,
    signers: Set[int],
    revoked: Set[int],
    k: int,
    consOk: bool
  ): bool = all {
    originMatches' = (origin == PINNED_ORIGIN),
    originSigValid' = sigOk,
    threshold' = k,
    distinctSigners' = signers,
    revokedSigners' = revoked,
    consistencyValid' = consOk,
    transitionVerified' = transitionAdmissible(
      origin == PINNED_ORIGIN,
      sigOk,
      signers,
      revoked,
      k,
      consOk
    ),
    leftSize' = leftSize,
    rightSize' = rightSize,
    leftRoot' = leftRoot,
    rightRoot' = rightRoot,
    equivocationDetected' = false,
    evidenceRecorded' = false,
    actionAuthorized' = false,
  }

  action gossipCompareSameSize(
    origin: int,
    sigOk: bool,
    lSize: int,
    rSize: int,
    lRoot: int,
    rRoot: int
  ): bool = all {
    originMatches' = (origin == PINNED_ORIGIN),
    originSigValid' = sigOk,
    threshold' = threshold,
    distinctSigners' = distinctSigners,
    revokedSigners' = revokedSigners,
    consistencyValid' = false,
    transitionVerified' = false,
    leftSize' = lSize,
    rightSize' = rSize,
    leftRoot' = lRoot,
    rightRoot' = rRoot,
    equivocationDetected' = sameSizeEquivocation(
      origin == PINNED_ORIGIN,
      sigOk,
      lSize,
      rSize,
      lRoot,
      rRoot
    ),
    evidenceRecorded' = sameSizeEquivocation(
      origin == PINNED_ORIGIN,
      sigOk,
      lSize,
      rSize,
      lRoot,
      rRoot
    ),
    actionAuthorized' = false,
  }

  /// Negative control: admit transition without checking witness quorum.
  action unsafeSkipWitnessQuorum(signers: Set[int], revoked: Set[int], k: int): bool = all {
    originMatches' = true,
    originSigValid' = true,
    threshold' = k,
    distinctSigners' = signers,
    revokedSigners' = revoked,
    consistencyValid' = true,
    transitionVerified' = true,
    leftSize' = leftSize,
    rightSize' = rightSize,
    leftRoot' = leftRoot,
    rightRoot' = rightRoot,
    equivocationDetected' = false,
    evidenceRecorded' = false,
    actionAuthorized' = false,
  }

  val invWitnessGossipSafe: bool = and {
    not(actionAuthorized),
    transitionVerified implies transitionAdmissible(
      originMatches,
      originSigValid,
      distinctSigners,
      revokedSigners,
      threshold,
      consistencyValid
    ),
    equivocationDetected implies and {
      evidenceRecorded,
      sameSizeEquivocation(
        originMatches,
        originSigValid,
        leftSize,
        rightSize,
        leftRoot,
        rightRoot
      ),
    },
  }

  run quorumCosignedTransitionAcceptedTest =
    init
      .then(verifyCosignedTransition(PINNED_ORIGIN, true, Set(1, 2), Set(), 2, true))
      .expect(transitionVerified and invWitnessGossipSafe)

  run duplicateWitnessKeyRejectedTest =
    init
      .then(verifyCosignedTransition(PINNED_ORIGIN, true, Set(1), Set(), 2, true))
      .expect(not(transitionVerified) and invWitnessGossipSafe)

  run revokedWitnessExcludedTest =
    init
      .then(verifyCosignedTransition(PINNED_ORIGIN, true, Set(1, 2), Set(2), 2, true))
      .expect(not(transitionVerified) and invWitnessGossipSafe)

  run sameSizeSplitViewEquivocationDetectedTest =
    init
      .then(gossipCompareSameSize(PINNED_ORIGIN, true, 5, 5, 100, 999))
      .expect(equivocationDetected and evidenceRecorded and invWitnessGossipSafe)

  run crossOriginReplayRejectedTest =
    init
      .then(verifyCosignedTransition(99, true, Set(1, 2), Set(), 2, true))
      .expect(not(transitionVerified) and invWitnessGossipSafe)

  run unsafeSkipWitnessQuorumViolatesInvariantTest =
    init
      .then(unsafeSkipWitnessQuorum(Set(1), Set(), 2))
      .expect(not(invWitnessGossipSafe))
}
