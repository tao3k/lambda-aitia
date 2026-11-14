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

end LambdaAitiaProof.Modules.GitOps
