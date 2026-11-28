// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0023:
/// Deterministic Engineering Formal Library Reuse (`upstream-library-reuse`) +
/// Project-Specific Ephemeral AI Overlays (`ephemeral-ai-overlay` with mandatory
/// MR05 @countermodel & Sidecar Vault isolation) + G2 Mechanical Diff-Delta +
/// F3 Guard-Probe + Explicit PendingMethod + N-Version Fail-Closed Disagreement.
module DeterministicEngineeringFormalReview {
  // Model resolution modes:
  //   1 = upstream-library-reuse (general case: pinned DE Quint/Lean libraries)
  //   2 = ephemeral-ai-overlay   (special case: AI-authored overlay over DE library)
  val VALID_MODES: Set[int] = Set(1, 2)

  var modelMode: int
  var resolverPinned: bool
  var countermodelVerified: bool
  var storedInSidecarVault: bool
  var proofClean: bool
  var modelPassed: bool
  var g2Defects: int
  var redundantGuardProbes: int
  var pendingOracles: int
  var coordinatorClaimedAdmit: bool
  var oracleDisagreement: bool
  var reviewAdmitted: bool
  var actionAuthorized: bool

  pure def formalModelAdmissible(
    mode: int,
    pinned: bool,
    cmOk: bool,
    vaultOnly: bool,
    clean: bool,
    passed: bool
  ): bool =
    and {
      VALID_MODES.contains(mode),
      pinned,
      clean,
      passed,
      (mode == 2) implies (cmOk and vaultOnly),
    }

  pure def reviewClosureAdmissible(
    mode: int,
    pinned: bool,
    cmOk: bool,
    vaultOnly: bool,
    clean: bool,
    passed: bool,
    g2: int,
    redundantProbes: int,
    pending: int
  ): bool =
    and {
      formalModelAdmissible(mode, pinned, cmOk, vaultOnly, clean, passed),
      g2 == 0,
      redundantProbes == 0,
      pending == 0,
    }

  action init = all {
    modelMode' = 1,
    resolverPinned' = false,
    countermodelVerified' = false,
    storedInSidecarVault' = true,
    proofClean' = false,
    modelPassed' = false,
    g2Defects' = 1,
    redundantGuardProbes' = 0,
    pendingOracles' = 1,
    coordinatorClaimedAdmit' = false,
    oracleDisagreement' = false,
    reviewAdmitted' = false,
    actionAuthorized' = false,
  }

  action evaluateFormalReview(
    mode: int,
    pinned: bool,
    cmOk: bool,
    vaultOnly: bool,
    clean: bool,
    passed: bool,
    g2: int,
    redundantProbes: int,
    pending: int,
    coordAdmit: bool
  ): bool = {
    val ok = reviewClosureAdmissible(
      mode, pinned, cmOk, vaultOnly, clean, passed, g2, redundantProbes, pending
    )
    all {
      modelMode' = mode,
      resolverPinned' = pinned,
      countermodelVerified' = cmOk,
      storedInSidecarVault' = vaultOnly,
      proofClean' = clean,
      modelPassed' = passed,
      g2Defects' = g2,
      redundantGuardProbes' = redundantProbes,
      pendingOracles' = pending,
      coordinatorClaimedAdmit' = coordAdmit,
      oracleDisagreement' = (coordAdmit and not(ok)),
      reviewAdmitted' = ok,
      actionAuthorized' = false,
    }
  }

  /// Negative control: vacuous ephemeral AI overlay (no @countermodel) admitted anyway.
  action unsafeAdmitVacuousEphemeralOverlay: bool = all {
    modelMode' = 2,
    resolverPinned' = true,
    countermodelVerified' = false,
    storedInSidecarVault' = true,
    proofClean' = true,
    modelPassed' = true,
    g2Defects' = 0,
    redundantGuardProbes' = 0,
    pendingOracles' = 0,
    coordinatorClaimedAdmit' = true,
    oracleDisagreement' = false,
    reviewAdmitted' = true,
    actionAuthorized' = false,
  }

  val invDeFormalReviewSafe: bool = and {
    not(actionAuthorized),
    reviewAdmitted implies reviewClosureAdmissible(
      modelMode,
      resolverPinned,
      countermodelVerified,
      storedInSidecarVault,
      proofClean,
      modelPassed,
      g2Defects,
      redundantGuardProbes,
      pendingOracles
    ),
    oracleDisagreement implies not(reviewAdmitted),
  }

  run upstreamLibraryReuseAdmittedTest =
    init
      .then(evaluateFormalReview(1, true, false, true, true, true, 0, 0, 0, true))
      .expect(reviewAdmitted and not(oracleDisagreement) and invDeFormalReviewSafe)

  run ephemeralOverlayWithCountermodelAdmittedTest =
    init
      .then(evaluateFormalReview(2, true, true, true, true, true, 0, 0, 0, true))
      .expect(reviewAdmitted and not(oracleDisagreement) and invDeFormalReviewSafe)

  run vacuousEphemeralOverlayRejectedTest =
    init
      .then(evaluateFormalReview(2, true, false, true, true, true, 0, 0, 0, true))
      .expect(not(reviewAdmitted) and oracleDisagreement and invDeFormalReviewSafe)

  run g2DefectAndRedundantGuardProbeRejectedTest =
    init
      .then(evaluateFormalReview(1, true, true, true, true, true, 1, 1, 0, false))
      .expect(not(reviewAdmitted) and invDeFormalReviewSafe)

  run pendingOracleNeverSilentlyPassesTest =
    init
      .then(evaluateFormalReview(1, true, true, true, true, true, 0, 0, 1, false))
      .expect(not(reviewAdmitted) and invDeFormalReviewSafe)

  run unsafeVacuousOverlayViolatesInvariantTest =
    init
      .then(unsafeAdmitVacuousEphemeralOverlay)
      .expect(not(invDeFormalReviewSafe))
}
