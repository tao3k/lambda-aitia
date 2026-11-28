// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0025:
/// Native AI Host External Sidecar CLI Workflow (`aitia sidecar ...`) with
/// Vault-Outside-Repo Confinement, Zero Upstream Pollution, Formal Evidence
/// Closure (`upstream-library-reuse` + `ephemeral-ai-overlay`), and Zero Authority.
module NativeSidecarCliWorkflow {
  var upstreamClean: bool
  var contextCaptured: bool
  var ascentAdmissible: bool
  var formalVerified: bool
  var vaultOutsideRepo: bool
  var vaultArchived: bool
  var actionAuthorized: bool

  pure def archiveAdmissible(
    clean: bool,
    captured: bool,
    admissible: bool,
    formalOk: bool,
    outside: bool
  ): bool =
    and {
      clean,
      captured,
      admissible,
      formalOk,
      outside,
    }

  action init = all {
    upstreamClean' = true,
    contextCaptured' = false,
    ascentAdmissible' = false,
    formalVerified' = false,
    vaultOutsideRepo' = true,
    vaultArchived' = false,
    actionAuthorized' = false,
  }

  action cliCapture(clean: bool): bool = all {
    upstreamClean' = clean,
    contextCaptured' = clean,
    ascentAdmissible' = false,
    formalVerified' = false,
    vaultOutsideRepo' = vaultOutsideRepo,
    vaultArchived' = false,
    actionAuthorized' = false,
  }

  action cliAssessAndVerifyFormal(ascentOk: bool, formalOk: bool): bool = all {
    upstreamClean' = upstreamClean,
    contextCaptured' = contextCaptured,
    ascentAdmissible' = (contextCaptured and ascentOk),
    formalVerified' = (contextCaptured and formalOk),
    vaultOutsideRepo' = vaultOutsideRepo,
    vaultArchived' = false,
    actionAuthorized' = false,
  }

  action cliWriteReceiptToVault(outside: bool): bool = {
    val ok = archiveAdmissible(
      upstreamClean, contextCaptured, ascentAdmissible, formalVerified, outside
    )
    all {
      upstreamClean' = upstreamClean,
      contextCaptured' = contextCaptured,
      ascentAdmissible' = ascentAdmissible,
      formalVerified' = formalVerified,
      vaultOutsideRepo' = outside,
      vaultArchived' = ok,
      actionAuthorized' = false,
    }
  }

  /// Negative control: CLI writes sidecar vault inside the external upstream repo tree.
  action unsafeWriteVaultInsideUpstreamRepo: bool = all {
    upstreamClean' = true,
    contextCaptured' = true,
    ascentAdmissible' = true,
    formalVerified' = true,
    vaultOutsideRepo' = false,
    vaultArchived' = true,
    actionAuthorized' = false,
  }

  val invNativeSidecarCliSafe: bool = and {
    not(actionAuthorized),
    contextCaptured implies upstreamClean,
    vaultArchived implies archiveAdmissible(
      upstreamClean,
      contextCaptured,
      ascentAdmissible,
      formalVerified,
      vaultOutsideRepo
    ),
  }

  run completeNativeCliWorkflowAdmittedTest =
    init
      .then(cliCapture(true))
      .then(cliAssessAndVerifyFormal(true, true))
      .then(cliWriteReceiptToVault(true))
      .expect(vaultArchived and invNativeSidecarCliSafe)

  run pollutedUpstreamBlocksCaptureTest =
    init
      .then(cliCapture(false))
      .expect(not(contextCaptured) and invNativeSidecarCliSafe)

  run vaultInsideUpstreamRepoRefusedTest =
    init
      .then(cliCapture(true))
      .then(cliAssessAndVerifyFormal(true, true))
      .then(cliWriteReceiptToVault(false))
      .expect(not(vaultArchived) and invNativeSidecarCliSafe)

  run unverifiedFormalEvidenceBlocksReceiptTest =
    init
      .then(cliCapture(true))
      .then(cliAssessAndVerifyFormal(true, false))
      .then(cliWriteReceiptToVault(true))
      .expect(not(vaultArchived) and invNativeSidecarCliSafe)

  run openAscentObligationBlocksReceiptTest =
    init
      .then(cliCapture(true))
      .then(cliAssessAndVerifyFormal(false, true))
      .then(cliWriteReceiptToVault(true))
      .expect(not(vaultArchived) and invNativeSidecarCliSafe)

  run unsafeVaultInsideRepoViolatesInvariantTest =
    init
      .then(unsafeWriteVaultInsideUpstreamRepo)
      .expect(not(invNativeSidecarCliSafe))
}
