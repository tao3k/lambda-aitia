;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow/src/feature-system/source-lock-feature
                 source-lock-payload-digest)
        :poo-flow/lambda-aitia/modules/assurance/interface
        :poo-flow/lambda-aitia/modules/sdlc/interface)

(export design-verification-test)

(def source-bytes "(def (execute-job) 'committed)\n")
(def digest-a (source-lock-payload-digest source-bytes))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def guarantee
  (sdlc-design-guarantee "unique-effect" "g1" "At most one external commit"))
(def contract
  (sdlc-design-contract "job-executor" "r1" "ADR/job-executor"
                        '("execute-job") '("job-ledger")
                        '("external-operation") '() (list guarantee) '()))
(def source
  (assurance-artifact "artifact/source" "s1" 'supported digest-a
                      owner: "lambda-aitia" media-kind: 'scheme-source
                      provenance: '("repository")))
(def other-source
  (assurance-artifact "artifact/other" "s1" 'supported digest-b
                      owner: "lambda-aitia" media-kind: 'scheme-source
                      provenance: '("repository")))
(def claim
  (assurance-claim "claim/unique-effect" "r1" 'unknown digest-a
                   subject: "job-executor"
                   predicate: "At most one external commit"
                   support-requirements: '("obligation/test")
                   scope: "repository" valid-from: "2026-09-24"))
(def obligation
  (assurance-obligation "obligation/test" "r1" 'unknown digest-a
                        subject: "job-executor" claim: "claim/unique-effect"
                        snapshot: "snapshot/job-executor"
                        evidence-kind: 'native-test capability: 'gerbil-test
                        scope: "repository"))
(def evidence
  (assurance-evidence "evidence/test" "r1" 'supported digest-b
                      producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
                      input-artifacts: '("artifact/source")
                      obligation: "obligation/test" subject: "job-executor"
                      scope: "repository" valid-from: "2026-09-24"
                      admission-state: 'candidate))
(def other-evidence
  (assurance-evidence "evidence/test" "r1" 'supported digest-b
                      producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
                      input-artifacts: '("artifact/other")
                      obligation: "obligation/test" subject: "job-executor"
                      scope: "repository" valid-from: "2026-09-24"
                      admission-state: 'candidate))
(def evidence-link
  (assurance-relation "relation/evidence" 'assurance 'discharges
                      "evidence/test" "obligation/test" 'observed))
(def requirement-link
  (assurance-relation "relation/requirement" 'assurance 'supports
                      "obligation/test" "claim/unique-effect" 'declared))
(def source-link
  (assurance-relation "relation/source" 'structural 'depends-on
                      "claim/unique-effect" "artifact/source" 'declared))

(def (construct obligation-value evidence-value relation-values)
  (assurance-snapshot
   "snapshot/job-executor" "cut-1" "graph/job-executor"
   '(("artifact/source" . "s1") ("artifact/other" . "s1"))
   '(("claim/unique-effect" . "r1"))
   "fact-cut-1" "policy/design" "p1"
   (list source other-source claim obligation-value evidence-value) relation-values))
(def (bound-cut relation-values evidence-value)
  (let (draft (construct obligation evidence-value relation-values))
    (construct (assurance-bind-obligation-to-snapshot obligation draft)
               evidence-value relation-values)))
(def (bound-obligation snapshot-value)
  (find (lambda (node)
          (equal? (.ref node 'identity) "obligation/test"))
        (.ref snapshot-value 'nodes)))
(def (outcome snapshot-value input-source)
  (assurance-verifier-outcome
   "outcome/test" 'succeeded
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   obligation: "obligation/test" subject: "job-executor" scope: "repository"
   snapshot-revision: (.ref snapshot-value 'revision)
   snapshot-context-digest: (.ref snapshot-value 'context-digest)
   inputs: (list (assurance-verifier-input input-source))
   output-digest: digest-b))
(def (host source-procedure source-reader: (reader #f))
  (assurance-verification-host
   "host/design-verification"
   (lambda (subject-value issued-at expires-at)
     (and (equal? (.ref (.ref subject-value 'outcome) 'output-digest) digest-b)
          (< issued-at expires-at)))
   (lambda () 11) 9 source-procedure source-reader: reader))
(def (review snapshot-value host-value input-source evidence-value)
  (let* ((bound (bound-obligation snapshot-value))
         (reported (outcome snapshot-value input-source))
         (subject (assurance-verification-subject
                   snapshot-value bound evidence-value reported))
         (admission (assurance-host-admit
                     host-value bound evidence-value reported))
         (mapping
          (sdlc-design-implementation-link contract guarantee source
                                           snapshot-value)))
    (values
     (sdlc-design-guarantee-support-review
      host-value contract guarantee (list mapping) claim subject
      evidence-link admission (if admission (list admission) '()))
     admission subject mapping)))

(def design-verification-test
  (test-suite "SDLC design guarantee Host support"
    (test-case "source-bound Host admission closes support but not conformance"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (configured (host (lambda () cut))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (check-equal? (.ref receipt 'source-bound-support-current?) #t)
          (check-equal? (.ref receipt 'source-bytes-checked-support-current?) #f)
          (check-equal? (.ref receipt 'verifier-independence-established?) #f)
          (check-equal? (.ref receipt 'implementation-conforms?) #f)
          (check-equal? (.ref receipt 'release-authorized?) #f)
          (check-equal? (.ref receipt 'runtime-executed?) #f))))
    (test-case "Host-owned source bytes must match the mapped digest"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (configured
              (host (lambda () cut)
                    source-reader: (lambda (identity)
                                     (and (equal? identity "artifact/source")
                                          source-bytes)))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (check-equal? (.ref receipt 'source-bytes-checked-support-current?) #t)
          (check-equal? (.ref receipt 'verifier-independence-established?) #f)
          (check-equal? (.ref receipt 'implementation-conforms?) #f))))
    (test-case "changed Host bytes fail closed"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (payload "different")
             (configured
              (host (lambda () cut)
                    source-reader: (lambda (identity) payload))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (check-equal? (.ref receipt 'source-bound-support-current?) #t)
          (check-equal? (.ref receipt 'source-bytes-checked-support-current?) #f)
          (set! payload source-bytes)
          (check-equal?
           (.ref (sdlc-design-guarantee-support-review
                  configured contract guarantee (list mapping) claim subject
                  evidence-link admission (list admission))
                 'source-bytes-checked-support-current?)
           #t))))
    (test-case "a cut moving during Host source read fails closed"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (next (bound-cut (list evidence-link requirement-link)
                              evidence))
             (current-cut cut)
             (configured
              (host (lambda () current-cut)
                    source-reader:
                    (lambda (identity)
                      (set! current-cut next)
                      source-bytes))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (check-equal? (.ref receipt 'source-bytes-checked-support-current?) #f))))
    (test-case "design assumptions cannot disappear from the Assurance Claim"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (configured (host (lambda () cut)))
             (assumed
              (sdlc-design-contract
               "job-executor" "r2" "ADR/job-executor"
               '("execute-job") '("job-ledger") '("external-operation")
               (list (sdlc-design-assumption
                      "provider-idempotency" "a1" "Provider deduplicates keys"))
               (list guarantee) '()))
             (reported (outcome cut source))
             (bound (bound-obligation cut))
             (subject (assurance-verification-subject
                       cut bound evidence reported))
             (admission (assurance-host-admit configured bound evidence reported))
             (mapping (sdlc-design-implementation-link
                       assumed guarantee source cut))
             (receipt
              (sdlc-design-guarantee-support-review
               configured assumed guarantee (list mapping) claim subject
               evidence-link admission (list admission))))
        (check-equal? (.ref receipt 'mapping-current?) #t)
        (check-equal? (.ref receipt 'claim-current?) #f)
        (check-equal? (.ref receipt 'source-bound-support-current?) #f)))
    (test-case "missing claim-to-source dependency blocks design support"
      (let* ((cut (bound-cut (list evidence-link requirement-link) evidence))
             (configured (host (lambda () cut))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (check-equal? (.ref receipt 'host-admission-current?) #t)
          (check-equal? (.ref receipt 'source-input-bound?) #f)
          (check-equal? (.ref receipt 'source-bound-support-current?) #f))))
    (test-case "admission over another current source does not cover design source"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             other-evidence))
             (configured (host (lambda () cut))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured other-source other-evidence)))
          (check-equal? (.ref receipt 'host-admission-current?) #t)
          (check-equal? (.ref receipt 'source-input-bound?) #f)
          (check-equal? (.ref receipt 'source-bound-support-current?) #f))))
    (test-case "revoked or copied admission cannot close support"
      (let* ((cut (bound-cut (list evidence-link requirement-link source-link)
                             evidence))
             (configured (host (lambda () cut))))
        (let-values (((receipt admission subject mapping)
                      (review cut configured source evidence)))
          (let ((copied (.o (:: @ admission)))
                (before (.ref receipt 'source-bound-support-current?)))
            (check-equal? before #t)
            (check-equal?
             (.ref (sdlc-design-guarantee-support-review
                    configured contract guarantee (list mapping) claim subject
                    evidence-link admission '())
                   'source-bound-support-current?)
             #f)
            (check-equal?
             (.ref (sdlc-design-guarantee-support-review
                    configured contract guarantee (list mapping) claim subject
                    evidence-link copied (list copied))
                   'source-bound-support-current?)
             #f)
            (assurance-host-revoke-admission! configured admission)
            (check-equal?
             (.ref (sdlc-design-guarantee-support-review
                    configured contract guarantee (list mapping) claim subject
                    evidence-link admission (list admission))
                   'source-bound-support-current?)
             #f)))))))
