// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0022:
/// Native Scheme/POO gerbil-ascent Sidecar Obligation Derivation ->
/// Dual-Mode Sanctioned AI Handoff (`native-ai-environment` / `marlin-agent-core`) ->
/// Rust Cryptographic Receipt Closure with Zero-Authority Invariants.
module SchemeAscentMarlinBridge {
  val SANCTIONED_ENGINES: Set[int] = Set(1, 2) // 1 = native-ai-environment, 2 = marlin-agent-core

  var missingLensCount: int
  var usedEngines: Set[int]
  var ascentBlockers: int
  var marlinHandoffEmitted: bool
  var rustReceiptPromoted: bool
  var actionAuthorized: bool

  pure def enginesSanctioned(engines: Set[int]): bool =
    size(engines.exclude(SANCTIONED_ENGINES)) == 0

  pure def closureAdmissible(missing: int, engines: Set[int], blockers: int): bool =
    and {
      missing == 0,
      size(engines) >= 1,
      enginesSanctioned(engines),
      blockers == 0,
    }

  action init = all {
    missingLensCount' = 4,
    usedEngines' = Set(),
    ascentBlockers' = 2,
    marlinHandoffEmitted' = true,
    rustReceiptPromoted' = false,
    actionAuthorized' = false,
  }

  action evaluateSchemeAscent(missing: int, engines: Set[int], blockers: int): bool = all {
    missingLensCount' = missing,
    usedEngines' = engines,
    ascentBlockers' = blockers,
    marlinHandoffEmitted' = (missing > 0 or blockers > 0),
    rustReceiptPromoted' = closureAdmissible(missing, engines, blockers),
    actionAuthorized' = false,
  }

  /// Negative control: Rust/Marlin promotes sidecar receipt while Scheme ASCENT still reports blockers.
  action unsafeBypassAscentBlockers(engines: Set[int]): bool = all {
    missingLensCount' = 1,
    usedEngines' = engines,
    ascentBlockers' = 1,
    marlinHandoffEmitted' = false,
    rustReceiptPromoted' = true,
    actionAuthorized' = false,
  }

  val invSchemeAscentBridgeSafe: bool = and {
    not(actionAuthorized),
    rustReceiptPromoted implies closureAdmissible(
      missingLensCount,
      usedEngines,
      ascentBlockers
    ),
  }

  run dualModeSanctionedClosureAcceptedTest =
    init
      .then(evaluateSchemeAscent(0, Set(1, 2), 0))
      .expect(rustReceiptPromoted and not(marlinHandoffEmitted) and invSchemeAscentBridgeSafe)

  run nativeOnlyClosureAcceptedTest =
    init
      .then(evaluateSchemeAscent(0, Set(1), 0))
      .expect(rustReceiptPromoted and invSchemeAscentBridgeSafe)

  run missingLensEmitsMarlinHandoffAndBlocksReceiptTest =
    init
      .then(evaluateSchemeAscent(2, Set(1), 1))
      .expect(not(rustReceiptPromoted) and marlinHandoffEmitted and invSchemeAscentBridgeSafe)

  run unsanctionedCliEngineRejectedTest =
    init
      .then(evaluateSchemeAscent(0, Set(1, 99), 0))
      .expect(not(rustReceiptPromoted) and invSchemeAscentBridgeSafe)

  run openAscentBlockerBlocksPromotionTest =
    init
      .then(evaluateSchemeAscent(0, Set(1, 2), 1))
      .expect(not(rustReceiptPromoted) and invSchemeAscentBridgeSafe)

  run unsafeBypassAscentBlockersViolatesInvariantTest =
    init
      .then(unsafeBypassAscentBlockers(Set(2)))
      .expect(not(invSchemeAscentBridgeSafe))
}
