// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RetirementReview {
  import WorkCore.* from "./WorkCore"

  type Review = {work: Work, known: bool, reviewed: bool, retired: bool,
    lateFound: bool, gapFound: bool}
  var q: Review
  action init = q' = {work: {active: true, queued: true, cancelRequested: false},
    known: false, reviewed: false, retired: false, lateFound: false, gapFound: false}

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
  action Retire = all {not(q.retired), q.reviewed, quiescent(q.work), q.known,
    q' = {...q, retired: true}}
  action TrustCancellation = all {not(q.retired), q.work.cancelRequested, q.known,
    q' = {...q, retired: true}}
  action TrustOldReview = all {not(q.retired), q.reviewed, q.known,
    q' = {...q, retired: true}}
  action IgnoreInventoryGap = all {not(q.retired), q.reviewed, quiescent(q.work),
    q' = {...q, retired: true}}
  action Terminal = all {q.retired, q' = q}
  action step = any {Observe, Retire, Terminal}
  action cancellationStep = any {Observe, TrustCancellation, Terminal}
  action staleStep = any {Observe, TrustOldReview, Terminal}
  action unknownStep = any {Observe, IgnoreInventoryGap, Terminal}

  val TypeOK = true
  val NoOutstandingWork = q.retired implies quiescent(q.work)
  val InventoryKnown = q.retired implies q.known
  val NeverRetired = not(q.retired)
}
