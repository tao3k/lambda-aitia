// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0014:
/// Air-Gapped Offline Attestation Auditor (`aitia flow verify-attestation`):
/// Verifier-pinned SysML TufPolicy precedence, complete repo inventory coverage,
/// transitive chain integrity, and zero-authority verdict invariants.
module AirGappedAuditor {
  pure val EXPECTED_REPOS: Set[str] = Set("protocol-base", "ledger-core", "network-mux", "node-runner")

  var verifierMinThreshold: int
  var verifierMinEpoch: int
  var bundleClaimedMinThreshold: int
  var effectiveRootThreshold: int
  var effectiveRootMinEpoch: int
  var lineageChainValid: bool
  var coveredRepos: Set[str]

  var auditVerdict: bool
  var actionAuthorized: bool

  pure def effectivePolicyFloor(verifierFloor: int, _bundleClaim: int): int =
    verifierFloor

  pure def offlineAuditAdmissible(
    vThresh: int,
    vEpoch: int,
    rtThresh: int,
    rtEpoch: int,
    chainOk: bool,
    repos: Set[str]
  ): bool =
    and {
      chainOk,
      rtThresh >= vThresh,
      rtEpoch >= vEpoch,
      EXPECTED_REPOS.subseteq(repos),
    }

  action init = all {
    verifierMinThreshold' = 2,
    verifierMinEpoch' = 5,
    bundleClaimedMinThreshold' = 2,
    effectiveRootThreshold' = 2,
    effectiveRootMinEpoch' = 6,
    lineageChainValid' = true,
    coveredRepos' = EXPECTED_REPOS,
    auditVerdict' = false,
    actionAuthorized' = false,
  }

  action runOfflineAudit(
    bundleSpoofThresh: int,
    rtThresh: int,
    rtEpoch: int,
    chainOk: bool,
    repos: Set[str]
  ): bool = {
    val pinnedThresh = effectivePolicyFloor(verifierMinThreshold, bundleSpoofThresh)
    all {
      bundleClaimedMinThreshold' = bundleSpoofThresh,
      effectiveRootThreshold' = rtThresh,
      effectiveRootMinEpoch' = rtEpoch,
      lineageChainValid' = chainOk,
      coveredRepos' = repos,
      auditVerdict' = offlineAuditAdmissible(
        pinnedThresh, verifierMinEpoch, rtThresh, rtEpoch, chainOk, repos
      ),
      verifierMinThreshold' = verifierMinThreshold,
      verifierMinEpoch' = verifierMinEpoch,
      actionAuthorized' = false,
    }
  }

  /// Negative control: trust the untrusted bundle's claimed threshold instead of verifier-pinned SysML floor.
  action unsafeTrustBundlePolicy(bundleSpoofThresh: int, rtThresh: int): bool = all {
    bundleClaimedMinThreshold' = bundleSpoofThresh,
    effectiveRootThreshold' = rtThresh,
    auditVerdict' = rtThresh >= bundleSpoofThresh,
    verifierMinThreshold' = verifierMinThreshold,
    verifierMinEpoch' = verifierMinEpoch,
    effectiveRootMinEpoch' = effectiveRootMinEpoch,
    lineageChainValid' = lineageChainValid,
    coveredRepos' = coveredRepos,
    actionAuthorized' = false,
  }

  val airGappedAuditorInvariant: bool = and {
    not(actionAuthorized),
    auditVerdict implies offlineAuditAdmissible(
      verifierMinThreshold,
      verifierMinEpoch,
      effectiveRootThreshold,
      effectiveRootMinEpoch,
      lineageChainValid,
      coveredRepos
    ),
  }

  run completeAirGappedAuditPassesTest =
    init
      .then(runOfflineAudit(2, 2, 6, true, EXPECTED_REPOS))
      .expect(auditVerdict and airGappedAuditorInvariant)

  run verifierPinnedPolicyBeatsSpoofedBundleTest =
    init
      .then(runOfflineAudit(1, 1, 6, true, EXPECTED_REPOS))
      .expect(not(auditVerdict) and airGappedAuditorInvariant)

  run missingExpectedRepoRejectedTest =
    init
      .then(runOfflineAudit(2, 2, 6, true, Set("protocol-base", "ledger-core", "network-mux")))
      .expect(not(auditVerdict) and airGappedAuditorInvariant)

  run brokenLineageChainRejectedTest =
    init
      .then(runOfflineAudit(2, 2, 6, false, EXPECTED_REPOS))
      .expect(not(auditVerdict) and airGappedAuditorInvariant)

  run weakenedMinEpochRejectedTest =
    init
      .then(runOfflineAudit(2, 2, 4, true, EXPECTED_REPOS))
      .expect(not(auditVerdict) and airGappedAuditorInvariant)

  run unsafeTrustBundlePolicyViolatesInvariantTest =
    init
      .then(unsafeTrustBundlePolicy(1, 1))
      .expect(not(airGappedAuditorInvariant))
}
