;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref .slot? object?)
        :poo-flow/src/module-system/contribution/model
        (only-in :std/srfi/1 every))

(export assurance-text? assurance-digest?
        assurance-node-kind? assurance-state? assurance-relation-plane?
        assurance-relation-kind? assurance-relation-kind-plane
        assurance-modality?
        +assurance-node-kinds+ +assurance-states+
        +assurance-relation-planes+ +assurance-modalities+
        AssuranceNode AssuranceArtifact AssuranceClaim AssuranceAssumption
        AssuranceObservation AssuranceEvent AssuranceAction
        AssuranceObligation AssuranceEvidence AssuranceCounterexample
        AssuranceFinding AssuranceDecision AssuranceEffect
        AssuranceRelation AssuranceSnapshot
        make-assurance-invalidation-receipt-record
        assurance-node? assurance-artifact? assurance-claim?
        assurance-assumption? assurance-observation? assurance-event?
        assurance-action? assurance-obligation? assurance-evidence?
        assurance-counterexample? assurance-finding? assurance-decision?
        assurance-effect? assurance-relation? assurance-snapshot?
        assurance-invalidation-receipt? assurance-invalidation-receipt-ref)

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

(def +assurance-relation-kind-planes+
  '((derived-from . provenance)
    (generated-by . provenance)
    (cites . provenance)
    (used . provenance)
    (depends-on . structural)
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
(def (text-list? values)
  (and (list? values) (every assurance-text? values)))
(def (revision-bindings? values)
  (and (list? values)
       (every (lambda (binding)
                (and (pair? binding)
                     (assurance-text? (car binding))
                     (assurance-text? (cdr binding))))
              values)))
(def (witness-list? values)
  (and (list? values) (every text-list? values)))
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
         (enum-slot 'evidence-kind symbol?) (enum-slot 'capability symbol?)
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
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'nodes node-list?)
          (enum-slot 'relations relation-list?)
          (enum-slot 'unresolved text-list?)
          (enum-slot 'conflicts text-list?))))

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
