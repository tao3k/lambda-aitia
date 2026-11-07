// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module AssuranceLifecycle {
  import EffectAdmission.* from "./EffectAdmission"

  // One obligation, two source revisions, four clock values, three epochs.
  type Lifecycle = {revision: int, planned: int, verified: int, admitted: int,
    decided: int, granted: int, grantEpoch: int, epoch: int, clock: int,
    sealUntil: int, grantUntil: int, adapterInstalled: bool,
    reportedSuccess: bool, effectStarted: bool, startSafe: bool,
    reservationRevision: int, reservationEpoch: int, reservationUntil: int,
    deliveryStatus: int, deliveryCalls: int, deliverySafe: bool}
  var q: Lifecycle
  pure val Initial = {revision: 1, planned: 0, verified: 0, admitted: 0,
    decided: 0, granted: 0, grantEpoch: 0, epoch: 0, clock: 0,
    sealUntil: 0, grantUntil: 0, adapterInstalled: false,
    reportedSuccess: false, effectStarted: false, startSafe: true,
    reservationRevision: 0, reservationEpoch: 0, reservationUntil: 0,
    deliveryStatus: 0, deliveryCalls: 0, deliverySafe: true}
  action init = q' = Initial
  action InstallAdapter = all {not(q.adapterInstalled), q' = {...q, adapterInstalled: true}}
  action ReportSuccess = all {not(q.reportedSuccess), q' = {...q, reportedSuccess: true}}
  action Plan = all {q.planned != q.revision, q' = {...q, planned: q.revision}}
  action Verify = all {q.adapterInstalled, q.planned == q.revision, q.clock < 3,
    q' = {...q, verified: q.revision, sealUntil: q.clock + 1}}
  action Admit = all {q.verified == q.revision, q.clock < q.sealUntil,
    q.admitted != q.revision, q' = {...q, admitted: q.revision}}
  action Decide = all {q.admitted == q.revision, q.decided != q.revision,
    q' = {...q, decided: q.revision}}
  action Authorize = all {q.decided == q.revision, q.admitted == q.revision,
    q.granted != q.revision, q.clock < 3,
    q' = {...q, granted: q.revision, grantEpoch: q.epoch, grantUntil: q.clock + 1}}
  val Current = currentGrant(q.granted, q.revision, q.admitted, q.decided,
    q.grantEpoch, q.epoch, q.clock, q.grantUntil)
  action StartEffect = all {not(q.effectStarted), Current,
    q' = {...q, effectStarted: true,
      reservationRevision: q.revision, reservationEpoch: q.grantEpoch,
      reservationUntil: q.grantUntil,
      startSafe: currentGrant(q.granted, q.revision, q.admitted, q.decided,
        q.grantEpoch, q.epoch, q.clock, q.grantUntil)}}
  // Start is a one-shot reservation, not delivery or an acknowledgement.
  val DeliveryCurrent = Current and q.reservationRevision == q.revision and
    q.reservationEpoch == q.epoch and q.clock < q.reservationUntil
  // 0 = pending/not-started, 1 = acknowledged, 2 = rejected, 3 = failed,
  // 4 = unknown acknowledgement. Unknown never authorizes a blind retry.
  action DeliverEffect = all {q.effectStarted, q.deliveryStatus == 0, DeliveryCurrent,
    q' = {...q, deliveryStatus: 1, deliveryCalls: q.deliveryCalls + 1, deliverySafe: true}}
  action RejectDelivery = all {q.effectStarted, q.deliveryStatus == 0, not(DeliveryCurrent),
    q' = {...q, deliveryStatus: 2}}
  action FailDelivery = all {q.effectStarted, q.deliveryStatus == 0, DeliveryCurrent,
    q' = {...q, deliveryStatus: 3, deliveryCalls: q.deliveryCalls + 1}}
  action UnknownDelivery = all {q.effectStarted, q.deliveryStatus == 0, DeliveryCurrent,
    q' = {...q, deliveryStatus: 4, deliveryCalls: q.deliveryCalls + 1}}
  action ChangeSource = all {q.revision == 1,
    q' = {...q, revision: 2, planned: 0, verified: 0, admitted: 0,
      decided: 0, granted: 0, sealUntil: 0, grantUntil: 0}}
  action Tick = all {q.clock < 3,
    q' = {...q, clock: q.clock + 1,
      admitted: if (q.clock + 1 < q.sealUntil) q.admitted else 0,
      decided: if (q.clock + 1 < q.sealUntil) q.decided else 0,
      granted: if (q.clock + 1 < q.sealUntil and q.clock + 1 < q.grantUntil)
        q.granted else 0}}
  action Revoke = all {q.epoch < 2,
    q' = {...q, epoch: q.epoch + 1, verified: 0, admitted: 0,
      decided: 0, granted: 0, sealUntil: 0}}
  action stableStep = any {InstallAdapter, ReportSuccess, Plan, Verify, Admit,
    Decide, Authorize, StartEffect, DeliverEffect}
  action Terminal = all {q.clock == 3, q.epoch == 2, q.revision == 2,
    q.adapterInstalled, q.reportedSuccess, q.planned == q.revision,
    (not(q.effectStarted) or q.deliveryStatus != 0), q' = q}
  action step = any {stableStep, ChangeSource, Tick, Revoke, RejectDelivery,
    FailDelivery, UnknownDelivery, Terminal}

  // Each mutation is isolated by selecting its own step operator.
  action UnsafeStart = all {q.reportedSuccess, not(q.effectStarted),
    q' = {...q, effectStarted: true, startSafe: Current}}
  action UnsafeLateAdmit = all {q.revision == 2, q.reportedSuccess,
    q.admitted == 0, q' = {...q, admitted: 1}}
  action UnsafeEarlyGrant = all {q.revision == 2, q.reportedSuccess,
    q.admitted == 0, q.granted == 0, q.clock < 3,
    q' = {...q, granted: q.revision, grantEpoch: q.epoch,
      grantUntil: q.clock + 1}}
  action UnsafeAfterRevoke = all {q.epoch > q.grantEpoch,
    q.grantUntil > q.clock, q.granted == 0, not(q.effectStarted),
    q' = {...q, effectStarted: true, startSafe: Current}}
  action unsafeStep = any {step, UnsafeStart}
  action lateAdmitStep = any {step, UnsafeLateAdmit}
  action earlyGrantStep = any {step, UnsafeEarlyGrant}
  action afterRevokeStep = any {step, UnsafeAfterRevoke}
  action UnsafeDelivery = all {q.effectStarted, q.deliveryStatus == 0, not(DeliveryCurrent),
    q' = {...q, deliveryStatus: 1, deliveryCalls: q.deliveryCalls + 1, deliverySafe: false}}
  action UnsafeBeforeStart = all {q.reportedSuccess, not(q.effectStarted),
    q' = {...q, deliveryStatus: 1, deliveryCalls: q.deliveryCalls + 1, deliverySafe: false}}
  action UnsafeReplay = all {q.deliveryStatus == 1,
    q' = {...q, deliveryCalls: q.deliveryCalls + 1}}
  action unsafeDeliveryStep = any {step, UnsafeDelivery}
  action beforeStartStep = any {step, UnsafeBeforeStart}
  action replayStep = any {step, UnsafeReplay}

  val TypeOK = q.revision >= 1 and q.revision <= 2 and
    q.planned >= 0 and q.planned <= 2 and q.verified >= 0 and q.verified <= 2 and
    q.admitted >= 0 and q.admitted <= 2 and q.decided >= 0 and q.decided <= 2 and
    q.granted >= 0 and q.granted <= 2 and q.grantEpoch >= 0 and q.grantEpoch <= 2 and
    q.epoch >= 0 and q.epoch <= 2 and q.clock >= 0 and q.clock <= 3 and
    q.sealUntil >= 0 and q.sealUntil <= 4 and q.grantUntil >= 0 and q.grantUntil <= 4 and
    q.reservationRevision >= 0 and q.reservationRevision <= 2 and
    q.reservationEpoch >= 0 and q.reservationEpoch <= 2 and
    q.reservationUntil >= 0 and q.reservationUntil <= 4 and
    q.deliveryStatus >= 0 and q.deliveryStatus <= 4 and q.deliveryCalls >= 0 and q.deliveryCalls <= 1
  val AdmissionIsCurrent = q.admitted == 0 or
    (q.admitted == q.revision and q.verified == q.revision and q.clock < q.sealUntil)
  val DecisionRequiresAdmission = q.decided == 0 or
    (q.decided == q.revision and q.admitted == q.revision)
  val GrantRequiresCurrentDecision = q.granted == 0 or
    (q.granted == q.revision and q.decided == q.revision and
      q.admitted == q.revision and q.grantEpoch == q.epoch and q.clock < q.grantUntil)
  val NoUnsafeEffectStart = q.startSafe
  val NoEffectStarted = not(q.effectStarted)
  val NoUnsafeDelivery = q.deliverySafe
  val DeliveryRequiresStart = q.deliveryCalls == 0 or q.effectStarted
  val AtMostOneDelivery = q.deliveryCalls <= 1

  temporal stableFairness = InstallAdapter.weakFair(q) and Plan.weakFair(q) and
    Verify.weakFair(q) and Admit.weakFair(q) and Decide.weakFair(q) and
    Authorize.weakFair(q) and StartEffect.weakFair(q) and DeliverEffect.weakFair(q)
  temporal stableSpec = q == Initial and stableStep.orKeep(q).always() and stableFairness
  temporal stableSpecNoFair = q == Initial and stableStep.orKeep(q).always()
  temporal EventuallyEffect = q.effectStarted.eventually()
  temporal EventuallyDelivery = (q.deliveryStatus == 1).eventually()
}
