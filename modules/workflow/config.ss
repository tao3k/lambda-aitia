;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        "types.ss"
        "objects.ss"
        "func.ss"
        "reconcile.ss")
(export Config)

(def Config
  (.o domain-prototype: AitiaWorkflowDomain.
      gitops-commit-domain: GitOpsCommitWorkflowDomain.
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
      gitops-commit-graph: workflow-gitops-commit-graph
      reconcile-frontier: workflow-reconcile-frontier
      admit-proposal: workflow-admit-proposal
      reconcile-step: workflow-reconcile-step
      reconcile: workflow-reconcile
      reconcile-events: workflow-reconcile-events
      retract-premise: workflow-retract-premise))
