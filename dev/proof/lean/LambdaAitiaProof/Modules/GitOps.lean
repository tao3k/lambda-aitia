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

/-- Multi-repo Saga partial-wave barrier: consumer publish requires both concurrent peers. -/
def WaveConsumerCanPublish (peerLeftReady peerRightReady : Bool) : Prop :=
  peerLeftReady = true ∧ peerRightReady = true

/-- Durable checkpoint at-most-once publication guard. -/
def CheckpointAllowsPublish (alreadyPublished : Bool) : Prop :=
  alreadyPublished = false

/-- Signed human decision replay guard over applied decision IDs. -/
def FreshDecision (decisionId : Nat) (applied : List Nat) : Prop :=
  decisionId ∉ applied

theorem partialWaveBlocksConsumerPublish :
    ¬ WaveConsumerCanPublish true false := by
  intro h
  cases h.2

theorem checkpointPreventsDuplicatePublish :
    ¬ CheckpointAllowsPublish true := by
  intro h
  cases h

theorem appliedDecisionCannotReplay
    {decisionId : Nat} {applied : List Nat}
    (hMem : decisionId ∈ applied) :
    ¬ FreshDecision decisionId applied := by
  intro hFresh
  exact hFresh hMem

theorem semanticAstEquivalencePreservesCutoff
    {α β : Type} (hash : α → β) {astBefore astAfter : α}
    (hEq : astBefore = astAfter) :
    hash astBefore = hash astAfter :=
  congrArg hash hEq

end LambdaAitiaProof.Modules.GitOps
