---- MODULE EffectAdmission ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

EXTENDS Naturals

(* Shared predicate extracted from AssuranceLifecycle.StartEffect.
   This is a formal contract, not another Runtime or policy evaluator. *)
CurrentGrant(granted, revision, admitted, decided, grantEpoch, epoch, clock, grantUntil) == granted = revision /\ admitted = revision /\ decided = revision /\ grantEpoch = epoch /\ clock < grantUntil
====
