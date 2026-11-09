;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json read-json write-json)
        (only-in :clan/poo/object .get .o .cc .ref)
        (only-in :std/list/list find)
        (only-in :yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export jj-commit-evidence-test)

;; This adapter lives in the qualification fixture. The capture comes from
;; the real Rust JJ adapter. The check observation is a controlled input.
(def (fixture-cut project-id row)
  (.o project: project-id
      workspace: (hash-ref row "workspace_name")
      change: (hash-ref row "change_id")
      operation: (hash-ref row "operation_id")
      commit: (hash-ref row "commit_id")
      tree: (hash-ref row "tree_id")
      parents: (hash-ref row "parent_ids")))

(def (evidence-fields cut producer (identity "fixture-pass") (outcome "passed") (obligation "check"))
  (list (cons "PROJECT" (.get cut project))
        (cons "WORKSPACE" (.get cut workspace))
        (cons "CHANGE" (.get cut change))
        (cons "OPERATION" (.get cut operation))
        (cons "COMMIT" (.get cut commit))
        (cons "TREE" (.get cut tree))
        (cons "PARENTS" (call-with-output-string
                         (lambda (port)
                           (write-json port (list->vector (.get cut parents))))))
        (cons "PRODUCER" producer)
        (cons "ID" identity)
        (cons "OBLIGATION" obligation)
        (cons "OUTCOME" outcome)))

(def (observation-source fields)
  (apply string-append
         "* Commit observation\n:PROPERTIES:\n"
         (append (map (lambda (field)
                        (string-append ":" (car field) ": " (cdr field) "\n"))
                      fields)
                 '(":END:\n"))))

(def (check-recorded-support cuts before rewritten advanced)
  (let* ((runs (hash-ref cuts "runs"))
         (source-bytes (list->u8vector (hash-ref cuts "source")))
         (source-digest (source-lock-payload-digest source-bytes))
         (fixed (find (lambda (row) (equal? (hash-ref row "id") "fixed")) runs))
         (buggy (find (lambda (row) (equal? (hash-ref row "id") "buggy")) runs))
         (producer-id "aitia-runtime/pytest")
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (assurance (.get lambda-aitia.init.exports modules assurance))
         (admit-org (.get gitops admit-commit-observation))
         (derive (.get gitops commit-evidence))
         (fixed-fact (admit-org
                      (observation-source (evidence-fields before producer-id "fixed" "passed"))
                      (.o cut: before identity: "fixed" obligation: "check" outcome: 'passed)
                      producer-id))
         (buggy-fact (admit-org
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

(def (check-commit-observation before rewritten)
  (let* ((producer "fixture-runner")
         (source (observation-source (evidence-fields before producer)))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (admit (.get gitops admit-commit-observation))
         (expected (.o cut: before identity: "fixture-pass"
                       obligation: "check" outcome: 'passed))
         (observation (admit source expected producer))
         (evaluate (.get gitops commit-evidence))
         (original (evaluate before '("check") (list observation)))
         (current (evaluate rewritten '("check") (list observation))))
    (check (admit source (.o cut: rewritten identity: "fixture-pass"
                                           obligation: "check" outcome: 'passed) producer) => #f)
    (check (admit
            (observation-source (evidence-fields before "claimed-runner"))
            expected producer) => #f)
    (check (admit (string-append source "* Extra headline\n")
                              expected producer) => #f)
    (check (admit "#+title: No observation\n" expected producer) => #f)
    (check (admit source (.o cut: before identity: "fixture-pass"
                             obligation: "check" outcome: 'failed)
                  producer) => #f)
    (check (admit (observation-source
                   (evidence-fields (.cc before parents: '()) producer))
                  expected producer) => #f)
    (check-equal? (.get before change) (.get rewritten change))
    (check-equal? (.get original supported) '(("fixture-pass" "check")))
    (check-equal? (.get original open) '())
    (check-equal? (.get current supported) '())
    (check-equal? (.get current stale) '(("fixture-pass" "check")))
    (check-equal? (.get current reopened) '(("check")))))

(def jj-commit-evidence-test
  (test-suite "Real JJ cut to ASCENT evidence replay"
    (test-case "a rewrite preserves lineage while reopening the checked obligation"
      (let* ((path (getenv "AITIA_JJ_REPLAY_CUTS"))
             (cuts (call-with-input-file path
                     (lambda (port) (read-json port object-as-hash: #t array-as-vector: #f))))
             (project-id (if (hash-get cuts "runs") (hash-ref cuts "project") "jj-qualification"))
             (before (fixture-cut project-id (hash-ref cuts "before")))
             (rewritten (fixture-cut project-id (hash-ref cuts "rewritten"))))
        (if (hash-get cuts "runs")
          (check-recorded-support cuts before rewritten
                                  (fixture-cut project-id (hash-ref cuts "advanced")))
          (check-commit-observation before rewritten))))))
