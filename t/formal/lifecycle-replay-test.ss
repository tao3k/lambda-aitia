;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :clan/poo/object .ref)
        ./lifecycle-fixture)
(export lifecycle-replay-test)
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
                trace))) traces))))))
