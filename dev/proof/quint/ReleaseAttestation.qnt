// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

// RFC 0010: Formal Quint model of Proof-Carrying Multi-Repo Release Attestations
// (in-toto / TUF / SLSA) and Adapton / Salsa Incremental Verification Memoization.
module ReleaseAttestation {
  var repoCommit: int
  var upstreamIface: int
  var policyDigest: int
  var attestedCommit: int
  var attestedUpstreamIface: int
  var attestedPolicyDigest: int
  var signatureValid: bool
  var missingReports: int
  var tampered: bool
  var bundleAccepted: bool
  var cacheHitAdmitted: bool

  pure def memoKeyMatches(rc: int, ui: int, pd: int, ac: int, aui: int, apd: int): bool =
    rc == ac and ui == aui and pd == apd

  action init = all {
    repoCommit' = 1,
    upstreamIface' = 10,
    policyDigest' = 100,
    attestedCommit' = 1,
    attestedUpstreamIface' = 10,
    attestedPolicyDigest' = 100,
    signatureValid' = true,
    missingReports' = 0,
    tampered' = false,
    bundleAccepted' = false,
    cacheHitAdmitted' = false,
  }

  action verifyValidBundleAndReuseCache = all {
    signatureValid and not(tampered) and missingReports == 0,
    memoKeyMatches(repoCommit, upstreamIface, policyDigest, attestedCommit, attestedUpstreamIface, attestedPolicyDigest),
    repoCommit' = repoCommit,
    upstreamIface' = upstreamIface,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = signatureValid,
    missingReports' = missingReports,
    tampered' = tampered,
    bundleAccepted' = true,
    cacheHitAdmitted' = true,
  }

  action changeUpstreamInterface = all {
    repoCommit' = repoCommit,
    upstreamIface' = 20,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = signatureValid,
    missingReports' = missingReports,
    tampered' = tampered,
    bundleAccepted' = false,
    cacheHitAdmitted' = false,
  }

  action tamperAttestationDigest = all {
    repoCommit' = repoCommit,
    upstreamIface' = upstreamIface,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = false,
    missingReports' = missingReports,
    tampered' = true,
    bundleAccepted' = false,
    cacheHitAdmitted' = false,
  }

  action recordMissingReport = all {
    repoCommit' = repoCommit,
    upstreamIface' = upstreamIface,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = signatureValid,
    missingReports' = 1,
    tampered' = tampered,
    bundleAccepted' = false,
    cacheHitAdmitted' = false,
  }

  // Negative-control fault 1: admitting a cache hit after upstream ABI changed
  action unsafeAdmitStaleCacheHit = all {
    not(memoKeyMatches(repoCommit, upstreamIface, policyDigest, attestedCommit, attestedUpstreamIface, attestedPolicyDigest)),
    repoCommit' = repoCommit,
    upstreamIface' = upstreamIface,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = signatureValid,
    missingReports' = missingReports,
    tampered' = tampered,
    bundleAccepted' = true,
    cacheHitAdmitted' = true,
  }

  // Negative-control fault 2: accepting a tampered / forged attestation bundle
  action unsafeAcceptTamperedBundle = all {
    tampered or not(signatureValid),
    repoCommit' = repoCommit,
    upstreamIface' = upstreamIface,
    policyDigest' = policyDigest,
    attestedCommit' = attestedCommit,
    attestedUpstreamIface' = attestedUpstreamIface,
    attestedPolicyDigest' = attestedPolicyDigest,
    signatureValid' = signatureValid,
    missingReports' = missingReports,
    tampered' = tampered,
    bundleAccepted' = true,
    cacheHitAdmitted' = false,
  }

  val cacheReuseSound =
    not(cacheHitAdmitted)
      or (signatureValid and not(tampered) and missingReports == 0
          and memoKeyMatches(repoCommit, upstreamIface, policyDigest, attestedCommit, attestedUpstreamIface, attestedPolicyDigest))

  val signatureSound =
    not(bundleAccepted) or (signatureValid and not(tampered) and missingReports == 0)

  run validBundleGrantsSoundCacheHitTest =
    init.then(verifyValidBundleAndReuseCache)
      .expect(bundleAccepted and cacheHitAdmitted and cacheReuseSound and signatureSound)

  run upstreamAbiChangeInvalidatesCacheTest =
    init.then(changeUpstreamInterface)
      .expect(not(cacheHitAdmitted) and cacheReuseSound and signatureSound)

  run tamperRejectsBundleTest =
    init.then(tamperAttestationDigest)
      .expect(not(bundleAccepted) and not(cacheHitAdmitted) and signatureSound)

  run missingReportBlocksAttestationTest =
    init.then(recordMissingReport)
      .expect(not(bundleAccepted) and signatureSound)

  run unsafeStaleCacheViolatesSoundnessTest =
    init.then(changeUpstreamInterface).then(unsafeAdmitStaleCacheHit)
      .expect(not(cacheReuseSound))

  run unsafeTamperAcceptViolatesSignatureTest =
    init.then(tamperAttestationDigest).then(unsafeAcceptTamperedBundle)
      .expect(not(signatureSound))
}
