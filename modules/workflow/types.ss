;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: strict nominal POO types and ScopeContract for Lambda Aitia's
;;; ASCENT Obligation Graph + FunFlow CAS DAG workflow domain (RFC 0008).
;;; ZERO `Any`: every FunFlow arrow edge, evidence payload, proposal, strategy,
;;; runner, and event carries an explicit POO Type / Record / Enum contract.

(import (only-in :clan/poo/object object? .slot? .ref .cc)
        (only-in :clan/poo/type Type. define-type Bool False List Object Record
                 Function Enum Or Symbol Pair)
        (only-in :clan/poo/number UInt)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/flow flow?)
        (only-in "../gitops/types.ss"
                 NonEmptyString GitOpsCommitCut GitOpsCommitNaming
                 GitOpsCommitSources GitOpsCommitProposals GitOpsCommitObservation))

(export WorkflowScopeContract
        WorkflowDomainProfileType
        WorkflowEffectClass
        WorkflowOriginTier
        WorkflowTypeDescriptor
        ProcedureType
        FlowType
        ChoiceArrowSpecType
        ObligationGraphType
        EvidenceFactType
        DeterministicTaskNodeType
        HypothesisType
        CompetingBranchType
        SynthesisProposalType
        GovernedRunnerType
        OrchestratorStrategyType
        WorkflowEventType
        ChoiceSolutionType
        ChoiceWorldType
        ChoiceFlowPlanType
        ChoiceExecutionType
        ChoiceConvergenceType
        ChoiceConvergenceStatusType
        EpistemicVerdictKind
        EpistemicProbeEvidence
        WorkflowProtocolState
        WorkflowHandoffTarget
        WorkflowGapKind
        WorkflowCheckSpecList
        OptionalCheckSpecList
        HostEffectClassKind
        HostFrameSpecType
        WorkflowProtocolStepType
        ObligationSessionType
        ChoiceStatusType
        ChoiceOptionSymbolList
        GitOpsCutRequest
        GitOpsCutEvidence
        GitOpsConfigRequest
        GitOpsConfigEvidence
        GitOpsSemanticsRequest
        GitOpsSemanticsEvidence
        GitOpsApplyRequest
        GitOpsApplyEvidence
        SdlcLifecycleRequest
        SdlcLifecycleEvidence
        WorkflowPatchRequest
        WorkflowPatchEvidence
        workflow-domain-profile?
        NonEmptyString)

(def (tagged-object? value expected-kind)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind) expected-kind)))

(def (workflow-domain-profile? value)
  (and (object? value)
       (.slot? value 'aitia-workflow-domain?)
       (.ref value 'aitia-workflow-domain?)))

(define-type (WorkflowDomainProfileType @ Type.)
  .element?: workflow-domain-profile?)

(define-type (WorkflowTypeDescriptor @ Type.)
  .element?: (lambda (value) (and (object? value) (.slot? value '.element?))))

(define-type (ProcedureType @ Type.)
  .element?: procedure?)

(define-type (FlowType @ Type.)
  .element?: flow?)

(define-type (ChoiceArrowSpecType @ Type.)
  .element?: (lambda (value)
               (and (object? value)
                    (.slot? value 'arrow)
                    (flow? (.ref value 'arrow))
                    (.slot? value 'input))))

(define-type (ObligationGraphType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'agentic-ai-lab.loop-engine.obligation-graph.v1)))

(define-type (EvidenceFactType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'agentic-ai-lab.loop-engine.evidence-fact.v1)))

(define-type (DeterministicTaskNodeType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'agentic-ai-lab.loop-engine.deterministic-task-node.v1)))

(define-type (HypothesisType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'agentic-ai-lab.loop-engine.hypothesis.v1)))

(define-type (CompetingBranchType @ Type.)
  .element?: (lambda (value) (and (object? value) (.slot? value 'branch-id))))

(define-type (SynthesisProposalType @ Type.)
  .element?: (lambda (value)
               (and (object? value)
                    (.slot? value 'kind)
                    (and (memq (.ref value 'kind)
                               '(typed-funflow-dag-patch
                                 bounded-competing-branches
                                 raw-single-step-tool-call))
                         #t))))

(define-type (GovernedRunnerType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'agentic-ai-lab.funflow.governed-runner.v1)))

(define-type (OrchestratorStrategyType @ Type.)
  .element?: (lambda (value) (and (object? value) (.slot? value '.admit-frontier))))

(define-type (ChoiceSolutionType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.choice-solution.v1)))

(define-type (ChoiceWorldType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.choice-world.v1)))

(define-type (ChoiceFlowPlanType @ Type.)
  .element?: (lambda (value)
               (and (tagged-object? value 'lambda-aitia.workflow.choice-flow-plan.v1)
                    (.slot? value 'choice-key)
                    (.slot? value 'shared-prefix)
                    (.slot? value 'branches)
                    (object? (.ref value 'branches))
                    (.slot? value 'fenced-tail))))

(define-type (ChoiceExecutionType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.choice-world-execution.v1)))

(define-type (ChoiceConvergenceType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.choice-convergence.v1)))

(define-type (ObligationSessionType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.obligation-session.v1)))

(def ChoiceStatusType
  (Enum unique-deduction competing-worlds unsatisfiable))

(def ChoiceConvergenceStatusType
  (Enum converged-unique irreducible-competition unsatisfiable plan-rejected budget-exhausted))

(def EpistemicVerdictKind
  (Enum supports refutes inconclusive))

(def EpistemicProbeEvidence
  (Record kind: [(Enum epistemic-verdict)]
          verdict: [EpistemicVerdictKind]
          option: [Symbol]
          detail: [NonEmptyString]))

(def WorkflowProtocolState
  (Enum need-host-frames
        need-agent-synthesis
        need-human-decision
        need-fenced-frames
        quiescent))

(def WorkflowHandoffTarget
  (Enum host-probe agent-synthesis human-decision host-fenced-effect none))

(def WorkflowGapKind
  (Enum model-reality-gap model-check-gap requirement-gap none))

(def WorkflowCheckSpecList
  (List (List NonEmptyString)))

(def OptionalCheckSpecList
  (Or False WorkflowCheckSpecList))

(def HostEffectClassKind
  (Enum host-read fenced-effect))

(def HostFrameSpecType
  (Record capability: [NonEmptyString]
          effect-class: [HostEffectClassKind]
          receipt-key: [NonEmptyString]
          payload: [Object]))

(define-type (WorkflowProtocolStepType @ Type.)
  .element?: (lambda (value)
               (tagged-object? value 'lambda-aitia.workflow.protocol-step.v1)))

(def ChoiceOptionSymbolList
  (List (Or Symbol NonEmptyString)))

(def ChoiceEdgePair
  (Pair (Or Symbol NonEmptyString) (Or Symbol NonEmptyString)))

(def WorkflowEffectClass
  (Enum pure-cas verified-epistemic fenced-effect))

(def WorkflowOriginTier
  (Enum observed-fact human-decision derived-claim))

(def WorkflowEventType
  (Record event-kind: [(Enum premise-retracted evidence-added)]
          premise-id: [NonEmptyString]
          cut: [UInt]))

;;; Strongly typed FunFlow arrow edge payloads (zero `Fun Any <- Any`).
(def GitOpsCutRequest
  (Record commit: [NonEmptyString] paths: [(List NonEmptyString)]))
(def GitOpsCutEvidence
  (Record kind: [(Enum observed-cut)] commit: [NonEmptyString] paths: [(List NonEmptyString)]))

(def GitOpsConfigRequest
  (Record commit: [NonEmptyString]))
(def GitOpsConfigEvidence
  (Record kind: [(Enum audited-config)] commit: [NonEmptyString]))

(def GitOpsSemanticsRequest
  (Record commit: [NonEmptyString] eligible: [(List (List NonEmptyString))]))
(def GitOpsSemanticsEvidence
  (Record kind: [(Enum semantics-eligible)] commit: [NonEmptyString] eligible: [(List (List NonEmptyString))]))

(def GitOpsApplyRequest
  (Record commit: [NonEmptyString]))
(def GitOpsApplyEvidence
  (Record kind: [(Enum commit-applied-receipt)] commit: [NonEmptyString]))

(def SdlcLifecycleRequest
  (Record change-id: [NonEmptyString] obligation-id: [NonEmptyString]))
(def SdlcLifecycleEvidence
  (Record kind: [(Enum sdlc-obligation-discharged)]
          change-id: [NonEmptyString]
          obligation-id: [NonEmptyString]))

(def WorkflowPatchRequest
  (Record action: [Symbol] targets: [(List NonEmptyString)]))
(def WorkflowPatchEvidence
  (Record kind: [(Enum synthesized-patch)] action: [Symbol] targets: [(List NonEmptyString)]))

(def WorkflowObjectPredicate (Function (list Bool) (list Object)))
(def OptionalOracleFn (Or False ProcedureType))
(def OptionalRunner (Or False GovernedRunnerType))
(def OptionalStrategy (Or False OrchestratorStrategyType))
(def OptionalCasList (Or False (List NonEmptyString)))

(def WorkflowScopeContract
  (.cc (Record domain-prototype: [WorkflowDomainProfileType]
               gitops-commit-domain: [WorkflowDomainProfileType]
               gitops-nasa-commit-domain: [WorkflowDomainProfileType]
               sdlc-lifecycle-domain: [WorkflowDomainProfileType]
               sdlc-open-security-domain: [WorkflowDomainProfileType]
               sdlc-nasa-lifecycle-domain: [WorkflowDomainProfileType]
               choice-flow-plan-prototype: [ChoiceFlowPlanType]
               profiles: [Object]
               domain?: [WorkflowObjectPredicate]
               patch-request-type: [WorkflowTypeDescriptor]
               patch-evidence-type: [WorkflowTypeDescriptor]
               probe-evidence-type: [WorkflowTypeDescriptor]
               make-pure-runner: [(Function (list GovernedRunnerType) '())]
               flow-arr:
               [(Function (list FlowType)
                          (list Symbol WorkflowTypeDescriptor WorkflowTypeDescriptor ProcedureType))]
               flow-then:
               [(Function (list FlowType)
                          (list Symbol FlowType FlowType))]
               flow-fanout:
               [(Function (list FlowType)
                          (list Symbol FlowType FlowType))]
               arrow-task-node:
               [(Function (list DeterministicTaskNodeType)
                          (list NonEmptyString NonEmptyString NonEmptyString FlowType Object)
                          keywords: (list (cons 'required-evidence-ids: (List NonEmptyString))
                                          (cons 'premise-ids: (List NonEmptyString))
                                          (cons 'read-footprint: (List Symbol))
                                          (cons 'write-footprint: (List Symbol))
                                          (cons 'effect-class: WorkflowEffectClass)))]
               choice-arrow-entry:
               [(Function (list ChoiceArrowSpecType)
                          (list FlowType Object)
                          keywords: (list (cons 'task-id: (Or False NonEmptyString))
                                          (cons 'obligation-id: NonEmptyString)
                                          (cons 'produces-evidence-id: (Or False NonEmptyString))
                                          (cons 'required-evidence-ids: (List NonEmptyString))
                                          (cons 'read-footprint: (List Symbol))
                                          (cons 'write-footprint: (List Symbol))
                                          (cons 'effect-class: WorkflowEffectClass)))]
               pure-task-node:
               [(Function (list DeterministicTaskNodeType)
                          (list NonEmptyString NonEmptyString NonEmptyString Symbol
                                WorkflowTypeDescriptor WorkflowTypeDescriptor
                                ProcedureType Object)
                          keywords: (list (cons 'required-evidence-ids: (List NonEmptyString))
                                          (cons 'premise-ids: (List NonEmptyString))
                                          (cons 'read-footprint: (List Symbol))
                                          (cons 'write-footprint: (List Symbol))
                                          (cons 'effect-class: WorkflowEffectClass)))]
               evidence-fact:
               [(Function (list EvidenceFactType) (list NonEmptyString Object)
                          keywords: (list (cons 'cut: UInt)
                                          (cons 'premise-ids: (List NonEmptyString))
                                          (cons 'origin-tier: WorkflowOriginTier)))]
               with-evidence: [(Function (list ObligationGraphType) (list ObligationGraphType EvidenceFactType))]
               live-evidence: [(Function (list (List EvidenceFactType)) (list ObligationGraphType))]
               dag-patch: [(Function (list SynthesisProposalType) (list (List DeterministicTaskNodeType)))]
               competing-branches: [(Function (list SynthesisProposalType) (list (List CompetingBranchType)))]
               raw-tool-call: [(Function (list SynthesisProposalType) (list Symbol (List NonEmptyString)))]
               gitops-commit-graph:
               [(Function (list ObligationGraphType)
                          (list GitOpsCommitNaming GitOpsCommitCut GitOpsCommitSources
                                (List NonEmptyString) GitOpsCommitProposals)
                          keywords: (list (cons 'graph-id: NonEmptyString)
                                          (cons 'profile: NonEmptyString)
                                          (cons 'required-checks: OptionalCheckSpecList)
                                          (cons 'cut-index: UInt)
                                          (cons 'observations: (List GitOpsCommitObservation))
                                          (cons 'approval-live?: Bool)
                                          (cons 'cedar-grant-live?: Bool)
                                          (cons 'candidate-offers: ChoiceOptionSymbolList)
                                          (cons 'forbidden-scopes: ChoiceOptionSymbolList)
                                          (cons 'state-budget: UInt)
                                          (cons 'extra-hypotheses: (List HypothesisType))
                                          (cons 'extra-evidence: (List EvidenceFactType))
                                          (cons 'extra-tasks: (List DeterministicTaskNodeType))))]
               sdlc-lifecycle-graph:
               [(Function (list ObligationGraphType)
                          (list NonEmptyString ChoiceOptionSymbolList)
                          keywords: (list (cons 'graph-id: NonEmptyString)
                                          (cons 'profile: NonEmptyString)
                                          (cons 'extra-obligations: (List NonEmptyString))
                                          (cons 'observed-obligations: (List NonEmptyString))
                                          (cons 'requirements-traced?: Bool)
                                          (cons 'verified?: Bool)
                                          (cons 'retirement-clear?: Bool)
                                          (cons 'approval-live?: Bool)
                                          (cons 'release-published?: Bool)
                                          (cons 'refuted-designs: ChoiceOptionSymbolList)
                                          (cons 'required-design: (Or False Symbol NonEmptyString))
                                          (cons 'cut-index: UInt)
                                          (cons 'state-budget: UInt)
                                          (cons 'extra-evidence: (List EvidenceFactType))))]
               solve-gitops-choices:
               [(Function (list ChoiceSolutionType)
                          (list Object GitOpsCommitCut)
                          keywords: (list (cons 'approval-live?: Bool)
                                          (cons 'candidate-offers: ChoiceOptionSymbolList)
                                          (cons 'forbidden-scopes: ChoiceOptionSymbolList)
                                          (cons 'state-budget: UInt)))]
               solve-sdlc-choices:
               [(Function (list ChoiceSolutionType)
                          (list (Or Symbol NonEmptyString) ChoiceOptionSymbolList)
                          keywords: (list (cons 'verified?: Bool)
                                          (cons 'retirement-clear?: Bool)
                                          (cons 'approval-live?: Bool)
                                          (cons 'refuted-designs: ChoiceOptionSymbolList)
                                          (cons 'required-design: (Or False Symbol NonEmptyString))
                                          (cons 'state-budget: UInt)))]
               choice-flow-plan:
               [(Function (list ChoiceFlowPlanType)
                          (list Object)
                          keywords: (list (cons 'choice-key: Symbol)
                                          (cons 'shared-prefix: (List (Or DeterministicTaskNodeType ChoiceArrowSpecType)))
                                          (cons 'fenced-tail: (List DeterministicTaskNodeType))))]
               execute-choice-worlds:
               [(Function (list ChoiceExecutionType)
                          (list ChoiceSolutionType GovernedRunnerType ChoiceFlowPlanType)
                          keywords: (list (cons 'approval-live?: Bool)))]
               converge-choice-worlds:
               [(Function (list ChoiceConvergenceType)
                          (list ProcedureType GovernedRunnerType ChoiceFlowPlanType)
                          keywords: (list (cons 'max-rounds: UInt)
                                          (cons 'approval-live?: Bool)
                                          (cons 'initial-refuted: ChoiceOptionSymbolList)))]
               open-obligation-session:
               [(Function (list ObligationSessionType)
                          (list ChoiceOptionSymbolList (List ChoiceEdgePair) (List ChoiceEdgePair))
                          keywords: (list (cons 'live-evidence: ChoiceOptionSymbolList)
                                          (cons 'active-defeaters: ChoiceOptionSymbolList)))]
               session-snapshot: [(Function (list Object) (list ObligationSessionType))]
               session-append-evidence!:
               [(Function (list Object) (list ObligationSessionType (Or Symbol NonEmptyString)))]
               session-retract-evidence!:
               [(Function (list Object) (list ObligationSessionType ChoiceOptionSymbolList))]
               reconcile-frontier:
               [(Function (list Object) (list ObligationGraphType)
                          keywords: (list (cons 'strategy: OptionalStrategy)
                                          (cons 'completed-cas: OptionalCasList)))]
               admit-proposal:
               [(Function (list Object) (list ObligationGraphType SynthesisProposalType)
                          keywords: (list (cons 'max-branches: UInt)))]
               reconcile-step:
               [(Function (list Object) (list ObligationGraphType)
                          keywords: (list (cons 'oracle-fn: OptionalOracleFn)
                                          (cons 'funflow-runner: OptionalRunner)
                                          (cons 'dag-strategy: OptionalStrategy)
                                          (cons 'completed-cas: OptionalCasList)))]
               reconcile:
               [(Function (list Object) (list ObligationGraphType)
                          keywords: (list (cons 'oracle-fn: OptionalOracleFn)
                                          (cons 'funflow-runner: OptionalRunner)
                                          (cons 'dag-strategy: OptionalStrategy)
                                          (cons 'completed-cas: OptionalCasList)))]
               reconcile-events:
               [(Function (list Object) (list ObligationGraphType (List WorkflowEventType))
                          keywords: (list (cons 'oracle-fn: OptionalOracleFn)
                                          (cons 'funflow-runner: OptionalRunner)
                                          (cons 'dag-strategy: OptionalStrategy)
                                          (cons 'completed-cas: OptionalCasList)))]
               retract-premise:
               [(Function (list ObligationGraphType) (list ObligationGraphType NonEmptyString)
                          keywords: (list (cons 'new-cut: (Or False UInt))))]
               plan-protocol-step:
               [(Function (list WorkflowProtocolStepType) (list Object))])
       identity: 'workflow/scope))
