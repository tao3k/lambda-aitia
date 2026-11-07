// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CommitEvidence {
  type Cut = { change: int, commit: int, tree: int, operation: int }
  pure val original = { change: 1, commit: 1, tree: 1, operation: 1 }
  pure val rewritten = { change: 1, commit: 2, tree: 2, operation: 2 }
  var cut: Cut
  var supported: Cut
  var open: bool

  action init = all {
    cut' = original,
    supported' = original,
    open' = false,
  }

  action rewrite = all {
    cut == original,
    cut' = rewritten,
    supported' = supported,
    open' = true,
  }

  action observeCurrent = all {
    open,
    cut' = cut,
    supported' = cut,
    open' = false,
  }

  action reuseByChangeId = all {
    open and cut.change == supported.change,
    cut' = cut,
    supported' = supported,
    open' = false,
  }

  val currentSupportRequired = open or cut == supported

  run rewriteReopensTest = init.then(rewrite)
    .expect(open and supported == original and cut.change == supported.change)
  run currentObservationClosesTest = init.then(rewrite).then(observeCurrent)
    .expect(not(open) and currentSupportRequired)
  run reuseByChangeIdViolatesTest = init.then(rewrite).then(reuseByChangeId)
    .expect(not(currentSupportRequired))
}
