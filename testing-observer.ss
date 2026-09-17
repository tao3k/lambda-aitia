;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-call-with-operation
                 testing-interface-run-test!)
        (only-in ./testing-interface +lambda-aitia-testing-interface+))

(export run-observed-test)

(def (emit phase test-path)
  (display "[lambda-aitia-testing] phase=")
  (display phase)
  (display " test=")
  (display test-path)
  (newline)
  (force-output))

(def (run-observed-test test-path)
  (emit 'native-test-process-start test-path)
  (testing-interface-call-with-operation
   +lambda-aitia-testing-interface+
   'native-test-file
   (lambda ()
     (testing-interface-run-test!
      +lambda-aitia-testing-interface+
      test-path
      arguments: '("-v"))))
  (emit 'native-test-process-complete test-path))
