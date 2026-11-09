;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/list/list find)
        (only-in :yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in "objects.ss" assurance-artifact assurance-claim assurance-assumption assurance-obligation
                 assurance-evidence assurance-relation assurance-counterexample)
        (only-in "func.ss" assurance-canonical-digest assurance-snapshot
                 assurance-bind-obligation-to-snapshot)
        (only-in "host.ss" assurance-verification-host assurance-host-required-support)
        (only-in "observed-support.ss" assurance-assess-observed-support))
(export assurance-assess-pytest-replay assurance-assess-replay-deployment assurance-replay-cases assurance-replay-observation-matches?)

;; This claim is limited to the selected Case at the exact recorded cut.
;; Outcome and source bytes originate at the runtime owner boundary.
(def (assurance-assess-pytest-replay
      project operation revision obligation-id selector source-bytes source-digest report-digest passed?)
  (let* ((producer "aitia-runtime/pytest")
         (source-id "artifact/recorded-replay-source")
         (claim-id "claim/recorded-pytest-case")
         (snapshot-id "recorded-pytest")
         (source-value (assurance-artifact source-id revision 'supported source-digest
                                           owner: producer media-kind: 'frozen-source))
         (claim-value
          (assurance-claim claim-id revision 'unknown report-digest
                           subject: project scope: selector valid-from: operation
                           predicate: "The selected pytest Case passed at this recorded cut"
                           support-requirements: (list obligation-id)))
         (obligation-value
          (assurance-obligation obligation-id revision 'unknown source-digest
                                subject: project claim: claim-id scope: selector
                                snapshot: snapshot-id evidence-kind: 'replay capability: 'pytest))
         (evidence-value
          (assurance-evidence report-digest revision 'supported report-digest
                              subject: project scope: selector valid-from: operation
                              producer: producer tool: "pytest" tool-version: "recorded-replay-v1"
                              input-artifacts: (list source-id)
                              obligation: obligation-id admission-state: 'candidate)))
    (and (equal? (source-lock-payload-digest source-bytes) source-digest)
         (assurance-assess-observed-support
          operation claim-value obligation-value evidence-value (list source-value)
          (lambda (identity) (and (equal? identity source-id) source-bytes))
          (and passed? report-digest)
          (lambda (subject now expiry inputs)
            (equal? (.ref (car inputs) 'digest) source-digest))
          challenge: (and (not passed?)
                          (assurance-counterexample
                           "counterexample/recorded-pytest-case" revision 'supported report-digest
                           subject: project challenges: claim-id evidence: report-digest
                           details-digest: report-digest))))))

;; ADR 0008 owns these deployment obligations. A selected replay cannot
;; satisfy them because each requires evidence from the deployed boundary.
(def adr-0008-deployment
  '(("logical-operation-identity" integration-test provider-identity
      "Keep tenant, logical operation and intent bound across retry and restart.")
    ("changed-intent-rejection" integration-test provider-intent
      "Refuse an existing identity with changed intent without a second effect.")
    ("deduplication-retention" integration-test provider-retention
      "Retain the deduplication record through the retry horizon and handle late requests.")
    ("atomic-effect-commit" integration-test provider-atomicity
      "Qualify the effect and deduplication commit boundary across failures.")
    ("concurrent-attempt-reconciliation" integration-test provider-concurrency
      "Qualify simultaneous attempts and reconcile unknown effects.")
    ("provider-retry-contract-review" human-review assumption-review
      "Review the deployed provider's deduplication and retry-horizon contract.")))

(def adr-0008-provider-assumption "assumption/adr-0008-provider-retry-contract")

(def (assurance-replay-cases profile)
  (and (equal? profile "adr-0008")
       '(("fixed-check" "test_unique_effect.py::test_unique_effect_after_lost_ack_and_restart[fixed]" "passed" #f)
         ("buggy-check" "test_unique_effect.py::test_unique_effect_after_lost_ack_and_restart[buggy]" "failed"
          "AssertionError: ADR0008 duplicate effects: expected 1, observed 2"))))

(def (require-replay-case profile selector)
  (or (let (cases (assurance-replay-cases profile))
        (and cases
             (find (lambda (row)
                     (let (name (cadr row))
                       (or (equal? selector name)
                           (equal? selector (string-append "dev/qualification/job-executor/" name)))))
                   cases)))
      (error "replay does not match the declared deployment profile" profile selector)))

(def (assurance-replay-observation-matches? profile selector obligation outcome message)
  (let* ((case-value (require-replay-case profile selector))
         (failure (cadddr case-value)))
    (and (equal? obligation (car case-value))
         (or (not (eq? outcome 'failed))
             (not failure)
             (equal? failure message)))))

(def (assurance-assess-replay-deployment profile project-id operation revision selector)
  (require-replay-case profile selector)
  (let* ((scope-id (string-append project-id "/deployment"))
         (claim-id "claim/adr-0008-deployed-unique-effect")
         (snapshot-id "adr-0008/deployment")
         (policy-digest (assurance-canonical-digest adr-0008-deployment))
         (premise
          (assurance-assumption
           adr-0008-provider-assumption revision 'unknown
           (assurance-canonical-digest
            '(provider-retains-deduplication-record-through-declared-retry-horizon))
           owner: "provider-owner" scope: scope-id review-policy: "human-review"))
         (claim-value
          (assurance-claim claim-id revision 'unknown policy-digest
                           subject: project-id scope: scope-id valid-from: operation
                           predicate: "At most one external commit per deployed logical operation"
                           assumptions: (list adr-0008-provider-assumption)
                           support-requirements: (map car adr-0008-deployment)))
         (obligations
          (map (lambda (row)
                 (assurance-obligation (car row) revision 'unknown
                                       (assurance-canonical-digest row)
                                       subject: project-id claim: claim-id scope: scope-id
                                       snapshot: snapshot-id evidence-kind: (cadr row)
                                       capability: (caddr row)))
               adr-0008-deployment))
         (relations
          (map (lambda (obligation)
                 (let (id (.ref obligation 'identity))
                   (assurance-relation (string-append "requires/" id)
                                       'assurance 'supports id claim-id 'declared)))
               obligations)))
    (def (snapshot-with nodes)
      (assurance-snapshot snapshot-id revision snapshot-id '()
                          (list (cons claim-id revision)) operation profile policy-digest
                          (cons claim-value (cons premise nodes))
                          (cons (assurance-relation "reviews/provider-retry-contract"
                                                    'assurance 'supports
                                                    "provider-retry-contract-review"
                                                    adr-0008-provider-assumption 'declared)
                                relations)))
    (let* ((draft (snapshot-with obligations))
           (snapshot-value
            (snapshot-with
             (map (lambda (obligation) (assurance-bind-obligation-to-snapshot obligation draft))
                  obligations)))
           (host (assurance-verification-host
                  snapshot-id (lambda (subject now expiry) #f)
                  (lambda () 0) 1 (lambda () snapshot-value)))
           (assessment-value (assurance-host-required-support host claim-value '())))
      (.o assessment: assessment-value conditions: adr-0008-deployment))))
