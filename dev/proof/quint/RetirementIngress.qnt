// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RetirementIngress {
  import WorkCore.* from "./WorkCore"
  import EffectAdmission.* from "./EffectAdmission"

  type Ingress = {work: Work, known: bool, reviewed: bool, retired: bool,
    lateFound: bool, gapFound: bool, ingressOpen: bool, epoch: int,
    grantEpoch: int, pending: bool, attempted: bool,
    rejectedAfterRetirement: bool, startedAfterRetirement: bool}
  var q: Ingress
  action init = q' = {work: {active: true, queued: true, cancelRequested: false},
    known: false, reviewed: false, retired: false, lateFound: false, gapFound: false,
    ingressOpen: true, epoch: 0, grantEpoch: 0, pending: false, attempted: false,
    rejectedAfterRetirement: false, startedAfterRetirement: false}

  action RequestCancellation = all {not(q.retired), not(q.work.cancelRequested),
    q' = {...q, work: cancel(q.work)}}
  action ObserveCompletion = all {not(q.retired), q.work.active,
    q' = {...q, work: complete(q.work)}}
  action ObserveQueueDrained = all {not(q.retired), q.work.queued,
    q' = {...q, work: drain(q.work)}}
  action CompleteInventory = all {not(q.retired), not(q.known), q' = {...q, known: true}}
  action ReviewCut = all {not(q.retired), not(q.reviewed), quiescent(q.work), q.known,
    q' = {...q, reviewed: true}}
  action ObserveLateActivity = all {not(q.retired), q.reviewed, not(q.lateFound),
    q' = {...q, work: {...q.work, active: true}, lateFound: true}}
  action ObserveInventoryGap = all {not(q.retired), q.reviewed, not(q.gapFound),
    q' = {...q, known: false, gapFound: true}}
  action Observe = any {RequestCancellation, ObserveCompletion, ObserveQueueDrained,
    CompleteInventory, ReviewCut, ObserveLateActivity, ObserveInventoryGap}
  action CloseIngress = all {q.ingressOpen, q' = {...q, ingressOpen: false, epoch: q.epoch + 1}}
  action Request = all {not(q.pending), not(q.attempted), q' = {...q, pending: true}}
  val Current = currentGrant(1, 1, 1, 1, q.grantEpoch, q.epoch, 0, 1)
  action Start = all {q.pending, Current,
    q' = {...q, work: {...q.work, active: true}, pending: false, attempted: true,
      startedAfterRetirement: q.retired}}
  action TrustCachedGrant = all {q.pending,
    q' = {...q, work: {...q.work, active: true}, pending: false, attempted: true,
      startedAfterRetirement: q.retired}}
  action Reject = all {q.pending, not(Current),
    q' = {...q, pending: false, attempted: true, rejectedAfterRetirement: q.retired}}
  action Retire = all {not(q.ingressOpen), not(q.retired), q.reviewed,
    quiescent(q.work), q.known, q' = {...q, retired: true}}
  action RetireWithoutFence = all {not(q.retired), q.reviewed,
    quiescent(q.work), q.known, q' = {...q, retired: true}}
  action Terminal = all {q.retired, q.attempted, q' = q}
  action Environment = any {Observe, CloseIngress, Request, Reject, Terminal}
  action step = any {Environment, Start, Retire}
  action unfencedStep = any {Environment, Start, RetireWithoutFence}
  action cachedGrantStep = any {Environment, TrustCachedGrant, Retire}

  val TypeOK = q.epoch >= 0 and q.epoch <= 1 and q.grantEpoch == 0
  val RetiredIsFenced = q.retired implies (not(q.ingressOpen) and q.grantEpoch != q.epoch)
  val NoPostRetirementStart = not(q.startedAfterRetirement)
  val NoOutstandingWork = q.retired implies quiescent(q.work)
  val InventoryKnown = q.retired implies q.known
  val NeverRejectAfterRetirement = not(q.rejectedAfterRetirement)
  val NeverStarted = not(q.attempted and not(q.rejectedAfterRetirement) and q.epoch == 0)
}
