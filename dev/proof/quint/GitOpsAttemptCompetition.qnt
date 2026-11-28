// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

module GitOpsAttemptCompetition {
  type State = {
    head: int,
    admitted: Set[int],
    consumedGrants: Set[int],
    published: Set[int],
    refused: Set[int],
  }

  var state: State

  action init = state' = {
    head: 0, admitted: Set(), consumedGrants: Set(),
    published: Set(), refused: Set(),
  }

  // Both prepared attempts target the same recorded base, head 0.
  action admit(attempt: int, grant: int): bool = all {
    not(state.admitted.contains(attempt)),
    not(state.refused.contains(attempt)),
    not(state.consumedGrants.contains(grant)),
    state' = {
      ...state,
      admitted: state.admitted.union(Set(attempt)),
      consumedGrants: state.consumedGrants.union(Set(grant)),
    },
  }

  action refuseReplay(attempt: int, grant: int): bool = all {
    not(state.admitted.contains(attempt)),
    state.consumedGrants.contains(grant),
    state' = { ...state, refused: state.refused.union(Set(attempt)) },
  }

  action publish(attempt: int): bool = all {
    state.head == 0,
    state.admitted.contains(attempt),
    state' = { ...state, head: attempt, published: Set(attempt) },
  }

  action refuseStale(attempt: int): bool = all {
    state.head != 0,
    state.admitted.contains(attempt),
    not(state.published.contains(attempt)),
    state' = { ...state, refused: state.refused.union(Set(attempt)) },
  }

  action publishWithoutComparison(attempt: int): bool = all {
    state.admitted.contains(attempt),
    state' = { ...state, head: attempt, published: state.published.union(Set(attempt)) },
  }

  val atMostOnePublication = state.published.size() <= 1

  run firstAttemptWinsTest = init.then(admit(1, 1)).then(admit(2, 2))
    .then(publish(1)).then(refuseStale(2))
    .expect(state.published == Set(1) and state.refused == Set(2))

  run secondAttemptWinsTest = init.then(admit(1, 1)).then(admit(2, 2))
    .then(publish(2)).then(refuseStale(1))
    .expect(state.published == Set(2) and state.refused == Set(1))

  run sharedGrantReplayTest = init.then(admit(1, 1)).then(refuseReplay(2, 1))
    .expect(state.admitted == Set(1) and state.refused == Set(2))

  run missingHeadComparisonTest = init.then(admit(1, 1)).then(admit(2, 2))
    .then(publish(1)).then(publishWithoutComparison(2))
    .expect(not(atMostOnePublication))
}
