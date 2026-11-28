;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json read-json)
        (only-in :clan/poo/object .get .o .cc .ref)
        (only-in "./jj-evidence-fixture.ss" fixture-cut evidence-fields observation-source)
        (only-in :std/list/list find)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (rename-in (only-in :lambda-aitia/modules/gitops/config Config)
                   (Config GitOpsConfig))
        (rename-in (only-in :lambda-aitia/modules/assurance/config Config)
                   (Config AssuranceConfig)))
(export jj-recorded-evidence-test)

(def (check-recorded-support cuts before rewritten advanced)
  (let* ((runs (hash-ref cuts "runs"))
         (source-bytes (list->u8vector (hash-ref cuts "source")))
         (source-digest (source-lock-payload-digest source-bytes))
         (fixed (find (lambda (row) (equal? (hash-ref row "id") "fixed")) runs))
         (buggy (find (lambda (row) (equal? (hash-ref row "id") "buggy")) runs))
         (producer-id "aitia-runtime/pytest")
         (gitops GitOpsConfig)
         (assurance AssuranceConfig)
         (admit-receipt (.get gitops admit-commit-observation))
         (derive (.get gitops commit-evidence))
         (fixed-fact (admit-receipt
                      (observation-source (evidence-fields before producer-id "fixed" "passed"))
                      (.o cut: before identity: "fixed" obligation: "check" outcome: 'passed)
                      producer-id))
         (buggy-fact (admit-receipt
                      (observation-source (evidence-fields before producer-id "buggy" "failed" "buggy-check"))
                      (.o cut: before identity: "buggy" obligation: "buggy-check" outcome: 'failed)
                      producer-id))
         (project-id (.get before project))
         (commit-id (.get before commit))
         (artifact-id "artifact/recorded-adr-source")
         (claim-id "claim/adr-0008-bounded-replay")
         (scope-id (hash-ref fixed "selector"))
         (source-artifact ((.get assurance artifact) artifact-id commit-id 'supported source-digest
                            owner: producer-id media-kind: 'frozen-source))
         (claim-value ((.get assurance claim) claim-id commit-id 'unknown source-digest
                         subject: project-id predicate: "One commit in the fixed lost ACK replay"
                         support-requirements: '("check") scope: scope-id valid-from: "2026-11-09"))
         (obligation-value ((.get assurance obligation) "check" commit-id 'unknown source-digest
                              subject: project-id claim: claim-id snapshot: "adr-0008"
                              evidence-kind: 'replay capability: 'pytest scope: scope-id))
         (evidence-value ((.get assurance evidence)
                           "evidence/fixed" commit-id 'supported (hash-ref fixed "outputSha256")
                           producer: producer-id tool: "pytest" tool-version: "qualification"
                           input-artifacts: (list artifact-id) obligation: "check"
                           subject: project-id scope: scope-id valid-from: "2026-11-09"
                           admission-state: 'candidate))
         (relations (list
                     ((.get assurance relation) "supports" 'assurance 'supports "check" claim-id 'declared)
                     ((.get assurance relation) "discharges" 'assurance 'discharges
                      "evidence/fixed" "check" 'observed)))
         (make-snapshot (.get assurance snapshot)))
    (def (snapshot-at cut obligation-node)
      (make-snapshot "adr-0008" (.get cut commit) "adr-0008"
                     (list (cons artifact-id commit-id)) (list (cons claim-id commit-id))
                     (.get cut operation) "adr-0008" "qualification"
                     (list source-artifact claim-value obligation-node evidence-value) relations))
    (let* ((bound ((.get assurance bind-obligation)
                   obligation-value (snapshot-at before obligation-value)))
           (snapshot-value (snapshot-at before bound))
           (make-outcome (.get assurance verifier-outcome))
           (make-input (.get assurance verifier-input))
           (digest-outcome (.get assurance verifier-outcome-digest))
           (actual-outcome
            (make-outcome "fixed" 'succeeded
                          producer: producer-id tool: "pytest" tool-version: "qualification"
                          obligation: "check" subject: project-id scope: scope-id
                          snapshot-revision: commit-id
                          snapshot-context-digest: (.ref snapshot-value 'context-digest)
                          inputs: (list (make-input source-artifact))
                          output-digest: (hash-ref fixed "outputSha256")))
           (actual-digest (digest-outcome actual-outcome))
           (host ((.get assurance verification-host)
                  "host/recorded-adr"
                  (lambda (subject now expiry inputs) #t)
                  (lambda () 11) 9 (lambda () snapshot-value)
                  source-reader: (lambda (identity) (and (equal? identity artifact-id) source-bytes))
                  execution-reader: (lambda (identity) (and (equal? identity "fixed") actual-digest))))
           (admit (.get assurance host-admit))
           (assess (.get assurance host-required-support)))
      (check-equal? (hash-ref fixed "verdict") "passed")
      (check-equal? (hash-ref buggy "verdict") "process-failed")
      (check-equal? (hash-ref fixed "sourceSha256") source-digest)
      (check-equal? (hash-ref buggy "sourceSha256") source-digest)
      (check-equal? (and fixed-fact buggy-fact #t) #t)
      (let (assessment (derive before '("check" "buggy-check") (list fixed-fact buggy-fact)))
        (check-equal? (.get assessment supported) '(("fixed" "check")))
        (check-equal? (.get assessment contradicted) '(("buggy" "buggy-check"))))
      (check-equal? (.get (derive rewritten '("check") (list fixed-fact)) reopened)
                    '(("check")))
      (check-equal? (.get advanced tree) (.get before tree))
      (check-equal? (equal? (.get advanced change) (.get before change)) #f)
      (let (view (derive advanced '("check") (list fixed-fact)))
        (check-equal? (.get view supported) '())
        (check-equal? (.get view stale) '(("fixed" "check")))
        (check-equal? (.get view reopened) '(("check"))))
      (check (admit host bound evidence-value
                    (.cc actual-outcome subject: "another-project")) => #f)
      (check (admit host bound evidence-value
                    (.cc actual-outcome identity: "buggy"
                         output-digest: (hash-ref buggy "outputSha256"))) => #f)
      (let* ((admission (admit host bound evidence-value actual-outcome))
             (assessment (assess host claim-value (list admission))))
        (check-equal? (.ref assessment 'complete?) #t)
        (check-equal? (.ref assessment 'release-authorized?) #f)
        (set! snapshot-value (snapshot-at rewritten bound))
        (check-equal? ((.get assurance host-admission-current?) host admission) #f)
        (check-equal? (.ref (assess host claim-value (list admission)) 'complete?) #f)))))

(def jj-recorded-evidence-test
  (test-suite "Recorded JJ execution to ASCENT and Assurance"
    (test-case "observed outcomes follow their cuts without granting release authority"
      (let* ((path (getenv "AITIA_ADR_REPLAY_EVIDENCE"))
             (cuts (call-with-input-file path
                     (lambda (port) (read-json port object-as-hash: #t array-as-vector: #f))))
             (project-id (hash-ref cuts "project"))
             (before (fixture-cut project-id (hash-ref cuts "before")))
             (rewritten (fixture-cut project-id (hash-ref cuts "rewritten")))
             (advanced (fixture-cut project-id (hash-ref cuts "advanced"))))
        (check-recorded-support cuts before rewritten advanced)))))
