;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        "types.ss"
        "objects.ss"
        "func.ss"
        "reconcile.ss")
(export Config
        GitOpsCommitCaseProfile.
        UnscopedScopeAuditCaseProfile.
        SdlcLifecycleCaseProfile.
        WorkflowCaseProfiles.)

;;; Role: `config.ss` owns Profile & Case DAG/Flow composition via pure POO
;;; prototype inheritance (`:: @`), without inventing a custom workflow DSL.
(.def (GitOpsCommitCaseProfile. @ GitOpsCommitWorkflowDomain.)
  case-id: 'aitia/case/gitops-commit
  choice-key: 'scope-decision
  state-budget: 32
  allow-fenced-in-competition?: #f
  choice-plan-prototype: ChoiceFlowPlan.
  build-graph: workflow-gitops-commit-graph
  build-choice-plan: workflow-choice-flow-plan
  execute-plan: workflow-execute-choice-worlds
  reconcile: workflow-reconcile)

(.def (UnscopedScopeAuditCaseProfile. @ GitOpsCommitCaseProfile.)
  case-id: 'aitia/case/unscoped-scope-audit
  default-max-branches: 4
  allow-fenced-in-competition?: #f)

(.def (SdlcLifecycleCaseProfile. @ SdlcLifecycleWorkflowDomain.)
  case-id: 'aitia/case/sdlc-lifecycle
  choice-key: 'design-decision
  state-budget: 32
  allow-fenced-in-competition?: #f
  choice-plan-prototype: ChoiceFlowPlan.
  solve-choices: workflow-solve-sdlc-choices
  build-choice-plan: workflow-choice-flow-plan
  execute-plan: workflow-execute-choice-worlds)

(.def WorkflowCaseProfiles.
  gitops-commit: GitOpsCommitCaseProfile.
  unscoped-scope-audit: UnscopedScopeAuditCaseProfile.
  sdlc-lifecycle: SdlcLifecycleCaseProfile.)

(def Config
  (.o domain-prototype: AitiaWorkflowDomain.
      gitops-commit-domain: GitOpsCommitWorkflowDomain.
      sdlc-lifecycle-domain: SdlcLifecycleWorkflowDomain.
      choice-flow-plan-prototype: ChoiceFlowPlan.
      profiles: WorkflowCaseProfiles.
      domain?: workflow-domain-profile?
      patch-request-type: WorkflowPatchRequest
      patch-evidence-type: WorkflowPatchEvidence
      make-pure-runner: workflow-make-pure-runner
      pure-task-node: workflow-pure-task-node
      evidence-fact: workflow-evidence-fact
      with-evidence: workflow-with-evidence
      live-evidence: workflow-live-evidence
      dag-patch: workflow-dag-patch
      competing-branches: workflow-competing-branches
      raw-tool-call: workflow-raw-tool-call
      solve-gitops-choices: workflow-solve-gitops-choices
      solve-sdlc-choices: workflow-solve-sdlc-choices
      choice-flow-plan: workflow-choice-flow-plan
      execute-choice-worlds: workflow-execute-choice-worlds
      open-obligation-session: workflow-open-obligation-session
      session-snapshot: workflow-session-snapshot
      session-append-evidence!: workflow-session-append-evidence!
      session-retract-evidence!: workflow-session-retract-evidence!
      gitops-commit-graph: workflow-gitops-commit-graph
      reconcile-frontier: workflow-reconcile-frontier
      admit-proposal: workflow-admit-proposal
      reconcile-step: workflow-reconcile-step
      reconcile: workflow-reconcile
      reconcile-events: workflow-reconcile-events
      retract-premise: workflow-retract-premise))
