-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-!
Lambda Aitia owns these domain laws. POO Flow may implement graph traversal,
but its generic proof package is neither imported nor copied here.
-/

namespace LambdaAitiaProof.Modules.Assurance.Invalidation

abbrev NodeSet (Node : Type) := Node → Prop

def Subset {Node : Type} (left right : NodeSet Node) : Prop :=
  ∀ node, left node → right node

def Impact {Node : Type}
    (reaches : Node → Node → Prop)
    (changed : NodeSet Node) : NodeSet Node :=
  fun node => changed node ∨ ∃ seed, changed seed ∧ reaches seed node

theorem impactMonotoneForFixedSnapshot
    {Node : Type}
    (reaches : Node → Node → Prop)
    (earlier later : NodeSet Node)
    (expanded : Subset earlier later) :
    Subset (Impact reaches earlier) (Impact reaches later) := by
  intro node impacted
  cases impacted with
  | inl changed =>
      exact Or.inl (expanded node changed)
  | inr path =>
      rcases path with ⟨seed, changed, reachable⟩
      exact Or.inr ⟨seed, expanded seed changed, reachable⟩

def Closed {Node : Type} (unresolved : NodeSet Node) : Prop :=
  ∀ node, ¬ unresolved node

theorem unresolvedFrontierBlocksClosure
    {Node : Type}
    (unresolved : NodeSet Node)
    (frontier : ∃ node, unresolved node) :
    ¬ Closed unresolved := by
  intro closed
  rcases frontier with ⟨node, missing⟩
  exact closed node missing

structure InvalidationReceipt (Node : Type) where
  impacted : NodeSet Node
  unresolved : NodeSet Node
  temporalProven : Bool
  releaseAuthorized : Bool
  runtimeExecuted : Bool

def InvalidationReceipt.Inert {Node : Type}
    (receipt : InvalidationReceipt Node) : Prop :=
  receipt.temporalProven = false ∧
    receipt.releaseAuthorized = false ∧
    receipt.runtimeExecuted = false

theorem inertReceiptGrantsNoAuthority
    {Node : Type}
    (receipt : InvalidationReceipt Node)
    (inert : receipt.Inert) :
    receipt.releaseAuthorized = false ∧ receipt.runtimeExecuted = false :=
  inert.2

end LambdaAitiaProof.Modules.Assurance.Invalidation
