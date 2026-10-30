-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-!
A declaration-level substitution direction for software-design contracts.
The predicates stand for exact, independently identified clauses. These laws
do not prove that natural-language clauses hold in an implementation, that the
Scheme comparison implements this relation, or that an effect is authorized.
-/

namespace LambdaAitiaProof.Modules.Sdlc.Design

structure Contract (Clause : Type) where
  assumptions : Clause → Prop
  guarantees : Clause → Prop

def Refines {Clause : Type} (old candidate : Contract Clause) : Prop :=
  (∀ clause, candidate.assumptions clause → old.assumptions clause) ∧
  (∀ clause, old.guarantees clause → candidate.guarantees clause)

theorem refinesRefl {Clause : Type} (contract : Contract Clause) :
    Refines contract contract := by
  constructor <;> intro clause present <;> exact present

theorem refinesTrans {Clause : Type}
    (first second third : Contract Clause)
    (firstToSecond : Refines first second)
    (secondToThird : Refines second third) :
    Refines first third := by
  constructor
  · intro clause required
    exact firstToSecond.1 clause (secondToThird.1 clause required)
  · intro clause promised
    exact secondToThird.2 clause (firstToSecond.2 clause promised)

theorem strongerAssumptionBlocks {Clause : Type}
    (old candidate : Contract Clause) (clause : Clause)
    (required : candidate.assumptions clause)
    (notPreviouslyRequired : ¬ old.assumptions clause) :
    ¬ Refines old candidate := by
  intro replacement
  exact notPreviouslyRequired (replacement.1 clause required)

theorem droppedGuaranteeBlocks {Clause : Type}
    (old candidate : Contract Clause) (clause : Clause)
    (promised : old.guarantees clause)
    (notPromised : ¬ candidate.guarantees clause) :
    ¬ Refines old candidate := by
  intro replacement
  exact notPromised (replacement.2 clause promised)

end LambdaAitiaProof.Modules.Sdlc.Design
