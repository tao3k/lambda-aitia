// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0020:
/// Sigstore Bundle v0.3 Wire Verification, Federated Multi-Organization Witness
/// Anti-Collusion Quorum, Offline Witness Timestamp Window & Skew Bounds,
/// RFC 6962 §2.1.1 Audit Inclusion Verification, and Zero-Authority Invariants.
module SigstoreFederatedWitness {
  var dsseValid: bool
  var tlogInclusionValid: bool
  var witnessCount: int
  var minWitnesses: int
  var distinctOrgs: int
  var minDistinctOrgs: int
  var minTs: int
  var maxTs: int
  var notBefore: int
  var notAfter: int
  var maxSkew: int
  var bundleVerified: bool
  var actionAuthorized: bool

  pure def sigstoreFederatedAdmissible(
    dOk: bool,
    incOk: bool,
    wCount: int,
    minW: int,
    orgs: int,
    minOrgs: int,
    tMin: int,
    tMax: int,
    nb: int,
    na: int,
    skewMax: int
  ): bool =
    and {
      dOk,
      incOk,
      minW >= 1,
      minOrgs >= 1,
      wCount >= minW,
      orgs >= minOrgs,
      nb <= tMin,
      tMin <= tMax,
      tMax <= na,
      (tMax - tMin) <= skewMax,
    }

  action init = all {
    dsseValid' = false,
    tlogInclusionValid' = false,
    witnessCount' = 0,
    minWitnesses' = 2,
    distinctOrgs' = 0,
    minDistinctOrgs' = 2,
    minTs' = 1000,
    maxTs' = 1005,
    notBefore' = 900,
    notAfter' = 1500,
    maxSkew' = 30,
    bundleVerified' = false,
    actionAuthorized' = false,
  }

  action verifyBundle(
    dOk: bool,
    incOk: bool,
    wCount: int,
    minW: int,
    orgs: int,
    minOrgs: int,
    tMin: int,
    tMax: int,
    nb: int,
    na: int,
    skewMax: int
  ): bool = all {
    dsseValid' = dOk,
    tlogInclusionValid' = incOk,
    witnessCount' = wCount,
    minWitnesses' = minW,
    distinctOrgs' = orgs,
    minDistinctOrgs' = minOrgs,
    minTs' = tMin,
    maxTs' = tMax,
    notBefore' = nb,
    notAfter' = na,
    maxSkew' = skewMax,
    bundleVerified' = sigstoreFederatedAdmissible(
      dOk, incOk, wCount, minW, orgs, minOrgs, tMin, tMax, nb, na, skewMax
    ),
    actionAuthorized' = false,
  }

  /// Negative control: ignore multi-org diversity and admit single-org collusion.
  action unsafeSkipOrgDiversity(wCount: int, minW: int, orgs: int, minOrgs: int): bool = all {
    dsseValid' = true,
    tlogInclusionValid' = true,
    witnessCount' = wCount,
    minWitnesses' = minW,
    distinctOrgs' = orgs,
    minDistinctOrgs' = minOrgs,
    minTs' = 1000,
    maxTs' = 1005,
    notBefore' = 900,
    notAfter' = 1500,
    maxSkew' = 30,
    bundleVerified' = (wCount >= minW),
    actionAuthorized' = false,
  }

  val invSigstoreFederatedSafe: bool = and {
    not(actionAuthorized),
    bundleVerified implies sigstoreFederatedAdmissible(
      dsseValid,
      tlogInclusionValid,
      witnessCount,
      minWitnesses,
      distinctOrgs,
      minDistinctOrgs,
      minTs,
      maxTs,
      notBefore,
      notAfter,
      maxSkew
    ),
  }

  run federatedSigstoreBundleAcceptedTest =
    init
      .then(verifyBundle(true, true, 2, 2, 2, 2, 1000, 1005, 900, 1500, 30))
      .expect(bundleVerified and invSigstoreFederatedSafe)

  run singleOrgCollusionRejectedTest =
    init
      .then(verifyBundle(true, true, 2, 2, 1, 2, 1000, 1005, 900, 1500, 30))
      .expect(not(bundleVerified) and invSigstoreFederatedSafe)

  run staleTimestampRejectedTest =
    init
      .then(verifyBundle(true, true, 2, 2, 2, 2, 850, 1005, 900, 1500, 30))
      .expect(not(bundleVerified) and invSigstoreFederatedSafe)

  run excessiveClockSkewRejectedTest =
    init
      .then(verifyBundle(true, true, 2, 2, 2, 2, 1000, 1150, 900, 1500, 30))
      .expect(not(bundleVerified) and invSigstoreFederatedSafe)

  run tlogInclusionMismatchRejectedTest =
    init
      .then(verifyBundle(true, false, 2, 2, 2, 2, 1000, 1005, 900, 1500, 30))
      .expect(not(bundleVerified) and invSigstoreFederatedSafe)

  run unsafeSkipOrgDiversityViolatesInvariantTest =
    init
      .then(unsafeSkipOrgDiversity(2, 2, 1, 2))
      .expect(not(invSigstoreFederatedSafe))
}
