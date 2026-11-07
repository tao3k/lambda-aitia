;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/test/base TestConfig TestModule TestHarness VERBOSITY-MODULE
                 test-run! test-result-ok?)
        :lambda-aitia/dev/proof/scheme/lifecycle-fixture)
(export lifecycle-replay-test run-lifecycle-replay)
(def lifecycle-replay-test
  (test-suite "Full bounded Quint lifecycle / real Scheme API graph replay"
    (test-case "every supplied edge has the same projected Scheme state"
      (let (file (getenv "AITIA_LIFECYCLE_REPLAY" #f))
        (unless file (error "run through just check-lifecycle-scheme"))
        (let (traces (call-with-input-file file read))
          (check-lifecycle-traces! traces))))))

;; Keep the standard harness, while each batch imports the same compiled
;; suite instead of discovering and expanding its source again.
(def (run-lifecycle-replay)
  (let* ((name "dev/proof/scheme/lifecycle-replay-test.ss")
         (config (TestConfig verbosity: VERBOSITY-MODULE capture-output?: #f))
         (module (TestModule name (list lifecycle-replay-test) '() void void))
         (result (test-run! (TestHarness name config (list module)))))
    (if (test-result-ok? result)
      (begin (displayln 'OK) (force-output) 0)
      42)))
