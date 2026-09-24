;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :clan/poo/object .ref)
        :poo-flow/lambda-aitia/modules/sdlc/interface)

(export design-contract-test)

(def idempotency
  (sdlc-design-assumption
   "external-idempotency" "a1"
   "The provider deduplicates tenant/job/operation keys"))
(def unique-effect
  (sdlc-design-guarantee
   "unique-effect" "g1"
   "At most one externally committed effect per operation key"))
(def cancellation
  (sdlc-design-guarantee
   "cancel-before-commit" "g1"
   "Cancellation before the commit point prevents a new commit"))
(def retry-v1
  (sdlc-design-variation "retry-policy" "v1" '("unique-effect")))
(def retry-v2
  (sdlc-design-variation "retry-policy" "v2" '("unique-effect")))

(def (contract revision assumptions guarantees variations
               effects: (effects '("external-operation"))
               owned-state: (owned '("job-ledger"))
               decision: (decision "ADR/job-executor"))
  (sdlc-design-contract
   "job-executor" revision decision '("execute-job") owned effects
   assumptions guarantees variations))

(def baseline
  (contract "r1" (list idempotency) (list unique-effect cancellation)
            (list retry-v1)))

(def design-contract-test
  (test-suite "SDLC design contract replacement"
    (test-case "retry variation reopens only its declared guarantee"
      (let* ((next (contract "r2" (list idempotency)
                             (list unique-effect cancellation) (list retry-v2)))
             (review (sdlc-design-replacement-review baseline next))
             (project (sdlc-project "job-service" "r2" "software" #t))
             (retry-node (sdlc-trace-node "retry-policy" 'design project))
             (guarantee-node (sdlc-trace-node "unique-effect" 'design project))
             (verification-node
              (sdlc-trace-node "verify-unique-effect" 'verification project))
             (edges
              (list (sdlc-trace-edge "retry-to-guarantee" "design-depends-on"
                                     "retry-policy" "unique-effect" project)
                    (sdlc-trace-edge "guarantee-to-check" "design-depends-on"
                                     "unique-effect" "verify-unique-effect" project)))
             (impact
              (sdlc-change-impact project
                                  (list retry-node guarantee-node verification-node)
                                  edges (.ref review 'changed-identities)
                                  '("design-depends-on"))))
        (check-equal? (.ref review 'declared-substitutable?) #f)
        (check-equal? (.ref review 'blockers) '(variation-changed))
        (check-equal? (.ref review 'changed-identities) '("retry-policy"))
        (check-equal? (.ref review 'recheck-guarantees) '("unique-effect"))
        (check-equal? (.ref impact 'recheck-verifications)
                      '("verify-unique-effect"))
        (check-equal? (.ref review 'evidence-admitted?) #f)
        (check-equal? (.ref review 'release-authorized?) #f)))
    (test-case "new provider assumption cannot masquerade as compatible"
      (let* ((extra (sdlc-design-assumption
                     "provider-available" "a1" "Provider is always available"))
             (next (contract "r2" (list idempotency extra)
                             (list unique-effect cancellation) (list retry-v1)))
             (review (sdlc-design-replacement-review baseline next)))
        (check-equal? (.ref review 'blockers)
                      '(stronger-or-changed-assumption))
        (check-equal? (.ref review 'recheck-guarantees)
                      '("cancel-before-commit" "unique-effect"))))
    (test-case "a weakened guarantee or added effect is an explicit blocker"
      (let* ((weakened-effect
              (sdlc-design-guarantee
               "unique-effect" "g2"
               "At most two externally committed effects per operation key"))
             (weakened (contract "r2" (list idempotency)
                                 (list weakened-effect cancellation)
                                 (list retry-v1)))
             (more-effects
              (contract "r2" (list idempotency)
                        (list unique-effect cancellation) (list retry-v1)
                        effects: '("external-operation" "audit-write"))))
        (check-equal?
         (.ref (sdlc-design-replacement-review baseline weakened) 'blockers)
         '(weaker-or-changed-guarantee))
        (check-equal?
         (.ref (sdlc-design-replacement-review baseline more-effects) 'blockers)
         '(new-effect))))
    (test-case "lost ACK exposes the difference between a key and a logical operation"
      (let* ((logical-effect
              (sdlc-design-guarantee
               "unique-effect" "g2"
               "At most one external commit per logical job operation across retries and restarts"))
             (revised (contract "r2" (list idempotency)
                                (list logical-effect cancellation)
                                (list retry-v2)))
             (review (sdlc-design-replacement-review baseline revised))
             (with-adr (contract "r2" (list idempotency)
                                 (list logical-effect cancellation)
                                 (list retry-v2)
                                 decision: "lambda-aitia-adr-0008"))
             (decision-review
              (sdlc-design-replacement-review baseline with-adr)))
        (check-equal? (.ref review 'declared-substitutable?) #f)
        (check-equal? (.ref review 'recheck-guarantees) '("unique-effect"))
        (check-equal? (.ref decision-review 'recheck-guarantees)
                      '("cancel-before-commit" "unique-effect"))
        (check-equal? (.ref review 'evidence-admitted?) #f)
        (check-equal? (.ref review 'release-authorized?) #f)))
    (test-case "declaration-level compatibility never admits new evidence"
      (let* ((next (contract "r2" '() (list unique-effect cancellation)
                             (list retry-v1)))
             (review (sdlc-design-replacement-review baseline next)))
        (check-equal? (.ref review 'declared-substitutable?) #t)
        (check-equal? (.ref review 'recheck-guarantees)
                      '("cancel-before-commit" "unique-effect"))
        (check-equal? (.ref (sdlc-design-replacement-review
                            baseline
                            (contract "r2" (list idempotency)
                                      (list unique-effect cancellation)
                                      (list retry-v1)))
                            'changed-identities)
                      '("job-executor"))
        (check-equal? (.ref review 'release-authorized?) #f)))
    (test-case "changing the selected ADR reopens every guarantee"
      (let (review
            (sdlc-design-replacement-review
             baseline
             (contract "r2" (list idempotency)
                       (list unique-effect cancellation) (list retry-v1)
                       decision: "ADR/job-executor-v2")))
        (check-equal? (.ref review 'blockers) '(decision-changed))
        (check-equal? (.ref review 'changed-identities) '("job-executor"))
        (check-equal? (.ref review 'recheck-guarantees)
                      '("cancel-before-commit" "unique-effect"))))
    (test-case "local deduplication is a distinct design, not a proof-preserving override"
      (let* ((alternative
              (sdlc-design-contract
               "job-executor" "r2" "ADR/local-deduplication"
               '("execute-job" "reconcile-unknown-effect")
               '("job-ledger" "dedup-ledger")
               '("external-operation") '()
               (list unique-effect cancellation) (list retry-v1)))
             (review (sdlc-design-replacement-review baseline alternative)))
        (check-equal? (.ref review 'declared-substitutable?) #f)
        (check-equal? (.ref review 'blockers)
                      '(responsibility-changed state-ownership-changed
                        decision-changed))
        (check-equal? (.ref review 'recheck-guarantees)
                      '("cancel-before-commit" "unique-effect"))))
    (test-case "same revision mutation and orphan dependency fail closed"
      (check-exception
       (sdlc-design-replacement-review
        baseline
        (contract "r1" (list idempotency) (list cancellation)
                  (list retry-v1)))
       Error?)
      (check-exception
       (contract "r2" (list idempotency) (list cancellation)
                 (list retry-v1))
       Error?)
      (check-exception
       (contract "r2" (list idempotency idempotency)
                 (list unique-effect cancellation) (list retry-v1))
       Error?)
      (check-exception
       (contract "r2" (list idempotency) '() '())
       Error?)
      (check-exception
       (sdlc-design-variation "retry-policy" "v3" '())
       Error?))))
