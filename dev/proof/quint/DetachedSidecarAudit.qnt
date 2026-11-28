// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0021:
/// Detached Sidecar Governance for Uninitialized External Repositories,
/// Multi-Lens AI Audit Context Freshness, SWE-146 Provenance & Conversation Binding,
/// Human Disposition of Critical/High Findings, and Zero-Authority Invariants.
module DetachedSidecarAudit {
  var upstreamPollutionFree: bool
  var currentContext: int
  var aiAuditContext: int
  var requiredLensesCovered: bool
  var swe146ProvenanceValid: bool
  var conversationBound: bool
  var unaddressedHighFindings: int
  var humanApproved: bool
  var sidecarReceiptAdmitted: bool
  var actionAuthorized: bool

  pure def sidecarAdmissible(
    cleanUpstream: bool,
    curCtx: int,
    aiCtx: int,
    lensesOk: bool,
    provOk: bool,
    convOk: bool,
    unaddressedHigh: int,
    humanOk: bool
  ): bool =
    and {
      cleanUpstream,
      curCtx == aiCtx,
      lensesOk,
      provOk,
      convOk,
      unaddressedHigh == 0,
      humanOk,
    }

  action init = all {
    upstreamPollutionFree' = true,
    currentContext' = 1,
    aiAuditContext' = 1,
    requiredLensesCovered' = false,
    swe146ProvenanceValid' = false,
    conversationBound' = false,
    unaddressedHighFindings' = 0,
    humanApproved' = false,
    sidecarReceiptAdmitted' = false,
    actionAuthorized' = false,
  }

  action evaluateSidecar(
    cleanUpstream: bool,
    curCtx: int,
    aiCtx: int,
    lensesOk: bool,
    provOk: bool,
    convOk: bool,
    unaddressedHigh: int,
    humanOk: bool
  ): bool = all {
    upstreamPollutionFree' = cleanUpstream,
    currentContext' = curCtx,
    aiAuditContext' = aiCtx,
    requiredLensesCovered' = lensesOk,
    swe146ProvenanceValid' = provOk,
    conversationBound' = convOk,
    unaddressedHighFindings' = unaddressedHigh,
    humanApproved' = humanOk,
    sidecarReceiptAdmitted' = sidecarAdmissible(
      cleanUpstream, curCtx, aiCtx, lensesOk, provOk, convOk, unaddressedHigh, humanOk
    ),
    actionAuthorized' = false,
  }

  /// Negative control: allow AI self-approval without independent human decision.
  action unsafeAiSelfApproval(curCtx: int): bool = all {
    upstreamPollutionFree' = true,
    currentContext' = curCtx,
    aiAuditContext' = curCtx,
    requiredLensesCovered' = true,
    swe146ProvenanceValid' = true,
    conversationBound' = true,
    unaddressedHighFindings' = 0,
    humanApproved' = false,
    sidecarReceiptAdmitted' = true,
    actionAuthorized' = false,
  }

  val invDetachedSidecarSafe: bool = and {
    not(actionAuthorized),
    sidecarReceiptAdmitted implies sidecarAdmissible(
      upstreamPollutionFree,
      currentContext,
      aiAuditContext,
      requiredLensesCovered,
      swe146ProvenanceValid,
      conversationBound,
      unaddressedHighFindings,
      humanApproved
    ),
  }

  run validDetachedSidecarCommitAcceptedTest =
    init
      .then(evaluateSidecar(true, 10, 10, true, true, true, 0, true))
      .expect(sidecarReceiptAdmitted and invDetachedSidecarSafe)

  run upstreamPollutionRejectedTest =
    init
      .then(evaluateSidecar(false, 10, 10, true, true, true, 0, true))
      .expect(not(sidecarReceiptAdmitted) and invDetachedSidecarSafe)

  run staleAiAuditRejectedTest =
    init
      .then(evaluateSidecar(true, 11, 10, true, true, true, 0, true))
      .expect(not(sidecarReceiptAdmitted) and invDetachedSidecarSafe)

  run unaddressedCriticalFindingRejectedTest =
    init
      .then(evaluateSidecar(true, 10, 10, true, true, true, 1, true))
      .expect(not(sidecarReceiptAdmitted) and invDetachedSidecarSafe)

  run missingConversationOrProvenanceRejectedTest =
    init
      .then(evaluateSidecar(true, 10, 10, true, false, true, 0, true))
      .expect(not(sidecarReceiptAdmitted) and invDetachedSidecarSafe)

  run unsafeAiSelfApprovalViolatesInvariantTest =
    init
      .then(unsafeAiSelfApproval(10))
      .expect(not(invDetachedSidecarSafe))
}
