;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil/core list-sort)
        :std/list/list
        (only-in :clan/poo/mop validate)
        "types.ss")

(export AssurancePolicy assurance-artifact assurance-claim assurance-assumption
        assurance-observation assurance-event assurance-action
        assurance-obligation assurance-evidence assurance-counterexample
        assurance-finding assurance-decision assurance-effect
        assurance-relation assurance-verifier-candidate)

;;; Pure declared defaults.  This value invokes no verifier and grants no
;;; authority.
(def AssurancePolicy
  (.o identity: "lambda-aitia/assurance-policy"
      revision: "1"
      relation-planes: +assurance-relation-planes+
      unresolved-frontier: 'block
      conflict-resolution: 'explicit
      planner-executes?: #f
      grants-authority?: #f))

(def (assurance-artifact identity-value revision-value state-value digest-value
                         owner: owner-value media-kind: media-kind-value
                         provenance: (provenance-values '()))
  (validate AssuranceArtifact
    (.o (:: @ (.ref AssuranceArtifact 'proto))
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
  (validate AssuranceClaim
    (.o (:: @ (.ref AssuranceClaim 'proto))
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
  (validate AssuranceAssumption
    (.o (:: @ (.ref AssuranceAssumption 'proto))
        identity: identity-value kind: 'assumption revision: revision-value
        state: state-value content-digest: digest-value owner: owner-value
        scope: scope-value review-policy: review-policy-value
        expires-at: expires-at-value)))
(def (assurance-observation identity-value revision-value state-value digest-value
                            subject: subject-value source: source-value
                            clock-role: clock-role-value
                            logical-position: logical-position-value)
  (validate AssuranceObservation
    (.o (:: @ (.ref AssuranceObservation 'proto))
        identity: identity-value kind: 'observation revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        source: source-value clock-role: clock-role-value
        logical-position: logical-position-value)))
(def (assurance-event identity-value revision-value state-value digest-value
                      subject: subject-value event-kind: event-kind-value
                      observation: observation-value payload-digest: payload-digest-value
                      modality: modality-value commitment-state: commitment-value
                      causal-parents: (causal-parent-values '()))
  (validate AssuranceEvent
    (.o (:: @ (.ref AssuranceEvent 'proto))
        identity: identity-value kind: 'event revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        event-kind: event-kind-value observation: observation-value
        payload-digest: payload-digest-value modality: modality-value
        commitment-state: commitment-value causal-parents: causal-parent-values)))
(def (assurance-action identity-value revision-value state-value digest-value
                       subject: subject-value action-kind: action-kind-value
                       requested-by: requested-by-value scope: scope-value)
  (validate AssuranceAction
    (.o (:: @ (.ref AssuranceAction 'proto))
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
  (validate AssuranceObligation
    (.o (:: @ (.ref AssuranceObligation 'proto))
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
  (validate AssuranceEvidence
    (.o (:: @ (.ref AssuranceEvidence 'proto))
        identity: identity-value kind: 'evidence revision: revision-value
        state: state-value content-digest: digest-value producer: producer-value
        tool: tool-value tool-version: tool-version-value
        input-artifacts: input-artifact-values obligation: obligation-value
        subject: subject-value scope: scope-value valid-from: valid-from-value
        valid-until: valid-until-value admission-state: admission-state-value)))
(def (assurance-counterexample identity-value revision-value state-value digest-value
                               subject: subject-value challenges: challenges-value
                               evidence: evidence-value details-digest: details-digest-value)
  (validate AssuranceCounterexample
    (.o (:: @ (.ref AssuranceCounterexample 'proto))
        identity: identity-value kind: 'counterexample revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        challenges: challenges-value evidence: evidence-value
        details-digest: details-digest-value)))
(def (assurance-finding identity-value revision-value state-value digest-value
                        subject: subject-value challenges: challenges-value
                        evidence: evidence-value finding-kind: finding-kind-value)
  (validate AssuranceFinding
    (.o (:: @ (.ref AssuranceFinding 'proto))
        identity: identity-value kind: 'finding revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        challenges: challenges-value evidence: evidence-value
        finding-kind: finding-kind-value)))
(def (assurance-decision identity-value revision-value state-value digest-value
                         subject: subject-value snapshot: snapshot-value
                         policy: policy-value authority: authority-value
                         outcome: outcome-value)
  (validate AssuranceDecision
    (.o (:: @ (.ref AssuranceDecision 'proto))
        identity: identity-value kind: 'decision revision: revision-value
        state: state-value content-digest: digest-value subject: subject-value
        snapshot: snapshot-value policy: policy-value authority: authority-value
        outcome: outcome-value)))
(def (assurance-effect identity-value revision-value state-value digest-value
                       subject: subject-value decision: decision-value
                       effect-kind: effect-kind-value effect-state: effect-state-value)
  (validate AssuranceEffect
    (.o (:: @ (.ref AssuranceEffect 'proto))
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
    (validate
     AssuranceRelation
     (.o (:: @ (.ref AssuranceRelation 'proto))
         identity: identity-value plane: plane-value relation: relation-value
         source: source-value target: target-value modality: modality-value))))

(def (assurance-verifier-candidate identity-value revision-value
                                   priority-value evidence-kind-values
                                   capability-value)
  (unless (and (list? evidence-kind-values)
               (pair? evidence-kind-values)
               (every assurance-evidence-kind? evidence-kind-values))
    (error "invalid verifier evidence kinds" evidence-kind-values))
  (validate
   AssuranceVerifierCandidate
   (.o (:: @ (.ref AssuranceVerifierCandidate 'proto))
       identity: identity-value revision: revision-value
       priority: priority-value
       evidence-kinds:
       (list-sort
        (lambda (left right)
          (string<? (symbol->string left) (symbol->string right)))
        (delete-duplicates/hash evidence-kind-values))
       capability: capability-value)))
