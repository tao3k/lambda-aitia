// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

module GitOpsWriteRecovery {
  type Phase = Prepared | Admitted | Published | Unknown | Applied | Unapplied | Refused
  type State = {
    phase: Phase,
    head: int,
    grantCurrent: bool,
    publicationCount: int,
    publishedOverExpectedHead: bool,
  }

  var state: State

  action init = state' = {
    phase: Prepared, head: 1, grantCurrent: true,
    publicationCount: 0, publishedOverExpectedHead: false,
  }

  action admit = all {
    state.phase == Prepared and state.grantCurrent,
    state' = { ...state, phase: Admitted },
  }

  action revoke = state' = { ...state, grantCurrent: false }

  action changeHead = all {
    state.publicationCount == 0,
    state' = { ...state, head: 2 },
  }

  action refuse = all {
    (state.phase == Prepared and not(state.grantCurrent)) or
      (state.phase == Admitted and state.head != 1),
    state' = { ...state, phase: Refused },
  }

  action publish = all {
    state.phase == Admitted and state.head == 1,
    state' = {
      ...state, phase: Published, head: 3,
      publicationCount: 1, publishedOverExpectedHead: true,
    },
  }

  action loseAcknowledgement = all {
    state.phase == Admitted or state.phase == Published,
    state' = { ...state, phase: Unknown },
  }

  // Unavailable or ambiguous evidence leaves the attempt unresolved.
  action observationUnavailable = all {
    state.phase == Unknown,
    state' = state,
  }

  // This action represents the arrival of authoritative effect evidence.
  action reconcile = all {
    state.phase == Unknown,
    state' = { ...state, phase: if (state.publicationCount == 1) Applied else Unapplied },
  }

  action publishWithoutFence = all {
    state.phase == Admitted,
    state' = {
      ...state, phase: Published, head: 3,
      publicationCount: 1, publishedOverExpectedHead: state.head == 1,
    },
  }

  val writeRequiresExpectedHead =
    state.publicationCount == 0 or state.publishedOverExpectedHead

  val receiptMatchesPublication = and {
    state.publicationCount <= 1,
    state.phase != Applied or state.publicationCount == 1,
    state.phase != Unapplied or state.publicationCount == 0,
    state.phase != Refused or state.publicationCount == 0,
  }

  action step = any {
    admit, revoke, changeHead, refuse, publish, loseAcknowledgement,
    observationUnavailable, reconcile,
  }

  run withdrawalBeforeAdmissionTest = init.then(revoke).then(refuse)
    .expect(state.phase == Refused and state.publicationCount == 0)

  run withdrawalAfterAdmissionTest = init.then(admit).then(revoke).then(publish)
    .expect(state.phase == Published and writeRequiresExpectedHead)

  run changedHeadRefusalTest = init.then(admit).then(changeHead).then(refuse)
    .expect(state.phase == Refused and state.head == 2 and state.publicationCount == 0)

  run unfencedPublicationTest = init.then(admit).then(changeHead).then(publishWithoutFence)
    .expect(not(writeRequiresExpectedHead))

  run crashBeforePublicationTest = init.then(admit).then(loseAcknowledgement).then(reconcile)
    .expect(state.phase == Unapplied and state.publicationCount == 0)

  run lostReceiptTest = init.then(admit).then(publish).then(loseAcknowledgement)
    .expect(state.phase == Unknown and state.publicationCount == 1)
    .then(reconcile).expect(state.phase == Applied and state.publicationCount == 1)
  run ambiguousReceiptRemainsUnknownTest = init.then(admit).then(publish)
    .then(loseAcknowledgement).then(observationUnavailable)
    .expect(state.phase == Unknown and state.publicationCount == 1)

}
