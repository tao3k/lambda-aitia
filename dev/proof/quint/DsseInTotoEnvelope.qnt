// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0019:
/// Standard in-toto v1 / SLSA v1.0 DSSE PAE Envelope Interoperability,
/// TUF Quorum & Anti-Rollback Enforcement, Head-Digest Binding,
/// and Zero-Authority Verdict Invariants.
module DsseInTotoEnvelope {
  val INTOTO_TYPE: int = 1
  val ALLOWED_SIGNERS: Set[int] = Set(1, 2, 3)

  var payloadType: int
  var paeMatchesType: bool
  var signers: Set[int]
  var revoked: Set[int]
  var threshold: int
  var epoch: int
  var minEpoch: int
  var headDigestMatches: bool
  var dsseVerified: bool
  var actionAuthorized: bool

  pure def validSignerCount(sigs: Set[int], rev: Set[int]): int =
    size(sigs.intersect(ALLOWED_SIGNERS).exclude(rev))

  pure def dsseAdmissible(
    pType: int,
    paeOk: bool,
    sigs: Set[int],
    rev: Set[int],
    k: int,
    ep: int,
    minEp: int,
    headOk: bool
  ): bool =
    and {
      pType == INTOTO_TYPE,
      paeOk,
      k >= 1,
      validSignerCount(sigs, rev) >= k,
      ep >= minEp,
      headOk,
    }

  action init = all {
    payloadType' = INTOTO_TYPE,
    paeMatchesType' = true,
    signers' = Set(),
    revoked' = Set(),
    threshold' = 2,
    epoch' = 6,
    minEpoch' = 5,
    headDigestMatches' = true,
    dsseVerified' = false,
    actionAuthorized' = false,
  }

  action verifyDsse(
    pType: int,
    paeOk: bool,
    sigs: Set[int],
    rev: Set[int],
    k: int,
    ep: int,
    minEp: int,
    headOk: bool
  ): bool = all {
    payloadType' = pType,
    paeMatchesType' = paeOk,
    signers' = sigs,
    revoked' = rev,
    threshold' = k,
    epoch' = ep,
    minEpoch' = minEp,
    headDigestMatches' = headOk,
    dsseVerified' = dsseAdmissible(pType, paeOk, sigs, rev, k, ep, minEp, headOk),
    actionAuthorized' = false,
  }

  /// Negative control: accept DSSE payload without verifying PAE payloadType binding.
  action unsafeSkipPaeTypeBinding(sigs: Set[int], k: int): bool = all {
    payloadType' = 99,
    paeMatchesType' = false,
    signers' = sigs,
    revoked' = Set(),
    threshold' = k,
    epoch' = 6,
    minEpoch' = 5,
    headDigestMatches' = true,
    dsseVerified' = (validSignerCount(sigs, Set()) >= k),
    actionAuthorized' = false,
  }

  val invDsseInTotoSafe: bool = and {
    not(actionAuthorized),
    dsseVerified implies dsseAdmissible(
      payloadType,
      paeMatchesType,
      signers,
      revoked,
      threshold,
      epoch,
      minEpoch,
      headDigestMatches
    ),
  }

  run validDsseInTotoEnvelopeAcceptedTest =
    init
      .then(verifyDsse(INTOTO_TYPE, true, Set(1, 2), Set(), 2, 6, 5, true))
      .expect(dsseVerified and invDsseInTotoSafe)

  run payloadTypeConfusionRejectedTest =
    init
      .then(verifyDsse(99, false, Set(1, 2), Set(), 2, 6, 5, true))
      .expect(not(dsseVerified) and invDsseInTotoSafe)

  run revokedSignerRejectedTest =
    init
      .then(verifyDsse(INTOTO_TYPE, true, Set(1, 2), Set(2), 2, 6, 5, true))
      .expect(not(dsseVerified) and invDsseInTotoSafe)

  run duplicateSignerKeyRejectedTest =
    init
      .then(verifyDsse(INTOTO_TYPE, true, Set(1), Set(), 2, 6, 5, true))
      .expect(not(dsseVerified) and invDsseInTotoSafe)

  run headDigestMismatchRejectedTest =
    init
      .then(verifyDsse(INTOTO_TYPE, true, Set(1, 2), Set(), 2, 6, 5, false))
      .expect(not(dsseVerified) and invDsseInTotoSafe)

  run unsafeSkipPaeTypeBindingViolatesInvariantTest =
    init
      .then(unsafeSkipPaeTypeBinding(Set(1, 2), 2))
      .expect(not(invDsseInTotoSafe))
}
