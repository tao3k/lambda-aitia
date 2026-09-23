;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref .slot? object?)
        :poo-flow/src/module-system/contribution/model
        :std/list/list)

(export assurance-text? assurance-digest?
        assurance-node-kind? assurance-state? assurance-relation-plane?
        assurance-relation-kind? assurance-relation-kind-plane
        assurance-modality? assurance-evidence-kind?
        +assurance-node-kinds+ +assurance-states+
        +assurance-relation-planes+ +assurance-modalities+
        +assurance-evidence-kinds+
        AssuranceNode AssuranceArtifact AssuranceClaim AssuranceAssumption
        AssuranceObservation AssuranceEvent AssuranceAction
        AssuranceObligation AssuranceEvidence AssuranceCounterexample
        AssuranceFinding AssuranceDecision AssuranceEffect
        AssuranceRelation AssuranceSnapshot
        AssuranceReplacementRequirement AssuranceReplacementDerivation
        AssuranceReplacementDeclarationReceipt
        AssuranceVerificationPolicy AssuranceVerificationRequest
        AssuranceVerificationPlan AssuranceVerifierCandidate
        AssuranceVerifierChoice AssuranceVerifierChoiceReceipt
        AssuranceVerifierInput AssuranceVerifierOutcome
        AssuranceEvidenceAdmissionReceipt AssuranceVerificationSubject
        AssuranceRequiredSupport AssessmentRequiredSupport
        AssuranceDecisionPreflight
        AssuranceCompositionRequirement AssuranceCompositionDerivation
        make-assurance-invalidation-receipt-record
        assurance-node? assurance-artifact? assurance-claim?
        assurance-assumption? assurance-observation? assurance-event?
        assurance-action? assurance-obligation? assurance-evidence?
        assurance-counterexample? assurance-finding? assurance-decision?
        assurance-effect? assurance-relation? assurance-snapshot?
        assurance-replacement-requirement?
        assurance-replacement-derivation?
        assurance-replacement-declaration-receipt?
        assurance-invalidation-receipt? assurance-invalidation-receipt-ref
        assurance-verification-policy? assurance-verification-request?
        assurance-verification-plan? assurance-verifier-candidate?
        assurance-verifier-choice? assurance-verifier-choice-receipt?
        assurance-verifier-input? assurance-verifier-outcome?
        assurance-evidence-admission-receipt?
        assurance-required-support? assessment-required-support?
        assurance-decision-preflight?
        assurance-verification-subject?
        assurance-composition-requirement?
        assurance-composition-derivation?)

(def +assurance-node-kinds+
  '(artifact claim assumption observation event action obligation evidence
    counterexample finding decision effect))
(def +assurance-states+
  '(supported violated unknown stale conflicted hypothesized counterfactual
    not-applicable))
(def +assurance-relation-planes+
  '(provenance structural causal assurance authority))
(def +assurance-modalities+
  '(observed declared derived hypothesized counterfactual))
(def +assurance-evidence-kinds+
  '(proof model-check replay unit-test integration-test native-test
    static-analysis authorization-differential human-review))

(def +assurance-relation-kind-planes+
  '((derived-from . provenance)
    (generated-by . provenance)
    (cites . provenance)
    (used . provenance)
    (depends-on . structural)
    (composes . structural)
    (implements . structural)
    (tests . structural)
    (refines . structural)
    (precedes . causal)
    (causal-parent . causal)
    (enables . causal)
    (prevents . causal)
    (supports . assurance)
    (discharges . assurance)
    (defeats . assurance)
    (invalidates . assurance)
    (authorizes . authority)
    (denies . authority)
    (requires-review . authority)))

(def (assurance-text? value)
  (and (string? value) (> (string-length value) 0)))
(def (assurance-digest? value)
  (and (string? value)
       (= (string-length value) 71)
       (string=? (substring value 0 7) "sha256:")
       (every (lambda (character)
                (or (char<=? #\0 character #\9)
                    (char<=? #\a character #\f)))
              (string->list (substring value 7 71)))))
(def (assurance-node-kind? value) (if (memq value +assurance-node-kinds+) #t #f))
(def (assurance-state? value) (if (memq value +assurance-states+) #t #f))
(def (assurance-relation-plane? value)
  (if (memq value +assurance-relation-planes+) #t #f))
(def (assurance-modality? value) (if (memq value +assurance-modalities+) #t #f))
(def (assurance-evidence-kind? value)
  (if (memq value +assurance-evidence-kinds+) #t #f))
(def (assurance-relation-kind-plane value)
  (let ((entry (assq value +assurance-relation-kind-planes+)))
    (and entry (cdr entry))))
(def (assurance-relation-kind? value)
  (if (assurance-relation-kind-plane value) #t #f))

(def (text-slot name)
  (poo-clos-direct-slot-definition name type-predicate: assurance-text?))
(def (enum-slot name predicate)
  (poo-clos-direct-slot-definition name type-predicate: predicate))
(def (maybe-text? value) (or (not value) (assurance-text? value)))
(def (maybe-digest? value) (or (not value) (assurance-digest? value)))
(def (text-list? values)
  (and (list? values) (every assurance-text? values)))
(def (symbol-list? values)
  (and (list? values) (every symbol? values)))
(def (evidence-kind-list? values)
  (and (list? values) (pair? values)
       (every assurance-evidence-kind? values)))
(def (verifier-choice-reason? value)
  (memq value '(chosen request-blocked evidence-kind-unsupported
                capability-mismatch lower-priority)))
(def (composition-blocker? value)
  (or (not value)
      (memq value '(conflicted-snapshot unresolved-frontier
                    invalid-composition-claim insufficient-components
                    invalid-component-claim missing-direct-obligation
                    stale-direct-obligation))))
(def (verification-blocker? value)
  (or (not value)
      (memq value '(conflicted-snapshot unresolved-frontier
                    capability-unavailable stale-obligation
                    dependency-unplanned dependency-blocked
                    dependency-cycle))))
(def (replacement-blocker? value)
  (or (not value)
      (memq value '(source-conflicted source-unresolved change-unresolved
                    stale-source
                    target-unchanged target-conflicted target-unresolved
                    target-identity-changed graph-changed
                    policy-changed claim-missing claim-changed))))
(def (replacement-declaration-blocker? value)
  (or (not value)
      (memq value '(derivation-mismatch source-requirement-missing
                    source-requirement-blocked target-frontier
                    candidate-missing candidate-not-fresh candidate-not-unbound
                    candidate-not-unknown candidate-claim-mismatch
                    candidate-subject-mismatch candidate-scope-mismatch
                    claim-not-declared support-link-missing
                    support-link-hypothetical))))
(def (revision-bindings? values)
  (and (list? values)
       (every (lambda (binding)
                (and (pair? binding)
                     (assurance-text? (car binding))
                     (assurance-text? (cdr binding))))
              values)))
(def (witness-list? values)
  (and (list? values) (every text-list? values)))
(def (invalidation-trajectories? values)
  (and (list? values)
       (every (lambda (entry)
                (and (list? entry)
                     (= (length entry) 3)
                     (assurance-text? (car entry))
                     (text-list? (cadr entry))
                     (text-list? (caddr entry))))
              values)))
(def (nonnegative-integer? value)
  (and (integer? value) (>= value 0)))
(def (one-of values)
  (lambda (value) (if (memq value values) #t #f)))

(def (node-slots)
  (list (text-slot 'identity)
        (enum-slot 'kind assurance-node-kind?)
        (text-slot 'revision)
        (enum-slot 'state assurance-state?)
        (enum-slot 'content-digest assurance-digest?)))
(def (node-class identity)
  (poo-clos-class identity direct-slots: (node-slots)))
(def AssuranceNode (node-class 'aitia/assurance-node))
(def (semantic-node-class identity slots)
  (poo-clos-class identity direct-slots: (append (node-slots) slots)))
(def AssuranceArtifact
  (semantic-node-class
   'aitia/artifact
   (list (text-slot 'owner) (enum-slot 'media-kind symbol?)
         (enum-slot 'provenance text-list?))))
(def AssuranceClaim
  (semantic-node-class
   'aitia/claim
   (list (text-slot 'subject) (text-slot 'predicate)
         (enum-slot 'assumptions text-list?) (enum-slot 'defeaters text-list?)
         (enum-slot 'support-requirements text-list?) (text-slot 'scope)
         (text-slot 'valid-from) (enum-slot 'valid-until maybe-text?))))
(def AssuranceAssumption
  (semantic-node-class
   'aitia/assumption
   (list (text-slot 'owner) (text-slot 'scope) (text-slot 'review-policy)
         (enum-slot 'expires-at maybe-text?))))
(def AssuranceObservation
  (semantic-node-class
   'aitia/observation
   (list (text-slot 'subject) (text-slot 'source)
         (enum-slot 'clock-role symbol?)
         (enum-slot 'logical-position nonnegative-integer?))))
(def AssuranceEvent
  (semantic-node-class
   'aitia/event
   (list (text-slot 'subject) (enum-slot 'event-kind symbol?)
         (text-slot 'observation) (enum-slot 'payload-digest assurance-digest?)
         (enum-slot 'modality assurance-modality?)
         (enum-slot 'commitment-state (one-of '(proposed committed revoked)))
         (enum-slot 'causal-parents text-list?))))
(def AssuranceAction
  (semantic-node-class
   'aitia/action
   (list (text-slot 'subject) (enum-slot 'action-kind symbol?)
         (text-slot 'requested-by) (text-slot 'scope))))
(def AssuranceObligation
  (semantic-node-class
   'aitia/obligation
   (list (text-slot 'subject) (text-slot 'claim) (text-slot 'snapshot)
         (enum-slot 'snapshot-revision maybe-text?)
         (enum-slot 'snapshot-context-digest maybe-digest?)
         (enum-slot 'evidence-kind assurance-evidence-kind?)
         (enum-slot 'capability symbol?)
         (text-slot 'scope))))
(def AssuranceEvidence
  (semantic-node-class
   'aitia/evidence
   (list (text-slot 'producer) (text-slot 'tool) (text-slot 'tool-version)
         (enum-slot 'input-artifacts text-list?) (text-slot 'obligation)
         (text-slot 'subject) (text-slot 'scope) (text-slot 'valid-from)
         (enum-slot 'valid-until maybe-text?)
         (enum-slot 'admission-state
                    (one-of '(candidate admitted rejected stale))))))
(def AssuranceCounterexample
  (semantic-node-class
   'aitia/counterexample
   (list (text-slot 'subject) (text-slot 'challenges) (text-slot 'evidence)
         (enum-slot 'details-digest assurance-digest?))))
(def AssuranceFinding
  (semantic-node-class
   'aitia/finding
   (list (text-slot 'subject) (text-slot 'challenges) (text-slot 'evidence)
         (enum-slot 'finding-kind symbol?))))
(def AssuranceDecision
  (semantic-node-class
   'aitia/decision
   (list (text-slot 'subject) (text-slot 'snapshot) (text-slot 'policy)
         (text-slot 'authority)
         (enum-slot 'outcome (one-of '(allow deny review unknown))))))
(def AssuranceEffect
  (semantic-node-class
   'aitia/effect
   (list (text-slot 'subject) (text-slot 'decision)
         (enum-slot 'effect-kind symbol?)
         (enum-slot 'effect-state
                    (one-of '(requested blocked started completed failed revoked))))))

(def AssuranceRelation
  (poo-clos-class 'aitia/assurance-relation
    direct-slots:
    (list (text-slot 'identity)
          (enum-slot 'plane assurance-relation-plane?)
          (enum-slot 'relation assurance-relation-kind?)
          (text-slot 'source)
          (text-slot 'target)
          (enum-slot 'modality assurance-modality?))))

(def (node-list? values)
  (and (list? values) (every assurance-node? values)))
(def (relation-list? values)
  (and (list? values) (every assurance-relation? values)))
(def AssuranceSnapshot
  (poo-clos-class 'aitia/assurance-snapshot
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'revision)
          (text-slot 'graph-identity)
          (enum-slot 'source-revisions revision-bindings?)
          (enum-slot 'claim-revisions revision-bindings?)
          (text-slot 'fact-cut)
          (text-slot 'policy-identity)
          (text-slot 'policy-revision)
          (enum-slot 'evidence-identities text-list?)
          (enum-slot 'state assurance-state?)
          (enum-slot 'context-digest assurance-digest?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'nodes node-list?)
          (enum-slot 'relations relation-list?)
          (enum-slot 'unresolved text-list?)
          (enum-slot 'conflicts text-list?))))

;;; A derivation names questions requiring a fresh declaration; it does not
;;; construct, bind, discharge or authorize a replacement obligation.
(def AssuranceReplacementRequirement
  (poo-clos-class 'aitia/replacement-requirement
    direct-slots:
    (list (text-slot 'source-obligation)
          (text-slot 'source-revision)
          (text-slot 'claim)
          (text-slot 'subject)
          (enum-slot 'evidence-kind assurance-evidence-kind?)
          (enum-slot 'capability symbol?)
          (text-slot 'scope)
          (enum-slot 'blocker replacement-blocker?))))
(def (replacement-requirement-list? values)
  (and (list? values) (every assurance-replacement-requirement? values)))
(def AssuranceReplacementDerivation
  (poo-clos-class 'aitia/replacement-derivation
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.replacement-requirements")))
          (text-slot 'identity)
          (enum-slot 'source-snapshot-digest assurance-digest?)
          (enum-slot 'target-snapshot-digest assurance-digest?)
          (enum-slot 'changed text-list?)
          (enum-slot 'witnesses invalidation-trajectories?)
          (enum-slot 'unresolved text-list?)
          (enum-slot 'requirements replacement-requirement-list?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; A caller-authored target obligation is checked and bound, never invented.
;;; This receipt is inert even when its blocker is false.
(def AssuranceReplacementDeclarationReceipt
  (poo-clos-class 'aitia/replacement-declaration-receipt
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.replacement-declaration")))
          (text-slot 'identity)
          (enum-slot 'derivation-digest assurance-digest?)
          (enum-slot 'source-snapshot-digest assurance-digest?)
          (enum-slot 'draft-snapshot-digest assurance-digest?)
          (enum-slot 'final-snapshot-digest maybe-digest?)
          (text-slot 'source-obligation)
          (text-slot 'target-obligation)
          (enum-slot 'blocker replacement-declaration-blocker?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; Public planning values remain POO-native and contain no executable hook.
(def AssuranceVerificationPolicy
  (poo-clos-class 'aitia/verification-policy
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'revision)
          (enum-slot 'capabilities symbol-list?)
          (enum-slot 'planner-executes? (one-of '(#f)))
          (enum-slot 'grants-authority? (one-of '(#f))))))
(def AssuranceVerificationRequest
  (poo-clos-class 'aitia/verification-request
    direct-slots:
    (list (text-slot 'obligation-identity)
          (text-slot 'subject)
          (text-slot 'claim)
          (enum-slot 'snapshot-digest assurance-digest?)
          (enum-slot 'evidence-kind assurance-evidence-kind?)
          (enum-slot 'capability symbol?)
          (enum-slot 'dependencies text-list?)
          (enum-slot 'selected? boolean?)
          (enum-slot 'blocker verification-blocker?))))
(def (verification-request-list? values)
  (and (list? values)
       (every (lambda (value)
                (assurance-verification-request? value))
              values)))
(def AssuranceVerificationPlan
  (poo-clos-class 'aitia/verification-plan
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.planning-result")))
          (text-slot 'identity)
          (enum-slot 'snapshot-digest assurance-digest?)
          (text-slot 'policy-identity)
          (text-slot 'policy-revision)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'selected-obligations text-list?)
          (enum-slot 'blocked-obligations text-list?)
          (enum-slot 'changed text-list?)
          (enum-slot 'impacted text-list?)
          (enum-slot 'blocked-effects text-list?)
          (enum-slot 'cycle-path text-list?)
          (enum-slot 'cyclic-components witness-list?)
          (enum-slot 'witnesses invalidation-trajectories?)
          (enum-slot 'requests verification-request-list?)
          (enum-slot 'unresolved text-list?)
          (enum-slot 'conflicts text-list?)
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f)))
          (enum-slot 'runtime-executed? (one-of '(#f))))))

;;; These are declared candidates and inert explanation values, never adapter
;;; handles or execution receipts.
(def AssuranceVerifierCandidate
  (poo-clos-class 'aitia/verifier-candidate
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'revision)
          (enum-slot 'priority nonnegative-integer?)
          (enum-slot 'evidence-kinds evidence-kind-list?)
          (enum-slot 'capability symbol?))))
(def (verifier-candidate-list? values)
  (and (list? values) (every assurance-verifier-candidate? values)))
(def AssuranceVerifierChoice
  (poo-clos-class 'aitia/verifier-choice
    direct-slots:
    (list (text-slot 'obligation-identity)
          (text-slot 'candidate-identity)
          (enum-slot 'selected? boolean?)
          (enum-slot 'reason verifier-choice-reason?))))
(def (verifier-choice-list? values)
  (and (list? values) (every assurance-verifier-choice? values)))
(def AssuranceVerifierChoiceReceipt
  (poo-clos-class 'aitia/verifier-choice-receipt
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.verifier-choices")))
          (text-slot 'identity)
          (enum-slot 'plan-digest assurance-digest?)
          (enum-slot 'candidates verifier-candidate-list?)
          (enum-slot 'choices verifier-choice-list?)
          (enum-slot 'unassigned-obligations text-list?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; A reported tool result is not an admission. Input bindings carry both the
;;; source revision and digest so a green exit cannot float across snapshots.
(def AssuranceVerifierInput
  (poo-clos-class 'aitia/verifier-input
    direct-slots:
    (list (text-slot 'identity) (text-slot 'revision)
          (enum-slot 'digest assurance-digest?))))
(def (verifier-input-list? values)
  (and (list? values) (every assurance-verifier-input? values)))
(def AssuranceVerifierOutcome
  (poo-clos-class 'aitia/verifier-outcome
    direct-slots:
    (list (text-slot 'identity)
          (enum-slot 'status
                     (one-of '(succeeded failed timed-out unavailable indeterminate)))
          (text-slot 'producer) (text-slot 'tool) (text-slot 'tool-version)
          (text-slot 'obligation) (text-slot 'subject) (text-slot 'scope)
          (text-slot 'snapshot-revision)
          (enum-slot 'snapshot-context-digest assurance-digest?)
          (enum-slot 'inputs verifier-input-list?)
          (enum-slot 'output-digest maybe-digest?)
          (enum-slot 'accountable-authority maybe-text?)
          (enum-slot 'review-scope maybe-text?))))
(def AssuranceEvidenceAdmissionReceipt
  (poo-clos-class 'aitia/evidence-admission-receipt
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.evidence-admission")))
          (text-slot 'outcome) (text-slot 'obligation)
          (enum-slot 'outcome-digest assurance-digest?)
          (enum-slot 'snapshot-digest assurance-digest?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'eligible? boolean?)
          (enum-slot 'blocker
                     (lambda (value)
                       (or (not value)
                           (memq value
                                 '(outcome-not-successful snapshot-conflicted
                                   stale-obligation
                                   outcome-binding-mismatch missing-output
                                   missing-inputs duplicate-inputs
                                   input-binding-mismatch
                                   human-authority-missing)))))
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; Exact subject for a Host-owned POO Flow verification adapter.  No
;;; caller-authored presentation slot is an execution attestation by itself.
(def AssuranceVerificationSubject
  (poo-clos-class 'aitia/verification-subject
    direct-slots:
    (list (enum-slot 'snapshot (lambda (value) (assurance-snapshot? value)))
          (enum-slot 'obligation (lambda (value) (assurance-obligation? value)))
          (enum-slot 'evidence (lambda (value) (assurance-evidence? value)))
          (enum-slot 'outcome
                     (lambda (value) (assurance-verifier-outcome? value))))))

;;; Host-checked support inventory is an input to Decision evaluation, not a
;;; Decision or an authority receipt. A POO presentation cannot grant release.
(def (required-support-blocker? value)
  (or (not value)
      (memq value '(obligation-missing obligation-stale support-link-missing
                    admission-missing admission-invalid
                    evidence-link-missing))))
(def AssessmentRequiredSupport
  (poo-clos-class 'aitia/required-support-assessment
    direct-slots:
    (list (text-slot 'obligation)
          (enum-slot 'supported? boolean?)
          (enum-slot 'blocker required-support-blocker?))))
(def (required-support-list? values)
  (and (list? values) (every assessment-required-support? values)))
(def (required-support-global-blocker? value)
  (memq value '(snapshot-conflicted snapshot-unresolved claim-not-current
                no-requirements duplicate-requirements
                assumptions-unresolved defeaters-unresolved
                claim-state-blocked challenge-unresolved source-changed)))
(def (required-support-global-blockers? values)
  (and (list? values)
       (every required-support-global-blocker? values)))
(def AssuranceRequiredSupport
  (poo-clos-class 'aitia/required-support
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.required-support")))
          (text-slot 'claim)
          (enum-slot 'snapshot-digest assurance-digest?)
          (enum-slot 'requirements required-support-list?)
          (enum-slot 'blockers required-support-global-blockers?)
          (enum-slot 'complete? boolean?)
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; A Host-issued preflight proves only that an undecided Decision and its
;;; required support were current at issuance. Cedar/Runtime own authority.
(def AssuranceDecisionPreflight
  (poo-clos-class 'aitia/decision-preflight
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.decision-preflight")))
          (text-slot 'identity)
          (text-slot 'issuer)
          (text-slot 'decision)
          (text-slot 'claim)
          (enum-slot 'snapshot-digest assurance-digest?)
          (enum-slot 'release-authorized? (one-of '(#f))))))

;;; A composition needs its own snapshot-bound obligation. Component support
;;; remains separate and cannot discharge this structural requirement.
(def AssuranceCompositionRequirement
  (poo-clos-class 'aitia/composition-requirement
    direct-slots:
    (list (text-slot 'composition-claim)
          (enum-slot 'component-claims text-list?)
          (enum-slot 'direct-obligations text-list?)
          (enum-slot 'current-obligations text-list?)
          (enum-slot 'blocker composition-blocker?))))
(def (composition-requirement-list? values)
  (and (list? values)
       (every assurance-composition-requirement? values)))
(def AssuranceCompositionDerivation
  (poo-clos-class 'aitia/composition-derivation
    direct-slots:
    (list (enum-slot 'schema
                     (lambda (value)
                       (equal? value "lambda-aitia.composition-requirements")))
          (text-slot 'identity)
          (enum-slot 'snapshot-digest assurance-digest?)
          (enum-slot 'requirements composition-requirement-list?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'verifier-executed? (one-of '(#f)))
          (enum-slot 'release-authorized? (one-of '(#f))))))

(defstruct assurance-invalidation-receipt-record
  (identity snapshot-digest changed impacted invalidated-evidence
   required-obligations invalidated-decisions blocked-effects witnesses unresolved
   strong-components cyclic-components
   temporal-proven? release-authorized? runtime-executed?)
  transparent: #t)

(def (node-of-kind? class kind value)
  (and (poo-flow-model? class value) (eq? (.ref value 'kind) kind)))
(def (assurance-node? value)
  (and (object? value) (.slot? value 'kind)
       (case (.ref value 'kind)
         ((artifact) (poo-flow-model? AssuranceArtifact value))
         ((claim) (poo-flow-model? AssuranceClaim value))
         ((assumption) (poo-flow-model? AssuranceAssumption value))
         ((observation) (poo-flow-model? AssuranceObservation value))
         ((event) (poo-flow-model? AssuranceEvent value))
         ((action) (poo-flow-model? AssuranceAction value))
         ((obligation) (poo-flow-model? AssuranceObligation value))
         ((evidence) (poo-flow-model? AssuranceEvidence value))
         ((counterexample) (poo-flow-model? AssuranceCounterexample value))
         ((finding) (poo-flow-model? AssuranceFinding value))
         ((decision) (poo-flow-model? AssuranceDecision value))
         ((effect) (poo-flow-model? AssuranceEffect value))
         (else #f))))
(def (assurance-artifact? value) (node-of-kind? AssuranceArtifact 'artifact value))
(def (assurance-claim? value) (node-of-kind? AssuranceClaim 'claim value))
(def (assurance-assumption? value)
  (node-of-kind? AssuranceAssumption 'assumption value))
(def (assurance-observation? value)
  (node-of-kind? AssuranceObservation 'observation value))
(def (assurance-event? value) (node-of-kind? AssuranceEvent 'event value))
(def (assurance-action? value) (node-of-kind? AssuranceAction 'action value))
(def (assurance-obligation? value)
  (node-of-kind? AssuranceObligation 'obligation value))
(def (assurance-evidence? value)
  (node-of-kind? AssuranceEvidence 'evidence value))
(def (assurance-counterexample? value)
  (node-of-kind? AssuranceCounterexample 'counterexample value))
(def (assurance-finding? value)
  (node-of-kind? AssuranceFinding 'finding value))
(def (assurance-decision? value)
  (node-of-kind? AssuranceDecision 'decision value))
(def (assurance-effect? value) (node-of-kind? AssuranceEffect 'effect value))
(def (assurance-relation? value)
  (and (poo-flow-model? AssuranceRelation value)
       (eq? (.ref value 'plane)
            (assurance-relation-kind-plane (.ref value 'relation)))))
(def (assurance-snapshot? value) (poo-flow-model? AssuranceSnapshot value))
(def (assurance-replacement-requirement? value)
  (poo-flow-model? AssuranceReplacementRequirement value))
(def (assurance-replacement-derivation? value)
  (poo-flow-model? AssuranceReplacementDerivation value))
(def (assurance-replacement-declaration-receipt? value)
  (and (poo-flow-model? AssuranceReplacementDeclarationReceipt value)
       (eq? (not (.ref value 'blocker))
            (if (.ref value 'final-snapshot-digest) #t #f))))
(def (assurance-verification-policy? value)
  (poo-flow-model? AssuranceVerificationPolicy value))
(def (assurance-verification-request? value)
  (and (poo-flow-model? AssuranceVerificationRequest value)
       (eq? (.ref value 'selected?)
            (not (.ref value 'blocker)))))
(def (assurance-verification-plan? value)
  (and (poo-flow-model? AssuranceVerificationPlan value)
       (equal?
        (.ref value 'selected-obligations)
        (map (lambda (request) (.ref request 'obligation-identity))
             (filter (lambda (request) (.ref request 'selected?))
                     (.ref value 'requests))))
       (equal?
        (.ref value 'blocked-obligations)
        (map (lambda (request) (.ref request 'obligation-identity))
             (filter (lambda (request) (not (.ref request 'selected?)))
                     (.ref value 'requests))))))
(def (assurance-verifier-candidate? value)
  (poo-flow-model? AssuranceVerifierCandidate value))
(def (assurance-verifier-choice? value)
  (and (poo-flow-model? AssuranceVerifierChoice value)
       (eq? (.ref value 'selected?)
            (eq? (.ref value 'reason) 'chosen))))
(def (assurance-verifier-choice-receipt? value)
  (poo-flow-model? AssuranceVerifierChoiceReceipt value))
(def (assurance-verifier-input? value)
  (poo-flow-model? AssuranceVerifierInput value))
(def (assurance-verifier-outcome? value)
  (poo-flow-model? AssuranceVerifierOutcome value))
(def (assurance-evidence-admission-receipt? value)
  (and (poo-flow-model? AssuranceEvidenceAdmissionReceipt value)
       (eq? (.ref value 'eligible?) (not (.ref value 'blocker)))))
(def (assessment-required-support? value)
  (and (poo-flow-model? AssessmentRequiredSupport value)
       (eq? (.ref value 'supported?) (not (.ref value 'blocker)))))
(def (assurance-required-support? value)
  (and (poo-flow-model? AssuranceRequiredSupport value)
       (eq? (.ref value 'complete?)
            (and (null? (.ref value 'blockers))
                 (pair? (.ref value 'requirements))
                 (every (lambda (item) (.ref item 'supported?))
                        (.ref value 'requirements))))))
(def (assurance-decision-preflight? value)
  (poo-flow-model? AssuranceDecisionPreflight value))
(def (assurance-verification-subject? value)
  (poo-flow-model? AssuranceVerificationSubject value))
(def (assurance-composition-requirement? value)
  (poo-flow-model? AssuranceCompositionRequirement value))
(def (assurance-composition-derivation? value)
  (poo-flow-model? AssuranceCompositionDerivation value))
(def (assurance-invalidation-receipt? value)
  (assurance-invalidation-receipt-record? value))
(def (assurance-invalidation-receipt-ref receipt name)
  (unless (assurance-invalidation-receipt? receipt)
    (error "not an assurance invalidation receipt" receipt))
  (case name
    ((identity) (assurance-invalidation-receipt-record-identity receipt))
    ((snapshot-digest)
     (assurance-invalidation-receipt-record-snapshot-digest receipt))
    ((changed) (assurance-invalidation-receipt-record-changed receipt))
    ((impacted) (assurance-invalidation-receipt-record-impacted receipt))
    ((invalidated-evidence)
     (assurance-invalidation-receipt-record-invalidated-evidence receipt))
    ((required-obligations)
     (assurance-invalidation-receipt-record-required-obligations receipt))
    ((invalidated-decisions)
     (assurance-invalidation-receipt-record-invalidated-decisions receipt))
    ((blocked-effects)
     (assurance-invalidation-receipt-record-blocked-effects receipt))
    ((witnesses) (assurance-invalidation-receipt-record-witnesses receipt))
    ((unresolved) (assurance-invalidation-receipt-record-unresolved receipt))
    ((strong-components)
     (assurance-invalidation-receipt-record-strong-components receipt))
    ((cyclic-components)
     (assurance-invalidation-receipt-record-cyclic-components receipt))
    ((temporal-proven?)
     (assurance-invalidation-receipt-record-temporal-proven? receipt))
    ((release-authorized?)
     (assurance-invalidation-receipt-record-release-authorized? receipt))
    ((runtime-executed?)
     (assurance-invalidation-receipt-record-runtime-executed? receipt))
    (else (error "unknown assurance invalidation receipt field" name))))
