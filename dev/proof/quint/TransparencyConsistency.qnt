// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0016:
/// RFC 6962 Append-Only Transparency Log Consistency Proofs (Anti-Equivocation,
/// Anti-Truncation, Split-View Defense, and Zero-Authority Verdict Invariants).
module TransparencyConsistency {
  pure def leafH(v: int): int = 100 + v
  pure def nodeH(l: int, r: int): int = 100000 + l * 500 + r

  pure def root1(a: int): int = leafH(a)
  pure def root2(a: int, b: int): int = nodeH(leafH(a), leafH(b))
  pure def root3(a: int, b: int, c: int): int = nodeH(nodeH(leafH(a), leafH(b)), leafH(c))

  var firstSize: int
  var secondSize: int
  var expectedFirstRoot: int
  var expectedSecondRoot: int
  var recomputedFirstRoot: int
  var recomputedSecondRoot: int
  var appendOnlyVerified: bool
  var actionAuthorized: bool

  pure def consistencyAdmissible(
    m: int,
    n: int,
    expFirst: int,
    expSecond: int,
    recFirst: int,
    recSecond: int
  ): bool =
    and {
      m >= 1,
      m <= n,
      recFirst == expFirst,
      recSecond == expSecond,
    }

  action init = all {
    firstSize' = 2,
    secondSize' = 3,
    expectedFirstRoot' = root2(10, 20),
    expectedSecondRoot' = root3(10, 20, 30),
    recomputedFirstRoot' = 0,
    recomputedSecondRoot' = 0,
    appendOnlyVerified' = false,
    actionAuthorized' = false,
  }

  action verifyConsistency(
    m: int,
    n: int,
    expFirst: int,
    expSecond: int,
    recFirst: int,
    recSecond: int
  ): bool = all {
    firstSize' = m,
    secondSize' = n,
    expectedFirstRoot' = expFirst,
    expectedSecondRoot' = expSecond,
    recomputedFirstRoot' = recFirst,
    recomputedSecondRoot' = recSecond,
    appendOnlyVerified' = consistencyAdmissible(m, n, expFirst, expSecond, recFirst, recSecond),
    actionAuthorized' = false,
  }

  /// Negative control: accept consistency proof while only checking secondRoot (allows history rewrite!).
  action unsafeSkipOldRootCheck(m: int, n: int, expFirst: int, expSecond: int, recFirst: int): bool = all {
    firstSize' = m,
    secondSize' = n,
    expectedFirstRoot' = expFirst,
    expectedSecondRoot' = expSecond,
    recomputedFirstRoot' = recFirst,
    recomputedSecondRoot' = expSecond,
    appendOnlyVerified' = (m >= 1 and m <= n),
    actionAuthorized' = false,
  }

  val transparencyConsistencyInvariant: bool = and {
    not(actionAuthorized),
    appendOnlyVerified implies consistencyAdmissible(
      firstSize,
      secondSize,
      expectedFirstRoot,
      expectedSecondRoot,
      recomputedFirstRoot,
      recomputedSecondRoot
    ),
  }

  run appendOnlyExtensionAcceptedTest =
    init
      .then(verifyConsistency(
        2, 3,
        root2(10, 20), root3(10, 20, 30),
        root2(10, 20), root3(10, 20, 30)
      ))
      .expect(appendOnlyVerified and transparencyConsistencyInvariant)

  run historicalEquivocationRejectedTest =
    init
      .then(verifyConsistency(
        2, 3,
        root2(10, 20), root3(11, 20, 30),
        root2(11, 20), root3(11, 20, 30)
      ))
      .expect(not(appendOnlyVerified) and transparencyConsistencyInvariant)

  run logTruncationRejectedTest =
    init
      .then(verifyConsistency(
        3, 2,
        root3(10, 20, 30), root2(10, 20),
        root3(10, 20, 30), root2(10, 20)
      ))
      .expect(not(appendOnlyVerified) and transparencyConsistencyInvariant)

  run splitViewForkRootRejectedTest =
    init
      .then(verifyConsistency(
        2, 3,
        root2(10, 20), root3(10, 20, 99),
        root2(10, 20), root3(10, 20, 30)
      ))
      .expect(not(appendOnlyVerified) and transparencyConsistencyInvariant)

  run zeroSizeLogRejectedTest =
    init
      .then(verifyConsistency(
        0, 2,
        0, root2(10, 20),
        0, root2(10, 20)
      ))
      .expect(not(appendOnlyVerified) and transparencyConsistencyInvariant)

  run unsafeSkipOldRootCheckViolatesInvariantTest =
    init
      .then(unsafeSkipOldRootCheck(
        2, 3,
        root2(10, 20), root3(11, 20, 30),
        root2(11, 20)
      ))
      .expect(not(transparencyConsistencyInvariant))
}
