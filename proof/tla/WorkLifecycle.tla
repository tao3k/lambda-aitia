---- MODULE WorkLifecycle ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

EXTENDS TLC

(* Shared action contract: asking to cancel does not observe completion.
   The caller owns admission, review and authorization. *)
VARIABLES active, queued, cancelRequested
vars == <<active, queued, cancelRequested>>
Init == active = TRUE /\ queued = TRUE /\ cancelRequested = FALSE
RequestCancellation ==
  /\ ~cancelRequested /\ cancelRequested' = TRUE
  /\ UNCHANGED <<active, queued>>
ObserveCompletion == active /\ active' = FALSE
                     /\ UNCHANGED <<queued, cancelRequested>>
ObserveQueueDrained == queued /\ queued' = FALSE
                       /\ UNCHANGED <<active, cancelRequested>>
Quiescent == ~active /\ ~queued
TypeOK == active \in BOOLEAN /\ queued \in BOOLEAN /\ cancelRequested \in BOOLEAN
Terminal == Quiescent /\ cancelRequested /\ UNCHANGED vars
Next == RequestCancellation \/ ObserveCompletion \/ ObserveQueueDrained \/ Terminal
Spec == Init /\ [][Next]_vars

(* Atomic cancellation-only environment; completion is deliberately absent. *)
CancellationSpec == Init /\ [][RequestCancellation \/
                              (cancelRequested /\ UNCHANGED vars)]_vars
WorkRemains == active /\ queued
NeverCancelled == ~cancelRequested
NeverQuiescent == ~Quiescent
====
