;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-artifact assurance-claim assurance-assumption
        assurance-observation assurance-event assurance-action
        assurance-obligation assurance-evidence assurance-counterexample
        assurance-finding assurance-decision assurance-effect
        assurance-relation)

(def (assurance-artifact identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceArtifact
    (.o (:: @ (poo-flow-model-prototype AssuranceArtifact))
        identity: identity-value kind: 'artifact revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-claim identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceClaim
    (.o (:: @ (poo-flow-model-prototype AssuranceClaim))
        identity: identity-value kind: 'claim revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-assumption identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceAssumption
    (.o (:: @ (poo-flow-model-prototype AssuranceAssumption))
        identity: identity-value kind: 'assumption revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-observation identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceObservation
    (.o (:: @ (poo-flow-model-prototype AssuranceObservation))
        identity: identity-value kind: 'observation revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-event identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceEvent
    (.o (:: @ (poo-flow-model-prototype AssuranceEvent))
        identity: identity-value kind: 'event revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-action identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceAction
    (.o (:: @ (poo-flow-model-prototype AssuranceAction))
        identity: identity-value kind: 'action revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-obligation identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceObligation
    (.o (:: @ (poo-flow-model-prototype AssuranceObligation))
        identity: identity-value kind: 'obligation revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-evidence identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceEvidence
    (.o (:: @ (poo-flow-model-prototype AssuranceEvidence))
        identity: identity-value kind: 'evidence revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-counterexample identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceCounterexample
    (.o (:: @ (poo-flow-model-prototype AssuranceCounterexample))
        identity: identity-value kind: 'counterexample revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-finding identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceFinding
    (.o (:: @ (poo-flow-model-prototype AssuranceFinding))
        identity: identity-value kind: 'finding revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-decision identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceDecision
    (.o (:: @ (poo-flow-model-prototype AssuranceDecision))
        identity: identity-value kind: 'decision revision: revision-value
        state: state-value content-digest: digest-value)))
(def (assurance-effect identity-value revision-value state-value digest-value)
  (poo-flow-check-model AssuranceEffect
    (.o (:: @ (poo-flow-model-prototype AssuranceEffect))
        identity: identity-value kind: 'effect revision: revision-value
        state: state-value content-digest: digest-value)))

(def (assurance-relation identity-value plane-value relation-value
                         source-value target-value modality-value)
  (let ((owned-plane (assurance-relation-kind-plane relation-value)))
    (unless owned-plane
      (error "unknown assurance relation kind" relation-value))
    (unless (eq? plane-value owned-plane)
      (error "assurance relation crosses its owned plane"
             relation-value plane-value owned-plane))
    (poo-flow-check-model
     AssuranceRelation
     (.o (:: @ (poo-flow-model-prototype AssuranceRelation))
         identity: identity-value plane: plane-value relation: relation-value
         source: source-value target: target-value modality: modality-value))))
