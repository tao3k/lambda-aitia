---- MODULE RetirementReview ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

EXTENDS Naturals, TLC

(* Design-level experiment, not a generated projection or deployed Runtime.
   A review can be followed by late activity or a discovered inventory gap.
   Cancellation requests never stand in for completion observations.
   No persistence implementation or policy authorization is modeled. *)

VARIABLES active, queued, known, reviewed, cancelRequested, retired,
          lateFound, gapFound

Work == INSTANCE WorkLifecycle

vars == <<active, queued, known, reviewed, cancelRequested, retired,
          lateFound, gapFound>>

Init == /\ Work!Init /\ known = FALSE
        /\ reviewed = FALSE /\ retired = FALSE
        /\ lateFound = FALSE /\ gapFound = FALSE

RequestCancellation ==
  /\ ~retired /\ Work!RequestCancellation
  /\ UNCHANGED <<known, reviewed, retired, lateFound, gapFound>>

ObserveCompletion ==
  /\ ~retired /\ Work!ObserveCompletion
  /\ UNCHANGED <<known, reviewed, retired, lateFound, gapFound>>

ObserveQueueDrained ==
  /\ ~retired /\ Work!ObserveQueueDrained
  /\ UNCHANGED <<known, reviewed, retired, lateFound, gapFound>>

CompleteInventory ==
  /\ ~retired /\ ~known /\ known' = TRUE
  /\ UNCHANGED <<active, queued, reviewed, cancelRequested, retired, lateFound, gapFound>>

Review ==
  /\ ~retired /\ ~reviewed /\ Work!Quiescent /\ known
  /\ reviewed' = TRUE
  /\ UNCHANGED <<active, queued, known, cancelRequested, retired, lateFound, gapFound>>

ObserveLateActivity ==
  /\ ~retired /\ reviewed /\ ~lateFound
  /\ active' = TRUE /\ lateFound' = TRUE
  /\ UNCHANGED <<queued, known, reviewed, cancelRequested, retired, gapFound>>

ObserveInventoryGap ==
  /\ ~retired /\ reviewed /\ ~gapFound
  /\ known' = FALSE /\ gapFound' = TRUE
  /\ UNCHANGED <<active, queued, reviewed, cancelRequested, retired, lateFound>>

Finish ==
  /\ retired' = TRUE
  /\ UNCHANGED <<active, queued, known, reviewed, cancelRequested, lateFound, gapFound>>

Retire == ~retired /\ reviewed /\ Work!Quiescent /\ known /\ Finish
TrustCancellation == ~retired /\ cancelRequested /\ known /\ Finish
TrustOldReview == ~retired /\ reviewed /\ known /\ Finish
IgnoreInventoryGap == ~retired /\ reviewed /\ Work!Quiescent /\ Finish

Observe == RequestCancellation \/ ObserveCompletion \/ ObserveQueueDrained
           \/ CompleteInventory \/ Review \/ ObserveLateActivity \/ ObserveInventoryGap
Terminal == retired /\ UNCHANGED vars
Next == Observe \/ Retire \/ Terminal
Spec == Init /\ [][Next]_vars
CancellationSpec == Init /\ [][Observe \/ TrustCancellation \/ Terminal]_vars
OldReviewSpec == Init /\ [][Observe \/ TrustOldReview \/ Terminal]_vars
GapSpec == Init /\ [][Observe \/ IgnoreInventoryGap \/ Terminal]_vars

TypeOK == /\ Work!TypeOK /\ known \in BOOLEAN /\ reviewed \in BOOLEAN
          /\ retired \in BOOLEAN /\ lateFound \in BOOLEAN /\ gapFound \in BOOLEAN
NoOutstandingWork == retired => Work!Quiescent
InventoryKnown == retired => known
NeverRetired == ~retired

====
