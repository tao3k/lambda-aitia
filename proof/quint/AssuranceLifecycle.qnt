// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module AssuranceLifecycle {
  import EffectAdmission.* from "./EffectAdmission"

  // One obligation, two source revisions, four clock values, three epochs.
  type Lifecycle = {revision: int, planned: int, verified: int, admitted: int,
    decided: int, granted: int, grantEpoch: int, epoch: int, clock: int,
    sealUntil: int, grantUntil: int, adapterInstalled: bool,
    reportedSuccess: bool, effectStarted: bool, startSafe: bool}
  var q: Lifecycle
  pure val Initial = {revision: 1, planned: 0, verified: 0, admitted: 0,
    decided: 0, granted: 0, grantEpoch: 0, epoch: 0, clock: 0,
    sealUntil: 0, grantUntil: 0, adapterInstalled: false,
    reportedSuccess: false, effectStarted: false, startSafe: true}
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
      startSafe: currentGrant(q.granted, q.revision, q.admitted, q.decided,
        q.grantEpoch, q.epoch, q.clock, q.grantUntil)}}
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
    Decide, Authorize, StartEffect}
  action step = any {stableStep, ChangeSource, Tick, Revoke}

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

  val TypeOK = q.revision >= 1 and q.revision <= 2 and
    q.planned >= 0 and q.planned <= 2 and q.verified >= 0 and q.verified <= 2 and
    q.admitted >= 0 and q.admitted <= 2 and q.decided >= 0 and q.decided <= 2 and
    q.granted >= 0 and q.granted <= 2 and q.grantEpoch >= 0 and q.grantEpoch <= 2 and
    q.epoch >= 0 and q.epoch <= 2 and q.clock >= 0 and q.clock <= 3 and
    q.sealUntil >= 0 and q.sealUntil <= 4 and q.grantUntil >= 0 and q.grantUntil <= 4
  val AdmissionIsCurrent = q.admitted == 0 or
    (q.admitted == q.revision and q.verified == q.revision and q.clock < q.sealUntil)
  val DecisionRequiresAdmission = q.decided == 0 or
    (q.decided == q.revision and q.admitted == q.revision)
  val GrantRequiresCurrentDecision = q.granted == 0 or
    (q.granted == q.revision and q.decided == q.revision and
      q.admitted == q.revision and q.grantEpoch == q.epoch and q.clock < q.grantUntil)
  val NoUnsafeEffectStart = q.startSafe
  val NoEffectStarted = not(q.effectStarted)

  temporal stableFairness = InstallAdapter.weakFair(q) and Plan.weakFair(q) and
    Verify.weakFair(q) and Admit.weakFair(q) and Decide.weakFair(q) and
    Authorize.weakFair(q) and StartEffect.weakFair(q)
  temporal stableSpec = q == Initial and stableStep.orKeep(q).always() and stableFairness
  temporal stableSpecNoFair = q == Initial and stableStep.orKeep(q).always()
  temporal EventuallyEffect = q.effectStarted.eventually()
}
