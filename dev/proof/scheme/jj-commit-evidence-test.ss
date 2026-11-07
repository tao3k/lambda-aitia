;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json read-json write-json)
        (only-in :clan/poo/object .get .o .cc)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export jj-commit-evidence-test)

;; This adapter lives in the qualification fixture. The capture comes from
;; the real Rust JJ adapter. The check observation is a controlled input.
(def (fixture-cut row)
  (.o project: "jj-qualification"
      workspace: (hash-ref row "workspace_name")
      change: (hash-ref row "change_id")
      operation: (hash-ref row "operation_id")
      commit: (hash-ref row "commit_id")
      tree: (hash-ref row "tree_id")
      parents: (hash-ref row "parent_ids")))

(def (evidence-fields cut producer)
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
        (cons "ID" "fixture-pass")
        (cons "OBLIGATION" "check")
        (cons "OUTCOME" "passed")))

(def (observation-source fields)
  (apply string-append
         "* Commit observation\n:PROPERTIES:\n"
         (append (map (lambda (field)
                        (string-append ":" (car field) ": " (cdr field) "\n"))
                      fields)
                 '(":END:\n"))))

(def jj-commit-evidence-test
  (test-suite "Real JJ cut to ASCENT evidence replay"
    (test-case "a rewrite preserves lineage while reopening the checked obligation"
      (let* ((path (getenv "AITIA_JJ_REPLAY_CUTS"))
             (cuts (call-with-input-file path
                     (lambda (port) (read-json port object-as-hash: #t array-as-vector: #f))))
             (before (fixture-cut (hash-ref cuts "before")))
             (rewritten (fixture-cut (hash-ref cuts "rewritten")))
             (producer "fixture-runner")
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
        (check-equal? (.get current reopened) '(("check")))))))
