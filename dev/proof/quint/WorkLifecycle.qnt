// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module WorkLifecycle {
  import WorkCore.* from "./WorkCore"
  // Cancellation is a request, never an observation of completion.
  var q: Work
  action init = q' = {active: true, queued: true, cancelRequested: false}
  action RequestCancellation = all {not(q.cancelRequested), q' = cancel(q)}
  action ObserveCompletion = all {q.active, q' = complete(q)}
  action ObserveQueueDrained = all {q.queued, q' = drain(q)}
  action Terminal = all {quiescent(q), q.cancelRequested, q' = q}
  action step = any {RequestCancellation, ObserveCompletion, ObserveQueueDrained, Terminal}
  action cancellationStep = any {RequestCancellation, all {q.cancelRequested, q' = q}}
  val TypeOK = true
  val WorkRemains = q.active and q.queued
  val NeverCancelled = not(q.cancelRequested)
  val NeverQuiescent = not(quiescent(q))
}
