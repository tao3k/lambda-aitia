;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil/core list-sort)
        :std/list/list
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-artifact assurance-claim assurance-assumption
        assurance-observation assurance-event assurance-action
        assurance-obligation assurance-evidence assurance-counterexample
        assurance-finding assurance-decision assurance-effect
        assurance-relation assurance-verifier-candidate)

(def (assurance-artifact identity-value revision-value state-value digest-value
                         owner: owner-value media-kind: media-kind-value
                         provenance: (provenance-values '()))
  (poo-flow-check-model AssuranceArtifact
    (.o (:: @ (poo-flow-model-prototype AssuranceArtifact))
        identity: identity-value kind: 'artifact revision: revision-value
        state: state-value content-digest: digest-value owner: owner-value
        media-kind: media-kind-value provenance: provenance-values)))
(def (assurance-claim identity-value revision-value state-value digest-value
                      subject: subject-value predicate: predicate-value
                      assumptions: (assumption-values '())
                      defeaters: (defeater-values '())
                      support-requirements: (support-values '())
                      scope: scope-value valid-from: valid-from-value
                      valid-until: (valid-until-value #f))
  (poo-flow-check-model AssuranceClaim
    (.o (:: @ (poo-flow-model-prototype AssuranceClaim))
        identity: identity-value kind: 'claim revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        predicate: predicate-value assumptions: assumption-values
        defeaters: defeater-values support-requirements: support-values
        scope: scope-value valid-from: valid-from-value
        valid-until: valid-until-value)))
(def (assurance-assumption identity-value revision-value state-value digest-value
                           owner: owner-value scope: scope-value
                           review-policy: review-policy-value
                           expires-at: (expires-at-value #f))
  (poo-flow-check-model AssuranceAssumption
    (.o (:: @ (poo-flow-model-prototype AssuranceAssumption))
        identity: identity-value kind: 'assumption revision: revision-value
        state: state-value content-digest: digest-value owner: owner-value
        scope: scope-value review-policy: review-policy-value
        expires-at: expires-at-value)))
(def (assurance-observation identity-value revision-value state-value digest-value
                            subject: subject-value source: source-value
                            clock-role: clock-role-value
                            logical-position: logical-position-value)
  (poo-flow-check-model AssuranceObservation
    (.o (:: @ (poo-flow-model-prototype AssuranceObservation))
        identity: identity-value kind: 'observation revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        source: source-value clock-role: clock-role-value
        logical-position: logical-position-value)))
(def (assurance-event identity-value revision-value state-value digest-value
                      subject: subject-value event-kind: event-kind-value
                      observation: observation-value payload-digest: payload-digest-value
                      modality: modality-value commitment-state: commitment-value
                      causal-parents: (causal-parent-values '()))
  (poo-flow-check-model AssuranceEvent
    (.o (:: @ (poo-flow-model-prototype AssuranceEvent))
        identity: identity-value kind: 'event revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        event-kind: event-kind-value observation: observation-value
        payload-digest: payload-digest-value modality: modality-value
        commitment-state: commitment-value causal-parents: causal-parent-values)))
(def (assurance-action identity-value revision-value state-value digest-value
                       subject: subject-value action-kind: action-kind-value
                       requested-by: requested-by-value scope: scope-value)
  (poo-flow-check-model AssuranceAction
    (.o (:: @ (poo-flow-model-prototype AssuranceAction))
        identity: identity-value kind: 'action revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        action-kind: action-kind-value requested-by: requested-by-value
        scope: scope-value)))
(def (assurance-obligation identity-value revision-value state-value digest-value
                           subject: subject-value claim: claim-value
                           snapshot: snapshot-value evidence-kind: evidence-kind-value
                           capability: capability-value scope: scope-value
                           snapshot-revision: (snapshot-revision-value #f)
                           snapshot-context-digest: (snapshot-context-value #f))
  (poo-flow-check-model AssuranceObligation
    (.o (:: @ (poo-flow-model-prototype AssuranceObligation))
        identity: identity-value kind: 'obligation revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        claim: claim-value snapshot: snapshot-value evidence-kind: evidence-kind-value
        snapshot-revision: snapshot-revision-value
        snapshot-context-digest: snapshot-context-value
        capability: capability-value scope: scope-value)))
(def (assurance-evidence identity-value revision-value state-value digest-value
                         producer: producer-value tool: tool-value
                         tool-version: tool-version-value
                         input-artifacts: input-artifact-values
                         obligation: obligation-value subject: subject-value
                         scope: scope-value valid-from: valid-from-value
                         valid-until: (valid-until-value #f)
                         admission-state: admission-state-value)
  (poo-flow-check-model AssuranceEvidence
    (.o (:: @ (poo-flow-model-prototype AssuranceEvidence))
        identity: identity-value kind: 'evidence revision: revision-value
        state: state-value content-digest: digest-value producer: producer-value
        tool: tool-value tool-version: tool-version-value
        input-artifacts: input-artifact-values obligation: obligation-value
        subject: subject-value scope: scope-value valid-from: valid-from-value
        valid-until: valid-until-value admission-state: admission-state-value)))
(def (assurance-counterexample identity-value revision-value state-value digest-value
                               subject: subject-value challenges: challenges-value
                               evidence: evidence-value details-digest: details-digest-value)
  (poo-flow-check-model AssuranceCounterexample
    (.o (:: @ (poo-flow-model-prototype AssuranceCounterexample))
        identity: identity-value kind: 'counterexample revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        challenges: challenges-value evidence: evidence-value
        details-digest: details-digest-value)))
(def (assurance-finding identity-value revision-value state-value digest-value
                        subject: subject-value challenges: challenges-value
                        evidence: evidence-value finding-kind: finding-kind-value)
  (poo-flow-check-model AssuranceFinding
    (.o (:: @ (poo-flow-model-prototype AssuranceFinding))
        identity: identity-value kind: 'finding revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        challenges: challenges-value evidence: evidence-value
        finding-kind: finding-kind-value)))
(def (assurance-decision identity-value revision-value state-value digest-value
                         subject: subject-value snapshot: snapshot-value
                         policy: policy-value authority: authority-value
                         outcome: outcome-value)
  (poo-flow-check-model AssuranceDecision
    (.o (:: @ (poo-flow-model-prototype AssuranceDecision))
        identity: identity-value kind: 'decision revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        snapshot: snapshot-value policy: policy-value authority: authority-value
        outcome: outcome-value)))
(def (assurance-effect identity-value revision-value state-value digest-value
                       subject: subject-value decision: decision-value
                       effect-kind: effect-kind-value effect-state: effect-state-value)
  (poo-flow-check-model AssuranceEffect
    (.o (:: @ (poo-flow-model-prototype AssuranceEffect))
        identity: identity-value kind: 'effect revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        decision: decision-value effect-kind: effect-kind-value
        effect-state: effect-state-value)))

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

(def (assurance-verifier-candidate identity-value revision-value
                                   priority-value evidence-kind-values
                                   capability-value)
  (unless (and (list? evidence-kind-values)
               (pair? evidence-kind-values)
               (every assurance-evidence-kind? evidence-kind-values))
    (error "invalid verifier evidence kinds" evidence-kind-values))
  (poo-flow-check-model
   AssuranceVerifierCandidate
   (.o (:: @ (poo-flow-model-prototype AssuranceVerifierCandidate))
       identity: identity-value revision: revision-value
       priority: priority-value
       evidence-kinds:
       (list-sort
        (lambda (left right)
          (string<? (symbol->string left) (symbol->string right)))
        (delete-duplicates/hash evidence-kind-values))
       capability: capability-value)))
