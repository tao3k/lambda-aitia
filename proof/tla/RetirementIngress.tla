---- MODULE RetirementIngress ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

EXTENDS Naturals, TLC, EffectAdmission

(* Requests can arrive AFTER retirement. Closing ingress stops new grants and
   advances the authority epoch; a client may still hold an old cached grant.
   Revision/admission/decision/time are fixed to isolate epoch revocation.
   No new grant issuance, persistence or deployed authorization is modeled. *)
VARIABLES active, queued, known, reviewed, cancelRequested, retired,
          lateFound, gapFound, ingressOpen, epoch, grantEpoch,
          pending, attempted, rejectedAfterRetirement, startedAfterRetirement
Review == INSTANCE RetirementReview
vars == <<active, queued, known, reviewed, cancelRequested, retired,
          lateFound, gapFound, ingressOpen, epoch, grantEpoch,
          pending, attempted, rejectedAfterRetirement, startedAfterRetirement>>
boundary == <<ingressOpen, epoch, grantEpoch, pending, attempted,
              rejectedAfterRetirement, startedAfterRetirement>>
Current == CurrentGrant(1, 1, 1, 1, grantEpoch, epoch, 0, 1)
Init == /\ Review!Init /\ ingressOpen = TRUE /\ epoch = 0 /\ grantEpoch = 0
        /\ pending = FALSE /\ attempted = FALSE
        /\ rejectedAfterRetirement = FALSE /\ startedAfterRetirement = FALSE

Observe == Review!Observe /\ UNCHANGED boundary
CloseIngress ==
  /\ ingressOpen /\ ingressOpen' = FALSE /\ epoch' = epoch + 1
  /\ UNCHANGED <<active, queued, known, reviewed, cancelRequested, retired,
                  lateFound, gapFound, grantEpoch, pending, attempted,
                  rejectedAfterRetirement, startedAfterRetirement>>
Request ==
  /\ ~pending /\ ~attempted /\ pending' = TRUE
  /\ UNCHANGED <<active, queued, known, reviewed, cancelRequested, retired,
                  lateFound, gapFound, ingressOpen, epoch, grantEpoch, attempted,
                  rejectedAfterRetirement, startedAfterRetirement>>
StartBody ==
  /\ active' = TRUE /\ pending' = FALSE /\ attempted' = TRUE
  /\ startedAfterRetirement' = retired
  /\ UNCHANGED <<queued, known, reviewed, cancelRequested, retired, lateFound,
                  gapFound, ingressOpen, epoch, grantEpoch, rejectedAfterRetirement>>
Start == pending /\ Current /\ StartBody
TrustCachedGrant == pending /\ StartBody
Reject ==
  /\ pending /\ ~Current /\ pending' = FALSE /\ attempted' = TRUE
  /\ rejectedAfterRetirement' = retired
  /\ UNCHANGED <<active, queued, known, reviewed, cancelRequested, retired,
                  lateFound, gapFound, ingressOpen, epoch, grantEpoch,
                  startedAfterRetirement>>
Retire == ~ingressOpen /\ Review!Retire /\ UNCHANGED boundary
RetireWithoutFence == Review!Retire /\ UNCHANGED boundary
Terminal == retired /\ attempted /\ UNCHANGED vars
Environment == Observe \/ CloseIngress \/ Request \/ Reject \/ Terminal
Next == Environment \/ Start \/ Retire
Spec == Init /\ [][Next]_vars
UnfencedSpec == Init /\ [][Environment \/ Start \/ RetireWithoutFence]_vars
CachedGrantSpec == Init /\ [][Environment \/ TrustCachedGrant \/ Retire]_vars
TypeOK == /\ Review!TypeOK /\ ingressOpen \in BOOLEAN /\ epoch \in 0..1
          /\ grantEpoch = 0 /\ pending \in BOOLEAN /\ attempted \in BOOLEAN
          /\ rejectedAfterRetirement \in BOOLEAN /\ startedAfterRetirement \in BOOLEAN
RetiredIsFenced == retired => (~ingressOpen /\ grantEpoch # epoch)
NoPostRetirementStart == ~startedAfterRetirement
NoOutstandingWork == Review!NoOutstandingWork
InventoryKnown == Review!InventoryKnown
NeverRejectAfterRetirement == ~rejectedAfterRetirement
NeverStarted == ~(attempted /\ ~rejectedAfterRetirement /\ epoch = 0)
====
