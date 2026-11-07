// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package AitiaCommit {
    private import Views::*;
    private import ScalarValues::*;
    doc /* Target architecture for an evidence-driven local commit. The current
         * Rust runtime exposes the SDLC Graph and GitOps evaluation, with
         * read-only JJ observation and a separate ASCENT evidence query.
         * Host evidence admission and the write protocol are proposed. */

    part agentAndHuman {
        doc /* Agents propose change intent and claims. Humans review where policy requires. */
    }
    part rustRuntime {
        doc /* Owns request, tool, and transaction lifetimes, and observes actual outcomes. */
    }
    part yuanxuGraph {
        doc /* Scheme POO owns the configured SDLC Graph and obligation semantics. */
    }
    part jjGitOps {
        doc /* JJ owns workspace snapshots, revisions, and the operation log. Git is the backing repository. */
    }
    part engineeringChecks {
        doc /* Selected checks execute on the captured cut and emit attributable observations. */
    }
    part evidenceStore {
        doc /* Org Elements and Contracts carry source-bound artifacts. A separate Git repository may hold evidence. */
    }
    part evidenceAdmission {
        doc /* Execute the ORG Contract and compare the declared subject and
             * producer with independently obtained host execution data. */
    }
    part ascentReasoning {
        doc /* Derives supported, contradicted, stale, and eligible relations. Eligibility conveys no permission. */
    }
    part governance {
        doc /* Decides local commit authority over an exact intent, cut, scope, and policy revision. */
    }
    part operationReceipt {
        doc /* Binds intent, actual before and after JJ operations, resulting revision, and outcome. */
    }

    connection request connect agentAndHuman to rustRuntime;
    connection graphSemantics connect rustRuntime to yuanxuGraph;
    connection snapshotAndMutation connect rustRuntime to jjGitOps;
    connection checkExecution connect rustRuntime to engineeringChecks;
    connection observation connect engineeringChecks to evidenceStore;
    connection sourceArtifact connect evidenceStore to evidenceAdmission;
    connection hostExecution connect rustRuntime to evidenceAdmission;
    connection admittedFacts connect evidenceAdmission to ascentReasoning;
    connection reviewInputs connect ascentReasoning to governance;
    connection humanReview connect agentAndHuman to governance;
    connection commitGrant connect governance to rustRuntime;
    connection actualOutcome connect rustRuntime to operationReceipt;
    connection custody connect operationReceipt to evidenceStore;

    item def CommitCut {
        doc /* Bind project and workspace identity, JJ change ID and exact commit ID,
             * tree and parents, plus the observed JJ operation/view. A stable change
             * ID groups rewrites. It cannot identify the exact evaluated revision. */
        attribute projectId : String;
        attribute workspaceId : String;
        attribute changeId : String;
        attribute commitId : String;
        attribute treeId : String;
        attribute parentCommitIds : String[0..*];
        attribute operationId : String;
    }
    item def CommitIntent {
        doc /* Bind the cut, allowed content, description and workspace transition.
             * Describe/finalize authority is scoped to the local repository. */
        item cut : CommitCut;
        attribute intentId : String;
        attribute description : String;
    }
    item def EvidenceObservation {
        doc /* Bind the check, input cut, tool and configuration, outcome, and producer. */
        item cut : CommitCut;
        attribute checkId : String;
        attribute toolIdentity : String;
        attribute configurationDigest : String;
        attribute producerId : String;
        attribute outcome : String;
    }
    item def LocalCommitGrant {
        doc /* Independent Governance record for one intent and cut, with expiry,
             * revocation, and single-use conditions. */
        item intent : CommitIntent;
        attribute grantId : String;
        attribute policyRevision : String;
    }

    item capture : CommitCut;
    item propose : CommitIntent;
    item observe : EvidenceObservation;
    part admitObservation;
    part retainRejectedArtifact;
    part evaluate;
    item authorize : LocalCommitGrant;
    part validateCurrent;
    part applyLocalCommit;
    part recordOutcome;
    part reopen;
    part reconcileUnknown;

    connection capturedIntent connect capture to propose;
    connection exactInput connect capture to observe;
    connection intentSubject connect propose to evaluate;
    connection claimedObservation connect observe to admitObservation;
    connection expectedSubject connect capture to admitObservation;
    connection evidenceInput connect admitObservation to evaluate;
    connection rejectedObservation connect admitObservation to retainRejectedArtifact;
    connection eligibleCandidate connect evaluate to authorize;
    connection currentGrant connect authorize to validateCurrent;
    connection validatedWrite connect validateCurrent to applyLocalCommit;
    connection observedWrite connect applyLocalCommit to recordOutcome;
    connection staleCut connect validateCurrent to reopen;
    connection changedEvidence connect evaluate to reopen;
    connection recapture connect reopen to capture;
    connection interruptedWrite connect applyLocalCommit to reconcileUnknown;
    connection provenOutcome connect reconcileUnknown to recordOutcome;

    requirement sourceBinding {
        doc /* A well-formed ORG declaration is checked against independent
             * execution custody. Rejected artifacts remain reviewable and do
             * not supply support or contradiction facts to ASCENT. */
    }
    requirement exactCut {
        doc /* Rewrite, concurrent workspace operation, or changed checked inputs invalidate
             * the affected evidence and grant. Preserve history and reopen obligations. */
    }
    requirement independentAuthority {
        doc /* ASCENT relations and successful checks cannot mint a local commit grant.
             * The commit grant does not authorize bookmark publication or push. */
    }
    requirement explicitSnapshot {
        doc /* A JJ working-copy snapshot can write repository state.
             * Observe an already captured cut without implicit snapshotting.
             * Authorize an explicit snapshot separately from commit finalization. */
    }
    requirement guardedWriter {
        doc /* Revalidate captured identities and consume the grant at the controlled
             * write boundary. If a supported JJ adapter cannot enforce this boundary,
             * expose observation only. */
    }
    requirement recovery {
        doc /* On uncertain write outcome, inspect the JJ operation log and resulting
             * identities. Retry requires a proven no-write outcome and fresh authority. */
    }

    part openSysmlSdk {
        doc /* Parses named SysML documents and resolves engineering elements and relationships. */
    }
    part gerbilJavaScriptDriver {
        doc /* Generated driver submits a declared check against authored Quint sources. */
    }
    part quintChecker {
        doc /* Executes Quint actions and invariants and returns scoped model evidence. */
    }
    part modelGapQuery {
        doc /* ASCENT derives missing, stale and contradicted mappings from admitted facts. */
    }
    part agentProposal {
        doc /* Suggests competing SysML and Quint changes for independent validation. */
    }

    connection resolveDesign connect rustRuntime to openSysmlSdk;
    connection designElements connect openSysmlSdk to modelGapQuery;
    connection runDeclaredCheck connect rustRuntime to gerbilJavaScriptDriver;
    connection checkAuthoredModel connect gerbilJavaScriptDriver to quintChecker;
    connection modelObservation connect quintChecker to evidenceAdmission;
    connection admittedModelEvidence connect evidenceAdmission to modelGapQuery;
    connection exactRevisionForReview connect jjGitOps to modelGapQuery;
    connection groundedGaps connect modelGapQuery to agentProposal;
    connection proposedChanges connect agentProposal to rustRuntime;

    view modelEngineeringGraph {
        doc /* Target tool integration for the existing JJ rewrite case. */
        expose rustRuntime; expose jjGitOps; expose openSysmlSdk;
        expose gerbilJavaScriptDriver; expose quintChecker; expose evidenceAdmission;
        expose modelGapQuery; expose agentProposal;
        expose resolveDesign; expose designElements; expose runDeclaredCheck;
        expose checkAuthoredModel; expose modelObservation; expose admittedModelEvidence;
        expose exactRevisionForReview; expose groundedGaps; expose proposedChanges;
        render asInterconnectionDiagram;
    }

    part gitOpsModule {
        doc /* Scheme/POO owns project configuration, GitOps operation intent,
             * applicability and evidence obligations through Yuanxu. */
    }
    part gitOpsFfi {
        doc /* Exchanges bounded requests and observations under one owner.
             * An exchange carries identity and outcome, and issues no grants. */
    }
    part jjAdapter {
        doc /* Rust owns repository handles, pinned observations, guarded mutation
             * and reconciliation against the JJ operation log. */
    }
    part jjRepository {
        doc /* JJ change, commit, workspace and operation identities. */
    }

    connection gitOpsRequest connect gitOpsModule to gitOpsFfi;
    connection repositoryOperation connect gitOpsFfi to jjAdapter;
    connection repositoryEffect connect jjAdapter to jjRepository;
    connection repositoryObservation connect jjRepository to jjAdapter;
    connection operationResult connect jjAdapter to gitOpsFfi;
    connection semanticObservation connect gitOpsFfi to gitOpsModule;
    connection evidenceObligations connect gitOpsModule to engineeringChecks;
    connection evidenceReview connect gitOpsModule to evidenceAdmission;
    connection obligationState connect ascentReasoning to gitOpsModule;
    connection authorizedIntent connect governance to gitOpsModule;

    item def GitOpsExchange {
        attribute requestId : String;
        attribute projectId : String;
        attribute workspaceId : String;
        attribute expectedOperationId : String[0..1];
    }

    item def ObserveRecordedCut :> GitOpsExchange {
        doc /* Open an observation for the registered project and workspace.
             * An expected operation, if supplied, constrains the observation. */
    }

    item def RecordedCutObservation {
        attribute requestId : String;
        item cut : CommitCut;
    }

    requirement gitOpsReadCustody {
        doc /* Admit a successful result only to its outstanding request and
             * project/workspace owner. Read artifacts at that exact cut.
             * Changed operations and rejected requests supply no evidence. */
    }

    item def GitOpsMutation :> GitOpsExchange {
        item intent : CommitIntent;
        item grant : LocalCommitGrant;
        attribute attemptId : String;
    }

    item def GitOpsOperationReceipt {
        attribute requestId : String;
        attribute attemptId : String;
        item beforeCut : CommitCut;
        item afterCut : CommitCut;
    }

    requirement gitOpsWriteFence {
        doc /* The expected operation and grant must be enforced at the same
             * authority boundary as publication of the local JJ mutation.
             * A prior read and a later independent CLI command leave a race. */
    }

    requirement gitOpsOutcomeCustody {
        doc /* Report an applied effect only with an attributable resulting
             * operation. Interrupted attempts remain unresolved until the
             * result can be reconciled. Unresolved attempts prohibit retry. */
    }

    part prepareLocalOperation {
        doc /* Store the intended JJ operation without advancing the visible head. */
    }
    part recordWriteAttempt {
        doc /* Persist the attempt and its prepared operation identity. */
    }
    part guardedPublication {
        doc /* Recheck the exact cut and consume a current grant within the
             * qualified local writer boundary. */
    }
    part refuseLocalWrite {
        doc /* A stale cut or revoked grant prevents an effect. */
    }
    part reconcileWriteAttempt {
        doc /* Inspect operation reachability and the attributable effect. */
    }
    part retainUnresolvedAttempt {
        doc /* Neither an effect receipt nor a retry may be produced. */
    }
    part requireFreshIntent {
        doc /* Proven absence of the effect permits a fresh decision. */
    }
    item localEffectReceipt : GitOpsOperationReceipt;

    connection preparedOperation connect prepareLocalOperation to recordWriteAttempt;
    connection durableAttempt connect recordWriteAttempt to guardedPublication;
    connection staleCutOrRevocation connect guardedPublication to refuseLocalWrite;
    connection confirmedLocalEffect connect guardedPublication to localEffectReceipt;
    connection lostAcknowledgement connect guardedPublication to reconcileWriteAttempt;
    connection provenEffect connect reconcileWriteAttempt to localEffectReceipt;
    connection provenNoEffect connect reconcileWriteAttempt to requireFreshIntent;
    connection ambiguousOutcome connect reconcileWriteAttempt to retainUnresolvedAttempt;

    view gitOpsWriteRecovery {
        doc /* Candidate local-write lifecycle. The receipt represents the
             * local repository operation and grants no external publication. */
        expose prepareLocalOperation; expose recordWriteAttempt; expose guardedPublication;
        expose refuseLocalWrite; expose reconcileWriteAttempt; expose retainUnresolvedAttempt;
        expose requireFreshIntent; expose localEffectReceipt;
        expose preparedOperation; expose durableAttempt; expose staleCutOrRevocation;
        expose confirmedLocalEffect; expose lostAcknowledgement;
        expose provenEffect; expose provenNoEffect; expose ambiguousOutcome;
        render asInterconnectionDiagram;
    }

    view gitOpsLifecycleBoundary {
        doc /* The Scheme Module owns the lifecycle protocol and delegates JJ
             * repository effects through FFI to the Rust adapter. */
        expose gitOpsModule; expose gitOpsFfi; expose jjAdapter; expose jjRepository;
        expose engineeringChecks; expose evidenceAdmission; expose ascentReasoning;
        expose governance; expose admittedFacts; expose reviewInputs;
        expose gitOpsRequest; expose repositoryOperation; expose repositoryEffect;
        expose repositoryObservation; expose operationResult; expose semanticObservation;
        expose evidenceObligations; expose evidenceReview; expose obligationState;
        expose authorizedIntent;
        render asInterconnectionDiagram;
    }

    view runtimeArchitecture {
        expose agentAndHuman; expose rustRuntime; expose yuanxuGraph;
        expose jjGitOps; expose engineeringChecks; expose evidenceStore;
        expose evidenceAdmission; expose ascentReasoning; expose governance; expose operationReceipt;
        expose request; expose graphSemantics; expose snapshotAndMutation;
        expose checkExecution; expose observation; expose sourceArtifact; expose hostExecution; expose admittedFacts;
        expose reviewInputs; expose humanReview; expose commitGrant;
        expose actualOutcome; expose custody;
        render asInterconnectionDiagram;
    }
    view commitEvidenceGraph {
        expose capture; expose propose; expose observe; expose admitObservation;
        expose retainRejectedArtifact; expose evaluate;
        expose authorize; expose validateCurrent; expose applyLocalCommit;
        expose recordOutcome; expose reopen; expose reconcileUnknown;
        expose capturedIntent; expose exactInput; expose intentSubject;
        expose claimedObservation; expose expectedSubject; expose evidenceInput;
        expose rejectedObservation; expose eligibleCandidate; expose currentGrant;
        expose validatedWrite; expose observedWrite; expose staleCut;
        expose changedEvidence; expose recapture; expose interruptedWrite;
        expose provenOutcome;
        render asInterconnectionDiagram;
    }
}
