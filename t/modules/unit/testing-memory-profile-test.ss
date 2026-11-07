;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-

(import :std/test
        (only-in :std/list/list take)
        (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-max-heap-mib-for
                 testing-interface-runtime-options-for
                 testing-interface-test-file-batches
                 testing-interface-test-file-isolated?)
        (only-in :lambda-aitia/testing-interface
                 +lambda-aitia-testing-interface+
                 lambda-aitia-sdlc-unit-testing-interface
                 lambda-aitia-sdlc-unit-test-order))

(export testing-memory-profile-test)

(def testing-memory-profile-test
  (test-suite "lambda-aitia bounded testing memory profiles"
    (test-case "ordinary tests default to a 512 MiB native heap"
      (check-equal?
       (testing-interface-max-heap-mib-for
        +lambda-aitia-testing-interface+
        "t/modules/unit/source-collection-test.ss")
       512)
      (check-equal?
       (testing-interface-runtime-options-for
        +lambda-aitia-testing-interface+
        "t/modules/unit/source-collection-test.ss")
       '("-:max-heap=512M")))

    (test-case "complete catalog tests remain bounded at 2 GiB"
      (for-each
       (lambda (path)
         (check-equal?
          (testing-interface-max-heap-mib-for
           +lambda-aitia-testing-interface+ path)
          2048)
         (check-equal?
          (testing-interface-runtime-options-for
           +lambda-aitia-testing-interface+ path)
          '("-:max-heap=2048M")))
       '("t/sdlc/unit/nasa-catalog-test.ss"
         "t/sdlc/unit/sdlc-trace-test.ss"
         "dev/proof/scheme/source-admission-test.ss")))
    (test-case "SDLC batches retain every fixture and never mix heap profiles"
      (let* ((files '("t/sdlc/unit/sdlc-model-test.ss"
                      "t/sdlc/unit/sdlc-flow-test.ss"
                      "t/sdlc/unit/nasa-catalog-test.ss"
                      "t/sdlc/unit/sdlc-trace-test.ss"))
             (testing (lambda-aitia-sdlc-unit-testing-interface files))
             (ordered (lambda-aitia-sdlc-unit-test-order testing files))
             (batches (testing-interface-test-file-batches testing ordered)))
        (check-equal? (testing-interface-test-file-isolated? testing (car files)) #t)
        (check-equal? (testing-interface-test-file-isolated? testing (caddr files)) #f)
        (check-equal? ordered (append (cddr files) (take files 2)))
        (check-equal? (apply append batches) ordered)
        (for-each
         (lambda (batch)
           (let (options (testing-interface-runtime-options-for testing (car batch)))
             (for-each
              (lambda (file)
                (check-equal? (testing-interface-runtime-options-for testing file) options)
                (check-equal? (testing-interface-test-file-isolated?
                               +lambda-aitia-testing-interface+ file)
                              #t))
              batch)))
         batches)))))
