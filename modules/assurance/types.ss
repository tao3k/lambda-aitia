;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot? object?)
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
        assurance-node? assurance-artifact? assurance-claim?
        assurance-assumption? assurance-observation? assurance-event?
        assurance-action? assurance-obligation? assurance-evidence?
        assurance-counterexample? assurance-finding? assurance-decision?
        assurance-effect? assurance-relation? assurance-snapshot?)

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

(def (node-slots)
  (list (text-slot 'identity)
        (enum-slot 'kind assurance-node-kind?)
        (text-slot 'revision)
        (enum-slot 'state assurance-state?)
        (enum-slot 'content-digest assurance-digest?)))
(def (node-class identity)
  (poo-clos-class identity direct-slots: (node-slots)))
(def AssuranceNode (node-class 'aitia/assurance-node))
(def AssuranceArtifact (node-class 'aitia/artifact))
(def AssuranceClaim (node-class 'aitia/claim))
(def AssuranceAssumption (node-class 'aitia/assumption))
(def AssuranceObservation (node-class 'aitia/observation))
(def AssuranceEvent (node-class 'aitia/event))
(def AssuranceAction (node-class 'aitia/action))
(def AssuranceObligation (node-class 'aitia/obligation))
(def AssuranceEvidence (node-class 'aitia/evidence))
(def AssuranceCounterexample (node-class 'aitia/counterexample))
(def AssuranceFinding (node-class 'aitia/finding))
(def AssuranceDecision (node-class 'aitia/decision))
(def AssuranceEffect (node-class 'aitia/effect))

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
(def (text-list? values)
  (and (list? values) (every assurance-text? values)))
(def AssuranceSnapshot
  (poo-clos-class 'aitia/assurance-snapshot
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'revision)
          (enum-slot 'state assurance-state?)
          (enum-slot 'digest assurance-digest?)
          (enum-slot 'nodes node-list?)
          (enum-slot 'relations relation-list?)
          (enum-slot 'unresolved text-list?)
          (enum-slot 'conflicts text-list?))))

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
