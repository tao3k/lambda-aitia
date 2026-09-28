-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-!
Design-level retirement safety. `Step.observe` overapproximates every
pre-retirement observation, including late work and inventory loss; safety
cannot rely on an old review. Terminal states admit no further observations.
This is not a proof of TLA/Scheme correspondence, inventory truth, liveness,
post-retirement ingress exclusion, persistence, or effect authorization.
-/

namespace LambdaAitiaProof.Modules.Sdlc.Retirement

structure State where
  active : Bool
  queued : Bool
  known : Bool
  reviewed : Bool
  cancelRequested : Bool
  retired : Bool

def Safe (s : State) : Prop :=
  s.retired = true → s.active = false ∧ s.queued = false ∧ s.known = true

def Initial : State := ⟨true, true, false, false, false, false⟩

inductive Step : State → State → Prop where
  | observe (s t : State) (before : s.retired = false)
      (after : t.retired = false) : Step s t
  | finalize (s : State) (before : s.retired = false)
      (review : s.reviewed = true) (idle : s.active = false)
      (drained : s.queued = false) (inventory : s.known = true) :
      Step s { s with retired := true }
  | terminal (s : State) (done : s.retired = true) : Step s s

theorem initialSafe : Safe Initial := by
  intro done
  cases done

theorem stepPreservesSafety {s t : State} (safe : Safe s)
    (step : Step s t) : Safe t := by
  cases step with
  | observe t before after =>
      intro done
      have impossible : false = true := after.symm.trans done
      cases impossible
  | finalize before review idle drained inventory =>
      intro _
      exact ⟨idle, drained, inventory⟩
  | terminal done => exact safe

inductive Reachable : State → Prop where
  | initial : Reachable Initial
  | next {s t : State} : Reachable s → Step s t → Reachable t

theorem reachableSafe {s : State} (reachable : Reachable s) : Safe s := by
  induction reachable with
  | initial => exact initialSafe
  | next previous step inductionHypothesis =>
      exact stepPreservesSafety inductionHypothesis step

def CancellationOnly : State := ⟨true, true, true, false, true, true⟩
def StaleReview : State := ⟨true, false, true, true, false, true⟩
def UnknownInventory : State := ⟨false, false, false, true, false, true⟩

theorem cancellationDoesNotJustifyRetirement : ¬ Safe CancellationOnly := by
  intro safe
  have impossible := (safe rfl).1
  cases impossible

theorem oldReviewDoesNotJustifyRetirement : ¬ Safe StaleReview := by
  intro safe
  have impossible := (safe rfl).1
  cases impossible

theorem unknownInventoryBlocksRetirement : ¬ Safe UnknownInventory := by
  intro safe
  have impossible := (safe rfl).2.2
  cases impossible

end LambdaAitiaProof.Modules.Sdlc.Retirement
