// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0012:
/// TUF Dual-Quorum Root Rotation Chain (R1 -> R2) and Transitive Multi-Epoch
/// Parent-Linked Release Attestation Lineage (Epoch 5 -> Epoch 6).
module TufRootRotationChain {
  var rootVersion: int
  var minEpoch: int
  var activeKeys: Set[str]
  var revokedKeys: Set[str]
  var threshold: int

  var lastBundleDigest: str
  var lastBundleEpoch: int
  var chainLength: int
  var rotationAccepted: bool
  var chainAccepted: bool
  var actionAuthorized: bool

  pure def distinctIn(signers: List[str], allowed: Set[str], revoked: Set[str]): Set[str] =
    signers.foldl(Set(), (acc, k) =>
      if (allowed.contains(k) and not(revoked.contains(k))) acc.union(Set(k)) else acc
    )

  pure def anyRevoked(signers: List[str], revoked: Set[str]): bool =
    signers.foldl(false, (acc, k) => acc or revoked.contains(k))

  pure def validRotation(
    oldVer: int,
    newVer: int,
    oldMinEp: int,
    newMinEp: int,
    oldKeys: Set[str],
    newKeys: Set[str],
    oldRevoked: Set[str],
    newRevoked: Set[str],
    oldThresh: int,
    newThresh: int,
    oldSigners: List[str],
    newSigners: List[str]
  ): bool =
    and {
      newVer == oldVer + 1,
      newMinEp >= oldMinEp,
      oldThresh >= 1,
      newThresh >= 1,
      not(anyRevoked(oldSigners, oldRevoked)),
      not(anyRevoked(newSigners, newRevoked)),
      distinctIn(oldSigners, oldKeys, oldRevoked).size() >= oldThresh,
      distinctIn(newSigners, newKeys, newRevoked).size() >= newThresh,
    }

  action init = all {
    rootVersion' = 1,
    minEpoch' = 5,
    activeKeys' = Set("keyA", "keyB", "keyC"),
    revokedKeys' = Set(),
    threshold' = 2,
    lastBundleDigest' = "sha256:epoch5",
    lastBundleEpoch' = 5,
    chainLength' = 1,
    rotationAccepted' = true,
    chainAccepted' = true,
    actionAuthorized' = false,
  }

  action rotateRoot(
    newVer: int,
    newMinEp: int,
    newKeys: Set[str],
    newRevoked: Set[str],
    newThresh: int,
    oldSigners: List[str],
    newSigners: List[str]
  ): bool = {
    val ok = validRotation(
      rootVersion, newVer, minEpoch, newMinEp,
      activeKeys, newKeys, revokedKeys, newRevoked,
      threshold, newThresh, oldSigners, newSigners
    )
    all {
      rotationAccepted' = ok,
      rootVersion' = if (ok) newVer else rootVersion,
      minEpoch' = if (ok) newMinEp else minEpoch,
      activeKeys' = if (ok) newKeys else activeKeys,
      revokedKeys' = if (ok) newRevoked else revokedKeys,
      threshold' = if (ok) newThresh else threshold,
      lastBundleDigest' = lastBundleDigest,
      lastBundleEpoch' = lastBundleEpoch,
      chainLength' = chainLength,
      chainAccepted' = chainAccepted,
      actionAuthorized' = false,
    }
  }

  action appendChainLink(
    newDigest: str,
    claimedParent: str,
    newEpoch: int,
    signers: List[str]
  ): bool = {
    val ok = and {
      claimedParent == lastBundleDigest,
      newEpoch > lastBundleEpoch,
      newEpoch >= minEpoch,
      not(anyRevoked(signers, revokedKeys)),
      distinctIn(signers, activeKeys, revokedKeys).size() >= threshold,
    }
    all {
      chainAccepted' = ok,
      lastBundleDigest' = if (ok) newDigest else lastBundleDigest,
      lastBundleEpoch' = if (ok) newEpoch else lastBundleEpoch,
      chainLength' = if (ok) chainLength + 1 else chainLength,
      rootVersion' = rootVersion,
      minEpoch' = minEpoch,
      activeKeys' = activeKeys,
      revokedKeys' = revokedKeys,
      threshold' = threshold,
      rotationAccepted' = rotationAccepted,
      actionAuthorized' = false,
    }
  }

  /// Negative control: accept root rotation verified ONLY by new keys (unilateral hijack).
  action unsafeUnilateralRootRotation(
    newVer: int,
    newKeys: Set[str],
    newSigners: List[str]
  ): bool = all {
    rotationAccepted' = distinctIn(newSigners, newKeys, Set()).size() >= threshold,
    rootVersion' = newVer,
    activeKeys' = newKeys,
    revokedKeys' = revokedKeys,
    minEpoch' = minEpoch,
    threshold' = threshold,
    lastBundleDigest' = lastBundleDigest,
    lastBundleEpoch' = lastBundleEpoch,
    chainLength' = chainLength,
    chainAccepted' = chainAccepted,
    actionAuthorized' = false,
  }

  val rotationAndLineageSafetyInvariant: bool = and {
    not(actionAuthorized),
    rootVersion >= 1,
    lastBundleEpoch >= 5,
    chainLength >= 1,
    not(rotationAccepted and activeKeys == Set("evil1", "evil2")),
  }

  run validDualQuorumRotationAndChainTest =
    init
      .then(rotateRoot(
        2, 6,
        Set("keyB", "keyC", "keyD"), Set("keyA"), 2,
        List("keyA", "keyB"), List("keyB", "keyC")
      ))
      .then(appendChainLink("sha256:epoch6", "sha256:epoch5", 6, List("keyB", "keyC")))
      .expect(rotationAccepted and chainAccepted and rootVersion == 2 and chainLength == 2 and rotationAndLineageSafetyInvariant)

  run unilateralNewRootWithoutOldQuorumRejectedTest =
    init
      .then(rotateRoot(
        2, 6,
        Set("evil1", "evil2"), Set(), 2,
        List("evil1", "evil2"), List("evil1", "evil2")
      ))
      .expect(not(rotationAccepted) and rootVersion == 1 and rotationAndLineageSafetyInvariant)

  run rootVersionSkipRejectedTest =
    init
      .then(rotateRoot(
        3, 6,
        Set("keyB", "keyC", "keyD"), Set("keyA"), 2,
        List("keyA", "keyB"), List("keyB", "keyC")
      ))
      .expect(not(rotationAccepted) and rootVersion == 1 and rotationAndLineageSafetyInvariant)

  run brokenParentHashChainRejectedTest =
    init
      .then(appendChainLink("sha256:epoch6", "sha256:wrong-parent", 6, List("keyA", "keyB")))
      .expect(not(chainAccepted) and chainLength == 1 and rotationAndLineageSafetyInvariant)

  run nonMonotonicChainEpochRejectedTest =
    init
      .then(appendChainLink("sha256:epoch5b", "sha256:epoch5", 5, List("keyA", "keyB")))
      .expect(not(chainAccepted) and chainLength == 1 and rotationAndLineageSafetyInvariant)

  run unsafeSingleQuorumRotationViolatesInvariantTest =
    init
      .then(unsafeUnilateralRootRotation(2, Set("evil1", "evil2"), List("evil1", "evil2")))
      .expect(not(rotationAndLineageSafetyInvariant))
}
