-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-!
The composition law is independent of the Graph traversal implementation.
It states the admission boundary: evidence for components does not discharge
the separate, current obligation declared for their composite claim.
-/

namespace LambdaAitiaProof.Modules.Assurance.Composition

structure Contract (Claim Obligation : Type) where
  componentOf : Claim → Claim → Prop
  componentObligation : Obligation → Claim → Prop
  directObligation : Obligation → Claim → Prop
  current : Obligation → Prop
  discharged : Obligation → Prop
  compositeSupported : Claim → Prop
  directEvidenceRequired :
    ∀ composite, compositeSupported composite →
      ∃ obligation, directObligation obligation composite ∧
        current obligation ∧ discharged obligation
  independent :
    ∀ obligation component composite,
      componentOf component composite →
      componentObligation obligation component →
      ¬ directObligation obligation composite

def ComponentOnlyEvidence {Claim Obligation : Type}
    (contract : Contract Claim Obligation) (composite : Claim) : Prop :=
  ∀ obligation,
    contract.current obligation ∧ contract.discharged obligation →
      ∃ component,
        contract.componentOf component composite ∧
          contract.componentObligation obligation component

theorem componentOnlyEvidenceCannotSupportComposite
    {Claim Obligation : Type}
    (contract : Contract Claim Obligation) (composite : Claim)
    (onlyComponents : ComponentOnlyEvidence contract composite) :
    ¬ contract.compositeSupported composite := by
  intro supported
  obtain ⟨obligation, direct, current, discharged⟩ :=
    contract.directEvidenceRequired composite supported
  obtain ⟨component, part, componentEvidence⟩ :=
    onlyComponents obligation ⟨current, discharged⟩
  exact (contract.independent obligation component composite part componentEvidence) direct

theorem directObligationNeeded
    {Claim Obligation : Type}
    (contract : Contract Claim Obligation) (composite : Claim)
    (supported : contract.compositeSupported composite) :
    ∃ obligation,
      contract.directObligation obligation composite ∧
        contract.current obligation ∧ contract.discharged obligation :=
  contract.directEvidenceRequired composite supported

theorem directWitnessDiffersFromComponentObligation
    {Claim Obligation : Type}
    (contract : Contract Claim Obligation)
    (component composite : Claim) (componentEvidence : Obligation)
    (part : contract.componentOf component composite)
    (belongsToComponent : contract.componentObligation componentEvidence component)
    (supported : contract.compositeSupported composite) :
    ∃ directEvidence,
      contract.directObligation directEvidence composite ∧
        contract.current directEvidence ∧
        contract.discharged directEvidence ∧
        directEvidence ≠ componentEvidence := by
  obtain ⟨directEvidence, direct, current, discharged⟩ :=
    contract.directEvidenceRequired composite supported
  refine ⟨directEvidence, direct, current, discharged, ?_⟩
  intro same
  subst directEvidence
  exact (contract.independent componentEvidence component composite
    part belongsToComponent) direct

end LambdaAitiaProof.Modules.Assurance.Composition
