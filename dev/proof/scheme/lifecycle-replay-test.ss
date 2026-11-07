;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/test/base TestConfig TestModule TestHarness VERBOSITY-MODULE
                 test-run! test-result-ok?)
        (only-in :clan/poo/object .ref)
        :lambda-aitia/dev/proof/scheme/lifecycle-fixture)
(export lifecycle-replay-test run-lifecycle-replay)
(def lifecycle-replay-test
  (test-suite "Full bounded Quint lifecycle / real Scheme API graph replay"
    (test-case "every supplied edge has the same projected Scheme state"
      (let (file (getenv "AITIA_LIFECYCLE_REPLAY" #f))
        (unless file (error "run through just check-lifecycle-scheme"))
        (let (traces (call-with-input-file file read))
          (check (pair? traces) => #t)
          (for-each
           (lambda (trace)
             (let (fixture (make-lifecycle-fixture))
               (for-each
                (lambda (row)
                  (let ((action (car row)) (expected (cadr row)))
                    (if (memq action '(UnsafeStart UnsafeLateAdmit UnsafeEarlyGrant UnsafeAfterRevoke
                                      UnsafeDelivery UnsafeBeforeStart UnsafeReplay))
                      (let* ((before (lifecycle-state fixture))
                             (calls (lifecycle-get fixture 'delivery-calls))
                             (result (lifecycle-action! fixture action)))
                        (if (memq action '(UnsafeDelivery UnsafeBeforeStart UnsafeReplay))
                          (check (.ref result 'outcome) => 'rejected)
                          (check result => #f))
                        (check (lifecycle-get fixture 'delivery-calls) => calls)
                        (let (after (lifecycle-state fixture))
                          (for-each (lambda (field)
                                      (check (.ref after (car field)) => (.ref before (car field)))) expected)))
                      (begin
                        (let (result (lifecycle-action! fixture action))
                          (check (if result #t #f) => #t))
                        (let (actual (lifecycle-state fixture))
                          (for-each (lambda (field)
                                      (check (.ref actual (car field)) => (cadr field))) expected))))
                    (when (eq? action 'StartEffect)
                      (check (lifecycle-get fixture 'delivery-calls) => 0)
                      (check (lifecycle-get fixture 'service-effects) => 0))))
                trace)
               (displayln "LIFECYCLE-TRACE-COMPLETE steps=" (length trace))
               (force-output))) traces))))))

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
