-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LambdaAitiaProof.Modules.Sdlc.Retirement

/-!
An abstract extension of retirement review with an ingress fence. Requests
and rejections may stutter after retirement; an effect with a current epoch
cannot start there. Finalization requires a closed issuance boundary and an
invalidated cached epoch. No proof of deployed revocation, TLA correspondence,
grant issuance, fairness or persistent state is claimed.
-/

namespace LambdaAitiaProof.Modules.Sdlc.RetirementIngress

structure State where
  review : Retirement.State
  ingressOpen : Bool
  epoch : Nat
  grantEpoch : Nat

def Safe (s : State) : Prop :=
  Retirement.Safe s.review ∧
  (s.review.retired = true → s.ingressOpen = false ∧ s.grantEpoch ≠ s.epoch)

def Initial : State := ⟨Retirement.Initial, true, 0, 0⟩

theorem initialSafe : Safe Initial := by
  constructor
  · exact Retirement.initialSafe
  · intro retired
    cases retired

theorem currentGrantExcludesRetirement {s : State} (safe : Safe s)
    (current : s.grantEpoch = s.epoch) : s.review.retired ≠ true := by
  intro retired
  exact (safe.2 retired).2 current

inductive Step : State → State → Prop where
  | review (s : State) (t : Retirement.State)
      (step : Retirement.Step s.review t) (beforeFinalization : t.retired = false) :
      Step s {s with review := t}
  | close (s : State) (notRetired : s.review.retired = false)
      (wasOpen : s.ingressOpen = true) :
      Step s {s with ingressOpen := false, epoch := s.epoch + 1}
  | finalize (s : State)
      (step : Retirement.Step s.review {s.review with retired := true})
      (closed : s.ingressOpen = false) (revoked : s.grantEpoch ≠ s.epoch) :
      Step s {s with review := {s.review with retired := true}}
  | start (s : State) (current : s.grantEpoch = s.epoch) :
      Step s {s with review := {s.review with active := true}}
  | requestOrReject (s : State) : Step s s

theorem stepPreservesSafety {s t : State} (safe : Safe s)
    (step : Step s t) : Safe t := by
  cases step with
  | review t step beforeFinalization =>
      constructor
      · exact Retirement.stepPreservesSafety safe.1 step
      · intro retired
        have impossible : false = true := beforeFinalization.symm.trans retired
        cases impossible
  | close notRetired wasOpen =>
      constructor
      · exact safe.1
      · intro retired
        have impossible : false = true := notRetired.symm.trans retired
        cases impossible
  | finalize step closed revoked =>
      constructor
      · exact Retirement.stepPreservesSafety safe.1 step
      · intro _
        exact ⟨closed, revoked⟩
  | start current =>
      constructor
      · intro retired
        exact False.elim (currentGrantExcludesRetirement safe current retired)
      · intro retired
        exact False.elim (currentGrantExcludesRetirement safe current retired)
  | requestOrReject => exact safe

inductive Reachable : State → Prop where
  | initial : Reachable Initial
  | next {s t : State} : Reachable s → Step s t → Reachable t

theorem reachableSafe {s : State} (reachable : Reachable s) : Safe s := by
  induction reachable with
  | initial => exact initialSafe
  | next previous step inductionHypothesis =>
      exact stepPreservesSafety inductionHypothesis step

end LambdaAitiaProof.Modules.Sdlc.RetirementIngress
