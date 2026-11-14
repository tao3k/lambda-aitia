;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json read-json)
        (only-in :clan/poo/object .get .o .cc)
        (only-in :clan/poo/mop validate)
        (only-in "./jj-evidence-fixture.ss" fixture-cut evidence-fields observation-source)
        (only-in "../../../modules/gitops/config.ss" Config)
        (only-in "../../../modules/gitops/types.ss" GitOpsScopeContract))
(export jj-commit-evidence-test)

(def (check-commit-observation before rewritten)
  (let* ((producer "fixture-runner")
         (source (observation-source (evidence-fields before producer)))
         (gitops (validate GitOpsScopeContract Config))
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
             (before (fixture-cut "jj-qualification" (hash-ref cuts "before")))
             (rewritten (fixture-cut "jj-qualification" (hash-ref cuts "rewritten"))))
        (check-commit-observation before rewritten)))))
