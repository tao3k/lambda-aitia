;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Shared JSON / POO projection helpers for the Scheme/Rust transport.
(import (for-template :tao3k/agentic-ai-lab/modules/temporal-causality/runtime/durable-journal)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :std/encoding/json JSONReadOptions json->string string->json)
        (only-in :clan/poo/object .get .o))
(export +aitia-max-input-bytes+
        +aitia-json-read-options+
        assert-aitia-input-budget!
        read-aitia-json
        json-required
        json-symbol
        json-list
        symbols->json
        replay-cut
        linked-journal-operations
        support-fields
        deployment-fields)

(def +aitia-max-input-bytes+ (* 4 1024 1024))
(def +aitia-json-read-options+
  (JSONReadOptions key-as-symbol: #f
                   array-as-vector: #f
                   object-as-hash: #t))

(def (assert-aitia-input-budget! payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB")))

(def (read-aitia-json text)
  (string->json text +aitia-json-read-options+))

(def (json-required object field)
  (or (hash-get object field)
      (error "missing Aitia input field" field)))

(def (json-symbol object field)
  (string->symbol (json-required object field)))

(def (json-list object field)
  (let (value (json-required object field))
    (cond
     ((list? value) value)
     ((vector? value) (vector->list value))
     (else (error "Aitia input field must be an array" field)))))

(def (symbols->json values)
  (list->vector (map symbol->string values)))

(def (replay-cut project-id row)
  (.o project: project-id
      workspace: (json-required row "workspace")
      change: (json-required row "change")
      operation: (json-required row "operation")
      commit: (json-required row "commit")
      tree: (json-required row "tree")
      parents: (json-list row "parents")))

(def (linked-journal-operations)
  (compiled-role-values 'tao3k/agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
    '(journal-pack journal-unpack journal-open journal-close!)))

(def (support-fields assessment)
  (let (requirements (.get assessment requirements))
    (hash (claim (.get assessment claim))
          (predicate (.get assessment predicate))
          (revision (.get assessment claim-revision))
          (scope (.get assessment scope))
          (subject (.get assessment subject))
          (snapshotDigest (.get assessment semantic-snapshot-digest))
          (complete (.get assessment complete?))
          (assumptions (list->vector (.get assessment assumptions)))
          (assumptionAssessments
           (list->vector
            (map (lambda (row)
                   (hash (assumption (.get row assumption))
                         (owner (.get row owner))
                         (reviewPolicy (.get row review-policy))
                         (obligation (.get row obligation))
                         (admission (.get row admission))
                         (blocker (and (.get row blocker)
                                       (symbol->string (.get row blocker))))))
                 (.get assessment assumption-assessments))))
          (defeaters (list->vector (.get assessment defeaters)))
          (challenges
           (list->vector
            (map (lambda (row)
                   (hash (challenge (.get row challenge))
                         (revision (.get row revision))
                         (kind (symbol->string (.get row kind)))
                         (state (symbol->string (.get row state)))
                         (subject (.get row subject))
                         (evidence (.get row evidence))
                         (evidenceDigest (.get row evidence-digest))
                         (scope (.get row scope))
                         (obligation (.get row obligation))
                         (relation (.get row relation))))
                 (.get assessment challenges))))
          (blockers (symbols->json (.get assessment blockers)))
          (residualDispositions
           (list->vector
            (map (lambda (row)
                   (hash (obligation (.get row obligation))
                         (decision (.get row decision))
                         (authority (.get row authority))
                         (policy (.get row policy))
                         (policyRevision (.get row policy-revision))
                         (admission (.get row admission))
                         (outcomeDigest (.get row outcome-digest))))
                 (.get assessment residual-dispositions))))
          (releaseAuthorized (.get assessment release-authorized?))
          (witnesses
           (list->vector
            (map (lambda (witness)
                   (hash (obligation (.get witness obligation))
                         (evidence (.get witness evidence))
                         (admission (.get witness admission))
                         (relation (.get witness relation))
                         (outcome (.get witness outcome))
                         (outcomeDigest (.get witness outcome-digest))
                         (scope (.get witness scope))
                         (method (symbol->string (.get witness declared-evidence-kind)))
                         (capability (symbol->string (.get witness capability)))
                         (producer (.get witness producer))
                         (tool (.get witness tool))
                         (toolVersion (.get witness tool-version))
                         (expiresAt (.get witness expires-at))
                         (inputs (list->vector (.get witness input-artifacts)))))
                 (.get assessment witnesses))))
          (remaining
           (list->vector
            (filter-map (lambda (row)
                          (and (not (.get row supported?))
                               (hash (obligation (.get row obligation))
                                     (reason (symbol->string (.get row blocker))))))
                        requirements))))))

(def (deployment-fields deployment)
  (hash (assessment (support-fields (.get deployment assessment)))
        (conditions
         (list->vector
          (map (lambda (row)
                 (hash (obligation (car row))
                       (method (symbol->string (cadr row)))
                       (capability (symbol->string (caddr row)))
                       (condition (cadddr row))))
               (.get deployment conditions))))))
