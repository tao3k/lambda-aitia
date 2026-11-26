-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

namespace LambdaAitiaProof.Modules.GitOps

/-- A successful publication compares the current head and installs a distinct operation. -/
def Publishes (expected before after : Nat) : Prop :=
  before = expected ∧ after ≠ before

/-- A successful admission takes a current, unused grant and marks it consumed. -/
def Admits (current : Bool) (before after : Bool) : Prop :=
  current = true ∧ before = false ∧ after = true

theorem sameExpectedHeadCannotPublishTwice
    {expected before middle after : Nat}
    (first : Publishes expected before middle) :
    ¬ Publishes expected middle after := by
  intro second
  exact first.2 (second.1.trans first.1.symm)

theorem consumedGrantCannotBeAdmittedAgain
    {current nextCurrent before middle after : Bool}
    (first : Admits current before middle) :
    ¬ Admits nextCurrent middle after := by
  intro second
  cases first.2.2.symm.trans second.2.1

theorem withdrawnGrantCannotBeAdmitted {before after : Bool} :
    ¬ Admits false before after := by
  intro admission
  cases admission.1

/-- Bazel Skyframe two-level Early Cutoff: upstream commit advanced, interface digest unchanged. -/
def EarlyCutoff (expectedCommit actualCommit expectedIface actualIface : Nat) : Prop :=
  expectedCommit ≠ actualCommit ∧ expectedIface = actualIface

/-- Bazel Bzlmod / IOHK CHaP transitive diamond coherence between two peer pins on a shared ancestor. -/
def DiamondCoherent (pinLeft pinRight : Nat) : Prop :=
  pinLeft = pinRight

/-- Wave dependency barrier: downstream fenced effects require upstream quiescence. -/
def DownstreamEffectAllowed (upstreamQuiescent : Bool) : Prop :=
  upstreamQuiescent = true

theorem earlyCutoffRequiresUnchangedInterface
    {expectedCommit actualCommit expectedIface actualIface : Nat}
    (h : EarlyCutoff expectedCommit actualCommit expectedIface actualIface) :
    expectedIface = actualIface :=
  h.2

theorem interfaceChangePreventsEarlyCutoff
    {expectedCommit actualCommit expectedIface actualIface : Nat}
    (hDiff : expectedIface ≠ actualIface) :
    ¬ EarlyCutoff expectedCommit actualCommit expectedIface actualIface := by
  intro hCutoff
  exact hDiff hCutoff.2

theorem diamondConflictBlocksConsumerClosure
    {pinLeft pinRight : Nat}
    (hConflict : pinLeft ≠ pinRight) :
    ¬ DiamondCoherent pinLeft pinRight := by
  intro hCoherent
  exact hConflict hCoherent

theorem waveBarrierPreventsPrematureDownstreamEffect :
    ¬ DownstreamEffectAllowed false := by
  intro hAllowed
  cases hAllowed

end LambdaAitiaProof.Modules.GitOps
