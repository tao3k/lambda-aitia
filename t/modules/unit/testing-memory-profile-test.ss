;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-

(import :std/test
        (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-max-heap-mib-for
                 testing-interface-runtime-options-for)
        (only-in :poo-flow/lambda-aitia/testing-interface
                 +lambda-aitia-testing-interface+))

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
         "t/sdlc/source-admission-test.ss")))))
