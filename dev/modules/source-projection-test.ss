;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .call .get .ref)
        (only-in :std/source this-source-file)
        (only-in :tao3k/yuanxu/module-system/source/admission
                 call-with-module-source-operation-measurement)
        (only-in "../../init.ss" lambda-aitia.init.exports std-make-spec))
(export source-projection-test)

;;; No top-level Scope read: the first Case must measure a genuinely cold spec.
(def source-projection-test
  (test-suite "AITIA init-owned source projection and lazy Module scopes"
    (test-case "source specification constructs zero business scopes"
      (let-values (((spec counters)
                    (call-with-module-source-operation-measurement
                     (lambda () std-make-spec)
                     accounting?: #f)))
        (check-equal? (pair? spec) #t)
        (check-equal? (hash-ref counters '(calls scope-factory) 0) 0)))
    (test-case "selecting catalog tests by owner prepares no business Scope"
      (let-values (((files counters)
                    (call-with-module-source-operation-measurement
                     (lambda ()
                       (.get (.call (.get lambda-aitia.init.exports tests) .select
                               '(nasa-7150-2d-catalog)) spec))
                     accounting?: #f)))
        (check-equal? (map path-normalize files)
          (list (path-normalize
                 (path-expand "../../modules/nasa-7150-2d-catalog/tests/catalog-test.ss"
                              (path-directory (this-source-file))))))
        (check-equal? (hash-ref counters '(calls scope-factory) 0) 0)))
    (test-case "runtime demand constructs each declared owner once"
      (let-values (((scopes counters)
                    (call-with-module-source-operation-measurement
                     (lambda ()
                       (let (modules (.get lambda-aitia.init.exports modules))
                         (list (.get modules ADR) (.get modules assurance))))
                     accounting?: #f)))
        (check-equal? (hash-ref counters '(calls scope-factory) 0) 2)
        ;; Gerbil owner identities belong to AITIA, not its host checkout.
        (check-equal? (hash-ref counters
                         '(calls (scope-factory lambda-aitia/modules/ADR/interface)) 0) 1)
        (check-equal? (hash-ref counters
                         '(calls (scope-factory lambda-aitia/modules/assurance/interface)) 0) 1)
        (check-equal? (procedure? (.get (car scopes) record)) #t)
        (check-equal? (.ref (.get (cadr scopes) policy) 'grants-authority?) #f)
        (let-values (((again repeated)
                      (call-with-module-source-operation-measurement
                       (lambda ()
                         (.get (.get lambda-aitia.init.exports modules) ADR))
                       accounting?: #f)))
          (check-equal? (eq? again (car scopes)) #t)
          (check-equal? (hash-ref repeated '(calls scope-factory) 0) 0))))
    (test-case "GitOps is constructed only when demanded"
      (let-values (((scope counters)
                    (call-with-module-source-operation-measurement
                     (lambda ()
                       (.get (.get lambda-aitia.init.exports modules) gitops))
                     accounting?: #f)))
        (check-equal? (hash-ref counters '(calls scope-factory) 0) 1)
        (check-equal? (hash-ref counters
                         '(calls (scope-factory lambda-aitia/modules/gitops/interface)) 0) 1)
        (check-equal? (procedure? (.get scope evaluate)) #t)))))
