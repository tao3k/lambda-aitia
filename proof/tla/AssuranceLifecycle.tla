---- MODULE AssuranceLifecycle ----
\* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
\*
\* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

EXTENDS Naturals, TLC

(* Bounded control-plane model. A successful report is not a Host verification;
   admitted evidence and grants are current only inside their validity cut. *)

VARIABLES revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe

vars == <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>

Init == revision = 1 /\ planned = 0 /\ verified = 0 /\ admitted = 0 /\ decided = 0 /\ granted = 0 /\ grantEpoch = 0 /\ epoch = 0 /\ clock = 0 /\ sealUntil = 0 /\ grantUntil = 0 /\ adapterInstalled = FALSE /\ reportedSuccess = FALSE /\ effectStarted = FALSE /\ startSafe = TRUE

InstallAdapter == ~adapterInstalled /\ adapterInstalled' = TRUE /\ UNCHANGED <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, reportedSuccess, effectStarted, startSafe>>
ReportSuccess == ~reportedSuccess /\ reportedSuccess' = TRUE /\ UNCHANGED <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, effectStarted, startSafe>>
Plan == planned # revision /\ planned' = revision /\ UNCHANGED <<revision, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Verify == adapterInstalled /\ planned = revision /\ clock < 3 /\ verified' = revision /\ sealUntil' = clock + 1 /\ UNCHANGED <<revision, planned, admitted, decided, granted, grantEpoch, epoch, clock, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Admit == verified = revision /\ clock < sealUntil /\ admitted # revision /\ admitted' = revision /\ UNCHANGED <<revision, planned, verified, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Decide == admitted = revision /\ decided # revision /\ decided' = revision /\ UNCHANGED <<revision, planned, verified, admitted, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Authorize == decided = revision /\ admitted = revision /\ granted # revision /\ clock < 3 /\ granted' = revision /\ grantEpoch' = epoch /\ grantUntil' = clock + 1 /\ UNCHANGED <<revision, planned, verified, admitted, decided, epoch, clock, sealUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
StartEffect == ~effectStarted /\ granted = revision /\ admitted = revision /\ decided = revision /\ grantEpoch = epoch /\ clock < grantUntil /\ effectStarted' = TRUE /\ startSafe' = (admitted = revision /\ decided = revision /\ granted = revision /\ grantEpoch = epoch /\ clock < grantUntil) /\ UNCHANGED <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess>>
ChangeSource == revision = 1 /\ revision' = 2 /\ planned' = 0 /\ verified' = 0 /\ admitted' = 0 /\ decided' = 0 /\ granted' = 0 /\ sealUntil' = 0 /\ grantUntil' = 0 /\ UNCHANGED <<grantEpoch, epoch, clock, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Tick == clock < 3 /\ clock' = clock + 1 /\ admitted' = (IF clock + 1 < sealUntil THEN admitted ELSE 0) /\ decided' = (IF clock + 1 < sealUntil THEN decided ELSE 0) /\ granted' = (IF (clock + 1 < sealUntil /\ clock + 1 < grantUntil) THEN granted ELSE 0) /\ UNCHANGED <<revision, planned, verified, grantEpoch, epoch, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
Revoke == epoch < 2 /\ epoch' = epoch + 1 /\ verified' = 0 /\ admitted' = 0 /\ decided' = 0 /\ granted' = 0 /\ sealUntil' = 0 /\ UNCHANGED <<revision, planned, grantEpoch, clock, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>

Next == InstallAdapter \/ ReportSuccess \/ Plan \/ Verify \/ Admit \/ Decide \/ Authorize \/ StartEffect \/ ChangeSource \/ Tick \/ Revoke
Spec == Init /\ [][Next]_vars

(* Progress is conditional: no source change, clock tick or revocation occurs,
   and the Host eventually schedules each continuously enabled stage. This
   does not assert unconditional progress for a changing environment. *)
StableNext == InstallAdapter \/ ReportSuccess \/ Plan \/ Verify \/ Admit \/ Decide \/ Authorize \/ StartEffect
StableSpecNoFair == Init /\ [][StableNext]_vars
StableSpec == Init /\ [][StableNext]_vars /\ WF_vars(InstallAdapter) /\ WF_vars(Plan) /\ WF_vars(Verify) /\ WF_vars(Admit) /\ WF_vars(Decide) /\ WF_vars(Authorize) /\ WF_vars(StartEffect)
EventuallyEffect == <>effectStarted

(* Deliberately unsafe mutant: a reported green result starts an effect without
   Host admission or grant. Its counterexample must be found by TLC. *)
UnsafeStart == reportedSuccess /\ ~effectStarted /\ effectStarted' = TRUE /\ startSafe' = (admitted = revision /\ decided = revision /\ granted = revision /\ grantEpoch = epoch /\ clock < grantUntil) /\ UNCHANGED <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess>>
UnsafeNext == Next \/ UnsafeStart
UnsafeSpec == Init /\ [][UnsafeNext]_vars
UnsafeLateAdmit == revision = 2 /\ reportedSuccess /\ admitted = 0 /\ admitted' = 1 /\ UNCHANGED <<revision, planned, verified, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
UnsafeLateAdmitNext == Next \/ UnsafeLateAdmit
UnsafeLateAdmitSpec == Init /\ [][UnsafeLateAdmitNext]_vars
UnsafeEarlyGrant == revision = 2 /\ reportedSuccess /\ admitted = 0 /\ granted = 0 /\ clock < 3 /\ granted' = revision /\ grantEpoch' = epoch /\ grantUntil' = clock + 1 /\ UNCHANGED <<revision, planned, verified, admitted, decided, epoch, clock, sealUntil, adapterInstalled, reportedSuccess, effectStarted, startSafe>>
UnsafeEarlyGrantNext == Next \/ UnsafeEarlyGrant
UnsafeEarlyGrantSpec == Init /\ [][UnsafeEarlyGrantNext]_vars
UnsafeAfterRevoke == epoch > grantEpoch /\ grantUntil > clock /\ granted = 0 /\ ~effectStarted /\ effectStarted' = TRUE /\ startSafe' = (admitted = revision /\ decided = revision /\ granted = revision /\ grantEpoch = epoch /\ clock < grantUntil) /\ UNCHANGED <<revision, planned, verified, admitted, decided, granted, grantEpoch, epoch, clock, sealUntil, grantUntil, adapterInstalled, reportedSuccess>>
UnsafeAfterRevokeNext == Next \/ UnsafeAfterRevoke
UnsafeAfterRevokeSpec == Init /\ [][UnsafeAfterRevokeNext]_vars

TypeInvariant == revision \in {1, 2} /\ planned \in {0, 1, 2} /\ verified \in {0, 1, 2} /\ admitted \in {0, 1, 2} /\ decided \in {0, 1, 2} /\ granted \in {0, 1, 2} /\ grantEpoch \in 0..2 /\ epoch \in 0..2 /\ clock \in 0..3 /\ sealUntil \in 0..4 /\ grantUntil \in 0..4 /\ adapterInstalled \in BOOLEAN /\ reportedSuccess \in BOOLEAN /\ effectStarted \in BOOLEAN /\ startSafe \in BOOLEAN
AdmissionIsCurrent == admitted = 0 \/ (admitted = revision /\ verified = revision /\ clock < sealUntil)
DecisionRequiresAdmission == decided = 0 \/ (decided = revision /\ admitted = revision)
GrantRequiresCurrentDecision == granted = 0 \/ (granted = revision /\ decided = revision /\ admitted = revision /\ grantEpoch = epoch /\ clock < grantUntil)
NoUnsafeEffectStart == startSafe
NoEffectStarted == ~effectStarted

====
