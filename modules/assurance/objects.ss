;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o)
        (only-in :gerbil/core list-sort)
        :std/list/list
        (only-in :clan/poo/type validate)
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

;; Declarative internal helper expanding directly to ordinary validated POO objects.
(defrule (validated-assurance-object RecordType (slot expr) ...)
  (validate RecordType
    (.o (:: @ (.get RecordType proto))
        (slot := expr) ...)))

(def (assurance-artifact identity revision state digest
                         owner: owner media-kind: media-kind
                         provenance: (provenance '()))
  (validated-assurance-object AssuranceArtifact
    (identity identity) (kind 'artifact) (revision revision)
    (state state) (content-digest digest) (owner owner)
    (media-kind media-kind) (provenance provenance)))

(def (assurance-claim identity revision state digest
                      subject: subject predicate: predicate
                      assumptions: (assumptions '())
                      defeaters: (defeaters '())
                      support-requirements: (support-requirements '())
                      scope: scope valid-from: valid-from
                      valid-until: (valid-until #f))
  (validated-assurance-object AssuranceClaim
    (identity identity) (kind 'claim) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (predicate predicate) (assumptions assumptions)
    (defeaters defeaters) (support-requirements support-requirements)
    (scope scope) (valid-from valid-from) (valid-until valid-until)))

(def (assurance-assumption identity revision state digest
                           owner: owner scope: scope
                           review-policy: review-policy
                           expires-at: (expires-at #f))
  (validated-assurance-object AssuranceAssumption
    (identity identity) (kind 'assumption) (revision revision)
    (state state) (content-digest digest) (owner owner)
    (scope scope) (review-policy review-policy) (expires-at expires-at)))

(def (assurance-observation identity revision state digest
                            subject: subject source: source
                            clock-role: clock-role
                            logical-position: logical-position)
  (validated-assurance-object AssuranceObservation
    (identity identity) (kind 'observation) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (source source) (clock-role clock-role)
    (logical-position logical-position)))

(def (assurance-event identity revision state digest
                      subject: subject event-kind: event-kind
                      observation: observation payload-digest: payload-digest
                      modality: modality commitment-state: commitment-state
                      causal-parents: (causal-parents '()))
  (validated-assurance-object AssuranceEvent
    (identity identity) (kind 'event) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (event-kind event-kind) (observation observation)
    (payload-digest payload-digest) (modality modality)
    (commitment-state commitment-state) (causal-parents causal-parents)))

(def (assurance-action identity revision state digest
                       subject: subject action-kind: action-kind
                       requested-by: requested-by scope: scope)
  (validated-assurance-object AssuranceAction
    (identity identity) (kind 'action) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (action-kind action-kind) (requested-by requested-by) (scope scope)))

(def (assurance-obligation identity revision state digest
                           subject: subject claim: claim
                           snapshot: snapshot evidence-kind: evidence-kind
                           capability: capability scope: scope
                           snapshot-revision: (snapshot-revision #f)
                           snapshot-context-digest: (snapshot-context-digest #f))
  (validated-assurance-object AssuranceObligation
    (identity identity) (kind 'obligation) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (claim claim) (snapshot snapshot) (evidence-kind evidence-kind)
    (snapshot-revision snapshot-revision)
    (snapshot-context-digest snapshot-context-digest)
    (capability capability) (scope scope)))

(def (assurance-evidence identity revision state digest
                         producer: producer tool: tool
                         tool-version: tool-version
                         input-artifacts: input-artifacts
                         obligation: obligation subject: subject
                         scope: scope valid-from: valid-from
                         valid-until: (valid-until #f)
                         admission-state: admission-state)
  (validated-assurance-object AssuranceEvidence
    (identity identity) (kind 'evidence) (revision revision)
    (state state) (content-digest digest) (producer producer)
    (tool tool) (tool-version tool-version)
    (input-artifacts input-artifacts) (obligation obligation)
    (subject subject) (scope scope) (valid-from valid-from)
    (valid-until valid-until) (admission-state admission-state)))

(def (assurance-counterexample identity revision state digest
                               subject: subject challenges: challenges
                               evidence: evidence details-digest: details-digest)
  (validated-assurance-object AssuranceCounterexample
    (identity identity) (kind 'counterexample) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (challenges challenges) (evidence evidence)
    (details-digest details-digest)))

(def (assurance-finding identity revision state digest
                        subject: subject challenges: challenges
                        evidence: evidence finding-kind: finding-kind)
  (validated-assurance-object AssuranceFinding
    (identity identity) (kind 'finding) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (challenges challenges) (evidence evidence)
    (finding-kind finding-kind)))

(def (assurance-decision identity revision state digest
                         subject: subject snapshot: snapshot
                         policy: policy authority: authority
                         outcome: outcome)
  (validated-assurance-object AssuranceDecision
    (identity identity) (kind 'decision) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (snapshot snapshot) (policy policy) (authority authority)
    (outcome outcome)))

(def (assurance-effect identity revision state digest
                       subject: subject decision: decision
                       effect-kind: effect-kind effect-state: effect-state)
  (validated-assurance-object AssuranceEffect
    (identity identity) (kind 'effect) (revision revision)
    (state state) (content-digest digest) (subject subject)
    (decision decision) (effect-kind effect-kind)
    (effect-state effect-state)))

(def (assurance-relation identity plane relation source target modality)
  (let ((owned-plane (assurance-relation-kind-plane relation)))
    (unless owned-plane
      (error "unknown assurance relation kind" relation))
    (unless (eq? plane owned-plane)
      (error "assurance relation crosses its owned plane"
             relation plane owned-plane))
    (validated-assurance-object AssuranceRelation
      (identity identity) (plane plane) (relation relation)
      (source source) (target target) (modality modality))))

(def (assurance-verifier-candidate identity revision priority evidence-kinds capability)
  (unless (and (list? evidence-kinds)
               (pair? evidence-kinds)
               (every assurance-evidence-kind? evidence-kinds))
    (error "invalid verifier evidence kinds" evidence-kinds))
  (validated-assurance-object AssuranceVerifierCandidate
    (identity identity) (revision revision) (priority priority)
    (evidence-kinds
     (list-sort
      (lambda (left right)
        (string<? (symbol->string left) (symbol->string right)))
      (delete-duplicates/hash evidence-kinds)))
    (capability capability)))
