;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Profile slot dispatch is the normal extension path. CLOS owns the optional
;;; evaluator strategy axis where provider/runtime specializers may combine.
(import (only-in :clan/poo/object .def .o)
        (only-in :clan/poo/mop .defgeneric .new)
        (only-in :poo-flow/src/module-system/poo-clos/interface
                 poo-clos-call
                 poo-clos-class
                 poo-clos-generic-function
                 poo-clos-generic-protocol
                 poo-clos-make-instance)
        (only-in :poo-flow/src/module-system/contribution/objects
                 make-contribution)
        :poo-flow/lambda-aitia/modules/gitops/types)
(export GitOpsEvaluator GitOpsDefaultEvaluator
        GitOpsEvaluationProtocol GitOpsEvaluationGeneric
        GitOpsProfile OpenGitOpsProfile GitOpsModule
        gitops-profile-matches?
        gitops-change gitops-check gitops-evaluate)

(.defgeneric (gitops-profile-matches? profile change)
  slot: .matches?)

(def GitOpsProfile
  (.o gitops-profile?: #t
      identity: "gitops/profile"
      owner: 'lambda-aitia
      name: 'gitops
      environment: 'unbound
      event: 'reconciliation
      target-ref: "unbound"
      required-checks: '()
      reconciliation: 'continuous
      next-profile: 'complete
      principles: '()
      source-url: #f
      runtime-executed: #f
      .matches?: (lambda (_change) #f)))

(.def (OpenGitOpsProfile @ GitOpsProfile)
  ;; The public identity is stable; standard revisions belong in evidence,
  ;; not in Scheme/Python namespaces or exported binding names.
  (identity "open-gitops")
  (name 'open-gitops)
  (principles '(declarative versioned-and-immutable pulled-automatically
                continuously-reconciled))
  (source-url "https://opengitops.dev/"))

(def GitOpsEvaluator (poo-clos-class 'gitops/evaluator))
(def GitOpsDefaultEvaluator (poo-clos-make-instance GitOpsEvaluator))
(def GitOpsEvaluationProtocol
  (poo-clos-generic-protocol 'gitops/evaluate))
(def GitOpsEvaluationGeneric
  (poo-clos-generic-function 'gitops-evaluate 4
    protocol: GitOpsEvaluationProtocol))
(def (gitops-evaluate composition change checks)
  (poo-clos-call GitOpsEvaluationGeneric GitOpsDefaultEvaluator
                 composition change checks))

(def GitOpsModule
  (make-contribution
   "lambda-aitia/gitops" "1" "lambda-aitia"
   OpenGitOpsProfile '(delivery-governance) '()))
(def (gitops-change provider-value event-value repository-value revision-value
                    source-ref-value target-ref-value pull-request-value)
  (.new GitOpsChange
    provider: provider-value event: event-value repository: repository-value
    revision: revision-value source-ref: source-ref-value
    target-ref: target-ref-value pull-request: pull-request-value))
(def (gitops-check name-value repository-value revision-value conclusion-value)
  (.new GitOpsCheck name: name-value repository: repository-value
        revision: revision-value conclusion: conclusion-value))
