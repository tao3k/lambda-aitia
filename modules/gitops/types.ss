;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; GitOps uses gerbil-poo Class descriptors for data and a reusable Type trait
;;; for environment Profile behavior.
(import :clan/poo/object :clan/poo/mop :clan/poo/type :clan/poo/number
        :clan/poo/brace)
(export GitOpsScopeContract NonEmptyString GitOpsEvent GitOpsCheckConclusion
        GitOpsChange GitOpsCheck GitOpsDecision
        GitOpsCommitCut GitOpsCommitObligations GitOpsCommitObservation GitOpsCommitObservations
        GitOpsModelMappings GitOpsModelProperties
        gitops-profile? gitops-change? gitops-check? gitops-decision?)

(define-type (NonEmptyString @ String)
  .element?: (lambda (value)
               (and (string? value) (> (string-length value) 0))))
(def GitOpsEvent
  (Enum push pull-request workflow-dispatch reconciliation))
(def GitOpsCheckConclusion
  (Enum success failure cancelled pending skipped))

(define-type (GitOpsChange @ Class.)
  slots: =>.+
  {provider: {type: Symbol}
   event: {type: GitOpsEvent}
   repository: {type: NonEmptyString}
   revision: {type: NonEmptyString}
   source-ref: {type: NonEmptyString}
   target-ref: {type: NonEmptyString}
   pull-request: {type: (Or False UInt)}})
(define-type (GitOpsCheck @ Class.)
  slots: =>.+
  {name: {type: Symbol}
   repository: {type: NonEmptyString}
   revision: {type: NonEmptyString}
   conclusion: {type: GitOpsCheckConclusion}
   standard-edition: {type: (Or False NonEmptyString)}
   source-lock-digest: {type: (Or False NonEmptyString)}})
(define-type (GitOpsDecision @ Class.)
  slots: =>.+
  {repository: {type: NonEmptyString}
   revision: {type: NonEmptyString}
   profile: {type: Symbol}
   accepted: {type: Bool}
   next-profile: {type: Symbol}
   environment: {type: Symbol}
   required-checks: {type: (List Symbol)}
   standards: {type: (List Symbol)}
   missing-checks: {type: (List Symbol)}
   failed-checks: {type: (List Symbol)}
   check-blockers: {type: (List GitOpsCheck)}
   stale-checks: {type: (List Symbol)}
   reasons: {type: (List Symbol)}})

(def (gitops-profile? value)
  (and (object? value) (.slot? value 'gitops-profile?)
       (.ref value 'gitops-profile?)))
(def (gitops-change? value) (element? GitOpsChange value))
(def (gitops-check? value) (element? GitOpsCheck value))
(def (gitops-decision? value) (element? GitOpsDecision value))

(define-type (GitOpsProfileType @ Type.)
  .element?: gitops-profile?)
(def Predicate (Function (list Bool) (list Any)))

(def GitOpsCommitCut
  (Record project: [NonEmptyString] workspace: [NonEmptyString]
          change: [NonEmptyString] operation: [NonEmptyString]
          commit: [NonEmptyString] tree: [NonEmptyString]
          parents: [(List NonEmptyString)]))
(def GitOpsCommitObligations (List NonEmptyString))
(def GitOpsCommitObservation
  (Record cut: [GitOpsCommitCut] identity: [NonEmptyString]
          obligation: [NonEmptyString] outcome: [(Enum passed failed)]))
(def GitOpsCommitObservations (List GitOpsCommitObservation))
(def GitOpsCommitExecution
  (Record observation: [GitOpsCommitObservation] producer: [NonEmptyString]
          method: [NonEmptyString] input-digest: [NonEmptyString]
          report-digest: [NonEmptyString]))
(def GitOpsCommitCandidates
  (List (Record source: [String] execution: [GitOpsCommitExecution])))

(def GitOpsModelMappings
  (List (Record design: [NonEmptyString] model: [NonEmptyString]
                property: [NonEmptyString])))
(def GitOpsModelProperties
  (List (Record model: [NonEmptyString] property: [NonEmptyString])))

(def GitOpsScopeContract
  (.cc (Record profile: [GitOpsProfileType]
               profile?: [Predicate] change?: [Predicate]
               check?: [Predicate] decision?: [Predicate]
               change: [(Function (list GitOpsChange)
                                  (list Symbol GitOpsEvent NonEmptyString NonEmptyString
                                        NonEmptyString NonEmptyString (Or False UInt)))]
               check: [(Function (list GitOpsCheck)
                                 (list Symbol NonEmptyString NonEmptyString GitOpsCheckConclusion)
                                 keywords: (list (cons 'standard-edition: (Or False NonEmptyString))
                                                 (cons 'source-lock-digest: (Or False NonEmptyString))))]
               matches?: [(Function (list Bool) (list GitOpsProfileType Any))]
               match-change: [(Function (list Predicate) (list GitOpsEvent NonEmptyString))]
               evaluate: [(Function (list GitOpsDecision)
                                    (list Object GitOpsChange (List GitOpsCheck)))]
               admit-commit-observation:
               [(Function (list (Or False GitOpsCommitObservation))
                          (list String GitOpsCommitObservation NonEmptyString))]
               commit-intent: [(Function (list NonEmptyString) (list NonEmptyString String))]
               record-commit-approval!: [(Function (list Bool) (list Any Object))]
               revoke-commit-approval!: [(Function (list Bool) (list Any NonEmptyString NonEmptyString))]
               consume-commit-admission!:
               [(Function (list (Or False Object))
                          (list Any NonEmptyString String NonEmptyString NonEmptyString
                                (Function (list UInt) '())))]
               commit-admission: [(Function (list (Or False Object)) (list Any NonEmptyString NonEmptyString))]
               commit-check-receipt: [(Function (list String) (list GitOpsCommitExecution))]
               nasa-draft-requirements: [(Function (list Object)
                 (list Object GitOpsCommitCut GitOpsCommitCandidates))]
               nasa-commit-description: [(Function (list Object)
                 (list Object GitOpsCommitCut GitOpsCommitCandidates String String String String))]
               commit-evidence: [(Function (list Object)
                                           (list GitOpsCommitCut GitOpsCommitObligations
                                                 GitOpsCommitObservations))]
               model-gaps: [(Function (list Object)
                                      (list GitOpsModelMappings (List NonEmptyString)
                                            GitOpsModelProperties))])
       identity: 'gitops/scope))
