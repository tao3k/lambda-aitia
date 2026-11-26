// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0011:
/// TUF k-of-n Threshold Release Attestation, Key Revocation, Epoch Rollback
/// Protection, and Counterfactual Competing-Branch Zero-Authority Invariants.
module TufThresholdAttestation {
  pure val AUTH_KEYS: Set[str] = Set("keyA", "keyB", "keyC")

  var revokedKeys: Set[str]
  var minEpoch: int
  var threshold: int

  var bundleEpoch: int
  var bundleSigners: List[str]
  var bundleDigestValid: bool
  var bundleAccepted: bool
  var counterfactualBranchesEvaluated: int
  var actionAuthorized: bool

  pure def distinctValidAuthorized(signers: List[str], revoked: Set[str]): Set[str] =
    signers.foldl(Set(), (acc, k) =>
      if (AUTH_KEYS.contains(k) and not(revoked.contains(k))) acc.union(Set(k)) else acc
    )

  pure def hasRevokedSigner(signers: List[str], revoked: Set[str]): bool =
    signers.foldl(false, (acc, k) => acc or revoked.contains(k))

  pure def quorumSatisfied(
    signers: List[str],
    revoked: Set[str],
    k: int,
    ep: int,
    floorEp: int,
    digestOk: bool
  ): bool =
    and {
      digestOk,
      ep >= floorEp,
      k >= 1,
      not(hasRevokedSigner(signers, revoked)),
      distinctValidAuthorized(signers, revoked).size() >= k,
    }

  action init = all {
    revokedKeys' = Set(),
    minEpoch' = 5,
    threshold' = 2,
    bundleEpoch' = 0,
    bundleSigners' = List(),
    bundleDigestValid' = false,
    bundleAccepted' = false,
    counterfactualBranchesEvaluated' = 0,
    actionAuthorized' = false,
  }

  action verifyBundle(ep: int, signers: List[str], digestOk: bool): bool = all {
    bundleEpoch' = ep,
    bundleSigners' = signers,
    bundleDigestValid' = digestOk,
    bundleAccepted' = quorumSatisfied(signers, revokedKeys, threshold, ep, minEpoch, digestOk),
    revokedKeys' = revokedKeys,
    minEpoch' = minEpoch,
    threshold' = threshold,
    counterfactualBranchesEvaluated' = counterfactualBranchesEvaluated,
    actionAuthorized' = false,
  }

  action revokeKey(k: str): bool = all {
    revokedKeys' = revokedKeys.union(Set(k)),
    bundleAccepted' = false,
    minEpoch' = minEpoch,
    threshold' = threshold,
    bundleEpoch' = bundleEpoch,
    bundleSigners' = bundleSigners,
    bundleDigestValid' = bundleDigestValid,
    counterfactualBranchesEvaluated' = counterfactualBranchesEvaluated,
    actionAuthorized' = false,
  }

  action advanceMinEpoch(newMin: int): bool = all {
    newMin >= minEpoch,
    minEpoch' = newMin,
    bundleAccepted' = false,
    revokedKeys' = revokedKeys,
    threshold' = threshold,
    bundleEpoch' = bundleEpoch,
    bundleSigners' = bundleSigners,
    bundleDigestValid' = bundleDigestValid,
    counterfactualBranchesEvaluated' = counterfactualBranchesEvaluated,
    actionAuthorized' = false,
  }

  action evaluateCounterfactualBranches(count: int): bool = all {
    count >= 2,
    counterfactualBranchesEvaluated' = count,
    revokedKeys' = revokedKeys,
    minEpoch' = minEpoch,
    threshold' = threshold,
    bundleEpoch' = bundleEpoch,
    bundleSigners' = bundleSigners,
    bundleDigestValid' = bundleDigestValid,
    bundleAccepted' = bundleAccepted,
    actionAuthorized' = false,
  }

  /// Negative control: naive verifier that counts list length instead of distinct keys.
  action unsafeAcceptDuplicateKeyQuorum(ep: int, signers: List[str]): bool = all {
    bundleEpoch' = ep,
    bundleSigners' = signers,
    bundleDigestValid' = true,
    bundleAccepted' = signers.length() >= threshold,
    revokedKeys' = revokedKeys,
    minEpoch' = minEpoch,
    threshold' = threshold,
    counterfactualBranchesEvaluated' = counterfactualBranchesEvaluated,
    actionAuthorized' = false,
  }

  val tufQuorumAndZeroAuthorityInvariant: bool = and {
    not(actionAuthorized),
    bundleAccepted implies quorumSatisfied(
      bundleSigners, revokedKeys, threshold, bundleEpoch, minEpoch, bundleDigestValid
    ),
  }

  run quorumTwoOfThreeAcceptedTest =
    init
      .then(verifyBundle(5, List("keyA", "keyB"), true))
      .expect(bundleAccepted and tufQuorumAndZeroAuthorityInvariant)

  run duplicateKeyInflationRejectedTest =
    init
      .then(verifyBundle(5, List("keyA", "keyA"), true))
      .expect(not(bundleAccepted) and tufQuorumAndZeroAuthorityInvariant)

  run revokedKeyCompromiseRejectedTest =
    init
      .then(revokeKey("keyA"))
      .then(verifyBundle(5, List("keyA", "keyB"), true))
      .expect(not(bundleAccepted) and tufQuorumAndZeroAuthorityInvariant)

  run epochRollbackRejectedTest =
    init
      .then(advanceMinEpoch(6))
      .then(verifyBundle(5, List("keyA", "keyB"), true))
      .expect(not(bundleAccepted) and tufQuorumAndZeroAuthorityInvariant)

  run counterfactualBranchPreservesZeroAuthorityTest =
    init
      .then(verifyBundle(5, List("keyA", "keyB"), true))
      .then(evaluateCounterfactualBranches(2))
      .expect(
        counterfactualBranchesEvaluated == 2 and
        not(actionAuthorized) and
        tufQuorumAndZeroAuthorityInvariant
      )

  run unsafeDuplicateKeyQuorumViolatesInvariantTest =
    init
      .then(unsafeAcceptDuplicateKeyQuorum(5, List("keyA", "keyA")))
      .expect(not(tufQuorumAndZeroAuthorityInvariant))
}
