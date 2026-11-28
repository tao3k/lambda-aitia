;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in "../harness/run-aitia-tests.ss" admit-aitia-test-layout!)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))
(export aitia-loader-ownership-test)

(def tests-root (path-normalize (path-expand ".." (path-directory (this-source-file)))))

(def aitia-loader-ownership-test
  (test-suite "Lambda Aitia init-owned downstream test publication"
    (test-case "declared owners discover their exact qualification files without running them"
      (def qualification (.get lambda-aitia.init.exports tests qualification))
      (def owners '(lambda-aitia/modules/ADR/interface
                    lambda-aitia/modules/assurance/interface
                    lambda-aitia/modules/gitops/interface
                    lambda-aitia/modules/sdlc/interface
                    lambda-aitia/user-interface/scenarios/aitia/interface))
      (def selected (.call qualification .select owners))
      (def graph-before (.ref/cached selected 'selected-graph))
      (check-equal? (eq? (.call selected .select owners) selected) #t)
      (def (test-files directory)
        (def path (path-expand directory tests-root))
        (map (cut path-expand <> path)
             (filter (cut string-suffix? "-test.ss" <>) (directory-files path))))
      (check-equal? (list-sort string<? (.get selected spec))
        (list-sort string<?
          (append (test-files "yanxu/modules/ADR")
                  (test-files "yanxu/modules/assurance")
                  (test-files "yanxu/modules/gitops")
                  (test-files "yanxu/modules/sdlc")
                  (test-files "yanxu/scenarios/aitia"))))
      (check-equal? (eq? (.get selected admit-current) (.get selected source admit-current)) #t)
      (for-each (lambda (name) (check-equal? (.slot? selected name) #f))
                '(.run .compile execution))
      ((.get selected admit-current))
      (check-equal? (eq? (.ref/cached selected 'selected-graph) graph-before) #t))
    (test-case "Loader owners publish all Lambda Aitia qualification test files"
      (check (admit-aitia-test-layout!) ? pair?))))
