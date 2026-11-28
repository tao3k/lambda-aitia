// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CommitReviewCurrentness {
  // The cut and the rendered description are fixed in this model.
  type Context = { rules: int, targetRevision: int }
  type State = { current: Context, reviewed: Context, verdict: str }
  var state: State

  pure val original = { rules: 1, targetRevision: 1 }

  action init = state' = {
    current: original, reviewed: original, verdict: "pending",
  }

  action replaceRules = all {
    state.verdict == "pending",
    state' = { ...state, current: { ...state.current, rules: 2 } },
  }

  action advanceTarget = all {
    state.verdict == "pending",
    state' = { ...state, current: { ...state.current, targetRevision: 2 } },
  }

  action reviewAgain = all {
    state.verdict == "pending",
    state' = { ...state, reviewed: state.current },
  }

  action prepare = all {
    state.verdict == "pending",
    state' = { ...state,
      verdict: if (state.reviewed == state.current) "prepared" else "refused" },
  }

  action prepareByProseOnly = all {
    state.verdict == "pending",
    state' = { ...state, verdict: "prepared" },
  }

  val preparationRequiresCurrentReview =
    state.verdict != "prepared" or state.reviewed == state.current

  run oldRulesRefusedTest = init.then(replaceRules).then(prepare)
    .expect(state.verdict == "refused" and preparationRequiresCurrentReview)

  run oldTargetRefusedTest = init.then(advanceTarget).then(prepare)
    .expect(state.verdict == "refused" and preparationRequiresCurrentReview)

  run freshReviewPreparedTest =
    init.then(replaceRules).then(advanceTarget).then(reviewAgain).then(prepare)
    .expect(state.verdict == "prepared" and preparationRequiresCurrentReview)

  run equalProseCannotReplaceReviewTest =
    init.then(advanceTarget).then(prepareByProseOnly)
    .expect(not(preparationRequiresCurrentReview))
}
