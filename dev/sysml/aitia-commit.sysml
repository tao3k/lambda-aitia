// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package AitiaCommit {
    private import Views::*;
    private import ScalarValues::*;
    doc /* Evidence-driven local commit. The default Project path validates
         * a prepared description and publishes through JJ. A Project may
         * additionally require independent signed Governance approval.
         * The linked replay and Agent input Cases use Host admission. */

    part agentAndHuman {
        doc /* Agents propose change intent and claims. Humans review where policy requires. */
    }
    part rustRuntime {
        doc /* Owns request, tool, and transaction lifetimes, and observes actual outcomes. */
    }
    part yuanxuGraph {
        doc /* Scheme POO owns the configured SDLC Graph and obligation semantics. */
    }
    requirement linkedStartupBoundary {
        doc /* Target design. One linked Scheme VM initializes the entry and
             * the modules required by the selected command. A configuration
             * read admits its project declaration without activating
             * commit assessment or journal execution. First preview still
             * evaluates the applicable ASCENT rules and ORG Contracts. */
    }
    requirement linkedStartupQualification {
        doc /* Measure launch to VM readiness, first policy call, first
             * command result, and ordinary exit. Use the same recorded
             * candidate to compare description, Evidence and revision GQL.
             * Measure first execution of a copied binary separately from
             * later invocations of that file. */
    }
    requirement linkedJournalDemand {
        doc /* Register the Lab durable journal with the linked Scheme image.
             * Commit admission and Context checkpoints initialize its
             * dependency closure when called. A read-only preview has no
             * journal demand. Approval and recovery keep the existing
             * journal encoding and keys. */
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
        doc /* Decides local commit authority when required by the Project policy. */
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
        attribute reviewContext : String;
    }
    item def ReviewRevision {
        doc /* The review selector names a full commit ID in the project's
             * JJ store. A bookmark or a change ID cannot substitute for it. */
        attribute projectId : String;
        attribute commitId : String;
    }
    requirement historicalReviewRead {
        doc /* The same revision continues to select its immutable tree when
             * the workspace advances. Reproduce the archived JJ report's
             * input binding from the original cut, recorded Scheme and JSON
             * sources, and changed paths before projecting the observation.
             * Compare raw JJ reports with the reproduced facts before entering
             * Scheme. Scheme selects applicable checks and their obligations.
             * A supplied proposal must satisfy the same request shape used
             * in live review. Scheme reconstructs its title and checks the
             * recorded engineering reference before projecting it.
             * Readability alone does not establish
             * apply, publication, current evidence support, or authority. */
    }
    requirement recoveredReviewRead {
        doc /* A recovery result must identify the exact applied operation
             * in the nearest Git project's JJ history. A direct attempt
             * can be reconciled even when current configuration cannot
             * be loaded. Approval lookup requires its Governance journal.
             * Its original changes and committed
             * description are readable at the result revision. Missing
             * archived reports remain missing. Recovery grants no effect. */
    }
    requirement recordedReviewProject {
        doc /* Resolve the nearest Git project and its recorded JJ inputs before
             * entering Scheme review. Scheme admits those sources and selects
             * policy. Applied preview and push verify the original review cut
             * from the same observed workspace, then recheck currentness. */
    }
    requirement appliedReviewRefresh {
        doc /* Reopen review at the original cut of the verified current
             * description rewrite. Observe current provider facts and retain
             * the comparison with the committed description. A new review
             * context can authorize consideration at push only when the
             * rendered description still matches the commit. */
    }
    requirement acknowledgedPushRecovery {
        doc /* Record success only if JJ positively acknowledges the sole
             * requested bookmark and its transaction records the applied
             * commit as the remote target. Recover a visible acknowledgement
             * for the exact applied operation, workspace, remote and bookmark.
             * Resolve the nearest Git project before opening its JJ history.
             * An independent nested Git project requires its own JJ workspace. The
             * historical acknowledgement carries no claim about the
             * current remote head. Missing history leaves the outcome
             * unresolved. Recovery performs no transport. */
    }
    item def EngineeringReference {
        doc /* An engineering record has a project-declared identity and a unique
             * ORG Element in a JJ-recorded source. Its ENGINEERING_ID must match
             * the owning headline in the full parsed graph. The document
             * Contract counts every ID property, including document-level
             * properties, using a view limited to those records and the root.
             * Distinct referenced IDs in one recorded document share a
             * Contract query context and each receives its own verdict.
             * A linked PR and a NASA SWE obligation are separate relations.
             * Distinct declared document/Element pairs for the same identity
             * conflict even if one cannot resolve on the current cut. */
        attribute identity : String;
        attribute sourcePath : String;
        attribute elementId : String;
    }
    item def NarrationProposal {
        doc /* LLM intent remains a proposal. Scheme renders a canonical title
             * only after ASCENT relates its reference, allowed type and affected
             * module scope. Each affected scope retains the recorded paths
             * that support it. Paths outside all admitted scopes remain
             * visible in review. Differing path sets under the same scope
             * name leave the proposal open. The full rendered title may contain up to 72
             * characters. Rationale is review input, not execution authority. */
        item reference : EngineeringReference;
        attribute identity : String;
        attribute changeType : String;
        attribute moduleScope : String;
        attribute summary : String;
        attribute rationale : String;
        attribute 'language' : String;
        attribute languageSource : String;
        doc /* Language is proposed from observed project documentation and any
             * explicit project declaration. The declared source path must
             * resolve to exactly one observation on the current JJ cut.
             * Missing, stale, or competing observations leave the proposal open.
             * ASCENT retains source and language conflict relations. */
    }
    item def RecordedReviewBookmark {
        doc /* JJ discovery evidence at one recorded operation. The target must
             * be reachable from the candidate. On each remote JJ retains the
             * maximal reachable targets and keeps aliases and conflicts distinct.
             * A conflicting target has no selected commit. Provider association,
             * check evidence and authority to push have separate admission. */
        item cut : CommitCut;
        attribute remoteName : String;
        attribute bookmarkName : String;
        attribute targetCommit : String[0..1];
        attribute githubRepository : String[0..1];
        doc /* Current JJ backend configuration supplies a GitHub repository
             * identity only when fetch and push endpoints agree. Credentials
             * and raw URLs never enter the observation. The configuration
             * observation is not part of immutable operation history. */
    }
    item def ProviderReviewObservation {
        doc /* A GitHub response must agree with the recorded repository,
             * source bookmark and head revision. Check runs refer to that
             * head. Scheme requires each check identity to occur once and every
             * check to refer to that head. Empty, malformed, duplicate or stale inventory
             * leaves the check disclosure Open. A published ancestor can establish
             * the PR association, but its checks leave the candidate's check
             * disclosure Open even when all passed. An observation grants no
             * push authority. */
        item bookmark : RecordedReviewBookmark;
        attribute pullRequestNumber : Integer;
        attribute targetBranch : String;
        attribute targetRevision : String;
        attribute headRevision : String;
        attribute onCandidate : Boolean;
        attribute updatedAt : String;
    }
    item def ProviderBranchAbsence {
        doc /* An empty open PR response is joined with a successful read of
             * the exact provider branch ref and its commit target. Scheme
             * admits the route only if it matches the recorded JJ bookmark. */
        item bookmark : RecordedReviewBookmark;
        attribute headRevision : String;
    }
    requirement liveReviewAssociation {
        doc /* Derive PR identity and target from the provider response
             * associated with the current JJ bookmark. No Project manifest
             * value supplies a PR identity or target. Bind the observed
             * association, including its target revision, to review and
             * revalidate before effects. Target advancement with the same
             * branch name invalidates the earlier review.
             * At push, the selected GitHub route and bookmark lease must
             * match a current PR association or an exact no-open-PR observation.
             * Re-read the association at lease admission and refuse transport
             * if the provider observation differs from the admitted review.
             * A split or undiscovered GitHub route cannot consume admission. */
    }
    requirement currentPushDestination {
        doc /* Bind the effective transport route to the review and compare it
             * against the selected route under the JJ lease.
             * Require exactly one effective push URL before admission.
             * One bookmark lease and acknowledgement cover one destination.
             * Refuse automatic tag following and mirror mode before and
             * after admission. The reviewed update covers one bookmark.
             * Disable both settings in the transport subprocess so a later
             * configuration write cannot widen the set of refs.
             * Admit only no or check for submodule recursion and pass the
             * admitted non-publishing mode to the Git subprocess.
             * After the admission callback, reopen Git configuration and compare
             * the ordered effective fetch and push URLs with the admitted
             * route. Refuse a missing or changed route before starting the
             * transaction, including when the bookmark lease is unchanged.
             * Verify that Git can reset the push URL list before admission.
             * Give the transport the admitted URL through a one-use rewrite
             * in command-scope configuration. JJ retains the original remote
             * name for the bookmark lease and receipt. */
    }
    requirement projectDeclarationOverlay {
        doc /* Scheme composes JSON data with the project's POO declaration
             * through Yuanxu. Omitted fields inherit and explicit values
             * replace their slots. Only the effective value passes to the
             * project Contract. JJ observes both inputs in one tree.
             * Scheme evaluates the packaged expression only after matching
             * its source to the recorded declaration. The archive identity
             * is part of the review context. */
    }
    item def CompiledPolicyProgram {
        doc /* Scheme owns rule semantics. The build binds the actual linked
             * program contents, not the manifest's file names. Runtime uses
             * the embedded identity without reading a checkout or build files. */
        attribute artifactIdentity : String;
    }
    requirement compiledPolicyCurrentness {
        doc /* Replacing compiled rule contents invalidates an old review even
             * when project revision and manifest paths are unchanged. Reopen
             * review before prepare/apply/push; eligibility never grants authority. */
    }
    item def NarrationAssessment {
        doc /* Retain competing proposals and unresolved/conflicting references.
             * Bind naming policy, source contents and changed paths to the review
             * context. Any revision requires re-evaluation before prepare/apply
             * and actual JJ description readback before push. */
        item proposals : NarrationProposal[0..*];
        item compiledPolicy : CompiledPolicyProgram;
        attribute eligibleIds : String[0..*];
        attribute openReasons : String[0..*];
        attribute canonicalTitle : String;
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
    item def NasaCommitAssessment {
        doc /* The selected NASA Scenario binds its edition and catalog digest
             * to a bounded project assessment. Current support, counterexamples
             * and remaining obligations are retained with their observations.
             * Each selected execution method maps to one requirement.
             * Historical readback uses that method to locate its report.
             * Runtime receipts retain exact identity and digest bindings.
             * The commit description contains the reviewed title and narrative.
             * Org review properties reference readable obligations; a separate
             * Runtime context binds their Contract to the current cut. The
             * linked Scheme export returns a rooted assessment projection.
             * Rust reads its values through the bridge and serializes the CLI
             * response. The projection conveys the Scheme decision and does
             * not independently grant authority. */
        item cut : CommitCut;
        attribute standardEdition : String;
        attribute standardSourceDigest : String;
        attribute evidenceIds : String[0..*];
        attribute openObligationIds : String[0..*];
        attribute descriptionDigest : String;
    }
    item def PreparedDescription {
        doc /* A stored JJ operation has an exact resulting revision and stays
             * invisible at head until a guarded write makes it visible.
             * Its operation metadata binds the preparation to the Scheme
             * review context. Apply compares that stored value to the current
             * assessment before publishing. */
        item expected : CommitCut;
        attribute preparedOperationId : String;
        attribute resultingCommitId : String;
        attribute descriptionDigest : String;
    }
    item def DescriptionReviewOrigin {
        doc /* JJ proves that the current operation is the exact prepared
             * description-only rewrite: tree, parents and change identity are
             * unchanged. The original cut and independent Git-object audit are
             * observed from immutable history, not supplied by the Agent. */
        item original : CommitCut;
        item current : CommitCut;
    }
    requirement appliedEvidenceReadback {
        doc /* Resolve the exact result revision through visible JJ operation
             * history. The host rejects archive methods it cannot produce
             * and SysML observations inconsistent with the recorded changed
             * paths or a successful status. Resolve the check selection
             * from the original project configuration through the Scheme
             * Contract. Reproduce selected
             * inventory and Git audit reports and compare them to the archive.
             * Verify each archived requirement and execution identity
             * against the selected check and reproduced inputs and report.
             * Report missing selected observations and refuse unselected
             * archives. The readback grants no write authority. */
    }
    requirement observedEvidenceLineage {
        doc /* Project verified JJ observations into one revision graph.
             * Each Query node exposes the same identity as its Graph node.
             * The graph relates file versions, recorded config inputs,
             * and regular files named by the recorded policy
             * to the revision, and changed files to the inventory that
             * enumerated them. Missing reports and unknown dependency
             * coverage remain distinct from observed report edges.
             * Reject duplicate observations and conflicting report states
             * before constructing the graph. Config inputs and policy
             * sources describe regular files. Each must agree with the
             * recorded file identity and executable bit of any other
             * observation at its path. A parse edge requires a verified
             * report and a changed regular SysML file in the selected
             * revision. */
    }
    requirement revisionInventoryQuery {
        doc /* Verify the applied revision and its archived reports before
             * selecting paths. Lab Query can select changed files from JJ
             * even when the archived inventory is missing. It traverses
             * observed changes to verified inventory and model reports,
             * and reads recorded configuration
             * and policy source paths with their changed state. Select
             * verified reports directly from the revision, including the
             * Git configuration audit of its tree and ordered parents.
             * Select missing report methods directly from the revision
             * through missing_report. Unknown dependency coverage is
             * reported separately. A policy source edge records availability.
             * An applied archive must supply the review context and proposal
             * bound to the verified JJ rewrite. The recorded revision must
             * select a commit policy. Scheme reruns title
             * admission against the applied tree and compares the rendered
             * title to JJ's readback.
             * The revision then names an EngineeringReference declared in the
             * recorded file. Recovery with only a rewrite receipt has no such
             * relation.
             * All selections remain partial and carry no action authority. */
    }
    requirement affectedModelAudit {
        doc /* A project-enabled model check applies to recorded SysML paths
             * changed by the candidate. The result must cover those exact
             * paths under the shared source byte budget. Bind the model
             * observation to review. Render the verified scope in Evidence
             * and keep an unresolved check in Open. */
    }
    requirement historicalModelEvidence {
        doc /* Resolve affected model paths from the applied revision and
             * select checks from the recorded project sources through the
             * same linked Scheme configuration Contract as live review.
             * A disabled check contributes no missing report. Refuse an
             * archive outside the selected checks or paths. Apply the same
             * total source budget as live review before parsing.
             * Compare an independent OpenSysML result with the archived
             * report. Emit parsed_by only for documents in the verified
             * result. A missing archive does not establish a passed check.
             * Later workspace contents do not enter this comparison. */
    }
    requirement reviewContextPreservation {
        doc /* Push must retain the original narration context and re-evaluate
             * it under current Scheme rules at the verified origin. A body-only
             * transition does not renew review. Equal rendered prose does not
             * excuse a stale context, changed rationale or changed ORG material.
             * Applied preview reports text equality and context freshness
             * independently. Push refuses a local description approval and
             * malformed context before starting review. It verifies the
             * current context before handing the commit to JJ transport.
             * The preview binds the title, body and ORG alongside the assessment.
             * Reserved machine receipt fields are refused in document
             * and headline property drawers.
             * Evidence and Open clause properties must belong to review
             * headlines and match the current assessment exactly. The
             * document-wide cardinality check uses a view of the root and
             * all clause properties. Headline ownership and reserved fields
             * are checked against the full source graph. Conflicting admitted
             * observations leave the obligation open.
             * Scheme renders structured narration against the current evidence
             * and open obligation rows. A passed model check contributes
             * its own evidence and does not replace required narration for
             * the other evidence rows. A readable unresolved preview is not
             * a prepared description when a prerequisite remains open.
             * Disclose unfinished, non-success or unavailable check
             * observations for the verified PR head. This disclosure binds
             * review context and carries no evidence about the candidate.
             * A discovery context cannot substitute for it. Current
             * operation and actual description are checked before transport.
             * Replacing the recorded engineering source invalidates its
             * earlier preview and prepared attempt even if the title,
             * engineering identity and rendered prose are unchanged.
             * Advancing the observed PR target revision invalidates the
             * earlier review even when the cut, PR head, check inventory
             * and rendered prose remain identical.
             * Signed admission binds the exact context as well as the rewrite;
             * a fresh preview cannot spend an old-context approval. */
    }
    item def LocalCommitGrant {
        doc /* Independent Governance record for one intent and cut, with expiry,
             * revocation, and single-use conditions. */
        item intent : CommitIntent;
        item preparation : PreparedDescription;
        attribute grantId : String;
        attribute policyRevision : String;
    }

    item capture : CommitCut;
    item propose : CommitIntent;
    item observe : EvidenceObservation;
    part admitObservation;
    part retainRejectedArtifact;
    part evaluate;
    item nasaAssessment : NasaCommitAssessment;
    item prepareDescription : PreparedDescription;
    item authorize : LocalCommitGrant[0..1];
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
    connection scopedAssessment connect evaluate to nasaAssessment;
    connection assessedDescription connect nasaAssessment to prepareDescription;
    connection eligibleCandidate connect prepareDescription to authorize;
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
        doc /* A rewrite, a new workspace change, a concurrent operation or
             * changed checked inputs invalidates affected evidence and grants.
             * Within the same project and workspace, losing prior support
             * reopens its obligation. Identical tree content leaves the exact
             * cut comparison in force. Apply rejects a prepared attempt for
             * another cut before Scheme evaluation. The JJ write still
             * rechecks that cut under the operation-head lock. Preserve
             * historical observations. */
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

    package AssuranceSupport {
        doc /* Judgments reference the current Assurance snapshot. The linked
             * Cases project Host witnesses and outstanding obligations.
             * Scoped assumption reviews use current Host admissions.
             * General method strength remains design. */

        item def ScopedClaim {
            attribute claimId : String;
            attribute snapshotId : String;
            attribute subjectId : String;
            attribute propositionId : String;
        }
        item def ExecutionObservation {
            attribute attemptId : String;
            attribute methodId : String;
            attribute validatedInputId : String;
            attribute consumedInputId : String;
            attribute outcome : String;
        }
        item def RecordedAgentInputObservation {
            attribute sourceOperationId : String;
            attribute sourceCommitId : String;
            attribute sourceTreeId : String;
            attribute historyPath : String;
            attribute historyDigest : String;
            attribute deliveredPacketDigest : String;
        }
        item def LiveContextDeliveryObservation {
            attribute sourceCutDigest : String;
            attribute queryObservationDigest : String;
            attribute transportAttemptId : String;
            attribute orgElementId : String;
            attribute deliveredBodyDigest : String;
        }
        item def SupportWitness {
            attribute obligationId : String;
            attribute evidenceId : String;
            attribute admissionId : String;
            attribute supportRelationId : String;
            attribute outcomeId : String;
            attribute outcomeDigest : String;
            attribute applicabilityScopeId : String;
            attribute evidenceKind : String;
            attribute capabilityId : String;
            attribute producerId : String;
            attribute toolId : String;
            attribute toolVersion : String;
            attribute expiresAt : Integer;
            attribute inputArtifactIds : String[0..*];
        }
        item def AssumptionAssessment {
            attribute assumptionId : String;
            attribute ownerId : String[0..1];
            attribute reviewPolicyId : String[0..1];
            attribute reviewObligationId : String[0..1];
            attribute reviewAdmissionId : String[0..1];
            attribute blocker : String[0..1];
        }
        item def ChallengeAssessment {
            attribute challengeId : String;
            attribute revision : String;
            attribute kind : String;
            attribute challengeState : String;
            attribute subjectId : String;
            attribute citedEvidenceId : String;
            attribute evidenceDigest : String[0..1];
            attribute applicabilityScopeId : String[0..1];
            attribute obligationId : String[0..1];
            attribute defeatRelationId : String[0..1];
        }
        item def ResidualDisposition {
            attribute obligationId : String;
            attribute decisionId : String;
            attribute authorityId : String;
            attribute policyId : String;
            attribute policyRevision : String;
            attribute reviewAdmissionId : String;
            attribute outcomeDigest : String;
        }
        item def SupportAssessment {
            item claim : ScopedClaim;
            item witnesses : SupportWitness[0..*];
            item assumptions : AssumptionAssessment[0..*];
            item challenges : ChallengeAssessment[0..*];
            item residualDispositions : ResidualDisposition[0..*];
            attribute obligationIds : String[1..*];
            attribute methodStrength : String;
            attribute applicabilityScopeId : String;
            attribute assumptionIds : String[0..*];
            attribute defeaterIds : String[0..*];
            attribute residualObligationIds : String[0..*];
            attribute sharedDependencyIds : String[0..*];
            attribute validityBindingId : String;
        }

        part applicableObjective;
        part scopedClaim;
        part rustExecution;
        part hostAdmission;
        part assessSupport;
        part openObligations;
        part governanceReview;
        part effectAdmission;

        connection instantiateClaim connect applicableObjective to scopedClaim;
        connection observedExecution connect rustExecution to hostAdmission;
        connection admittedObservation connect hostAdmission to assessSupport;
        connection scopedProposition connect scopedClaim to assessSupport;
        connection outstandingSupport connect assessSupport to openObligations;
        connection scopedJudgment connect assessSupport to governanceReview;
        connection currentAuthority connect governanceReview to effectAdmission;

        requirement preserveInputSemantics {
            doc /* Compare required meaning across the source and projection.
                 * Consume the validated input. A failed check blocks use. */
        }
        requirement boundConclusion {
            doc /* A method supports only its observed fragment and declared
                 * strength within its applicable scope. Retain residuals and
                 * recheck assumptions and defeaters on change. */
        }
        requirement separateEffectAuthority {
            doc /* Governance owns the current decision for an exact intent.
                 * An effect adapter checks the live policy revision,
                 * policy digest and entity digest, and binds the handoff
                 * sequence, length and payload digest.
                 * The executor checks authority at the effect boundary. */
        }
        package OptionalCedarIntegration {
            requirement sourceBoundConsumption {
                doc /* The Scheme Host binds the current preflight and
                     * independent Governance admission to a Cedar proposal.
                     * The Runtime authority looks up the exact proposal's
                     * admission before and after dual Cedar evaluation.
                     * Both engine receipts and the signed grant bind it.
                     * Direct and reprojected consumption share one live
                     * admission check and one grant ledger.
                     * The optional Cedar adapter shares its request registry
                     * with its configured delivery owner. The owner verifies the
                     * consumed admission, intent, sequence and payload before
                     * delivery and passes consumption provenance to the
                     * effect operation. The effect outcome is recorded
                     * separately. */
            }
            requirement privateConsumptionFailure {
                doc /* An exception during the private consume exchange
                     * retires the request in its owner. Propagate the failure
                     * and require a validated consumption receipt before
                     * calling the effect operation, including when the issuer
                     * consumed the grant but the reply was lost. A delivered result and
                     * its consumption receipt are distinct from refusal. */
            }

            requirement durableCedarDispatch {
                doc /* Commit the application-owned logical operation and consumed
                     * grant provenance before effect dispatch. Recheck the source
                     * after that commit. A fresh owner preserves dispatching and
                     * acknowledged records and refuses another dispatch for
                     * either. A definite source withdrawal before dispatch
                     * records withheld. Dispatching requires independent
                     * reconciliation when the effect outcome is unknown. */
            }

            requirement reconcileCedarDispatch {
                doc /* Query an application-configured Provider observation source
                     * for a dispatching operation. Require a committed observation
                     * with matching operation, intent and payload digests.
                     * Persist its receipt separately from grant consumption.
                     * Reconciliation grants no authority and sends no effect. */
            }
        }

        part lostAcknowledgementCase {
            item atMostOne : ScopedClaim;
            item boundedReplay : ExecutionObservation;
            item replaySupport : SupportAssessment;
            item deploymentSupport : SupportAssessment;

            requirement retryIdentity {
                doc /* Bind the same key and payload to the same tenant and
                     * logical operation across attempts and restarts. */
            }
            requirement boundedIntentConflict {
                doc /* After ACK loss, the fixture rejects a changed payload
                     * under the recorded key. */
            }
            requirement boundedConcurrentRetry {
                doc /* Two restarted workers reach the local provider
                     * before either receives an ACK.
                     * Both complete with the original payload as the sole
                     * persisted effect. The deployed provider requires
                     * independent evidence. */
            }
            requirement boundedConcurrentFirstAttempt {
                doc /* Two workers reach the local provider with an empty
                     * effect ledger. The write transaction serializes the
                     * empty-ledger check and insertion. One worker loses
                     * its ACK, the other completes, and the ledger has
                     * one effect and one completed task. */
            }
            requirement declaredAssuranceCheck {
                doc /* Resolve the recorded project declaration and fixture
                     * paths at one JJ cut. Execute the selected Cases and
                     * derive the Org observation from the actual process.
                     * The positive and negative expectations must match
                     * the admitted support and contradiction. The buggy Case
                     * must report the declared duplicate-effect assertion
                     * in its bounded JUnit result. */
            }
            requirement replayEvidenceBinding {
                doc /* Bind the owner-declared project to the recorded run
                     * at execution. Resolve the assessment workspace and
                     * require it to match the run's workspace. Admit an Org
                     * observation when the project, method, selected Case,
                     * exact JJ cut and digests agree with the recorded
                     * process. Match the Case to its declared obligation.
                     * Current passing support requires a Host witness over
                     * the exact frozen source of the run. A Case failure
                     * is scoped to its own open obligation. Execution
                     * errors leave it unassessed. */
            }
            requirement providerConditions {
                doc /* The ADR 0008 deployment assessment is separate from
                     * bounded replay support. Its open obligations cover
                     * scoped logical identity, changed intent, retention,
                     * atomic commit, and concurrent attempts and reconciliation.
                     * A provider-owner review must assess the assumption
                     * that the deployed deduplication record covers the
                     * declared retry horizon. */
            }
        }
        part agentInputCase {
            item projectedInput : RecordedAgentInputObservation;
            item liveProviderDelivery : LiveContextDeliveryObservation;
            item correspondenceSupport : SupportAssessment;

            requirement requiredRelations {
                doc /* Preserve every required tool call, result link and
                     * constraint. A result without a source call is refused. */
            }
            requirement verifiedConsumption {
                doc /* The consumer uses the verified packet. A failed check or
                     * substitution after validation blocks consumption. */
            }
            requirement observedDelivery {
                doc /* Record the digest of the exact packet delivered to a
                     * successful consumer and bind it to the recorded history.
                     * Consumer failure produces no delivery observation. */
            }
            requirement contextSourceCurrentness {
                doc /* Resolve the selected Org Element through the live
                     * Context Query owner. Bind delivery to its observation.
                     * Replacement or withdrawal reopens correspondence
                     * even when earlier source bytes are published again. */
            }
            requirement recoverContextObservations {
                doc /* Bind the Context catalog to its owning project before
                     * use. Export a project-bound checkpoint accepted by the
                     * recovery codec. Restore the owner-selected checkpoint
                     * only into a fresh catalog of the same project.
                     * A restored observation needs successful delivery or
                     * independently reconciled receipt evidence for admission. */
            }
            requirement reconcileIndeterminateDelivery {
                doc /* Distinguish a definite pre-send failure from unknown
                     * delivery. Accept a Provider acknowledgement only for
                     * the matching transport attempt and delivered body.
                     * Reconciliation performs no second send. */
            }
            requirement recoverPendingContextDelivery {
                doc /* Retain the project, attempt identity, Query observation
                     * reference and body digest before transport. After
                     * restart, recover against the trusted record and
                     * same-project Lab catalog using authenticated Provider
                     * bytes. Reconciliation creates no send operation. */
            }
            requirement retainedDeliveryAdmission {
                doc /* The first assessment of a completed delivery may
                     * admit its evidence once. Reassessment uses the
                     * same Host lease. Expiry or loss of current source
                     * closes this admission and reopens the obligation. */
            }
            requirement providerRequestBinding {
                doc /* Assemble the request using owner-selected settings
                     * and the projected input. Check the input within the
                     * final serialized request. The transport receives
                     * those bytes, and the receipt identifies that body. */
            }
            requirement admittedCorrespondence {
                doc /* The Assurance Host checks the recorded history and
                     * delivered packet as two materialized inputs. The
                     * witness applies to the required fragment of the
                     * recorded project, commit and history path. */
            }
            requirement deliveryCurrentness {
                doc /* Match the assessment project and resolved workspace to
                     * the delivery observation, then recheck the exact JJ cut.
                     * A rewrite preserves the historical delivery and reopens
                     * current support. Delivery alone grants no effect authority. */
            }
        }
    }

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
             * The Scheme owner selects the project policy for the captured
             * configuration. The Rust command holds its root while it
             * collects facts and returns that root for assessment.
             * The exchange carries identity and outcome, and issues no grants. */
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
        item grant : LocalCommitGrant[0..1];
        attribute attemptId : String;
    }

    item def GitOpsOperationReceipt {
        attribute requestId : String;
        attribute attemptId : String;
        item beforeCut : CommitCut;
        item afterCut : CommitCut;
    }

    requirement gitOpsWriteFence {
        doc /* The expected operation and any required grant must be enforced at the same
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
        doc /* Recheck the exact cut and consume any required grant within the
             * qualified local writer boundary. */
    }
    part refuseLocalWrite {
        doc /* A stale cut or revoked required grant prevents an effect. */
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
