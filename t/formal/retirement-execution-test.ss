;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Execute the bounded retirement-ingress controls against the local Scheme
;;; Host. The callback counter is an actual handoff result, not model metadata.
(import :std/test
        (only-in :clan/poo/object .ref)
        :poo-flow/lambda-aitia/modules/sdlc/retirement-host)
(export retirement-execution-test)

(def (accepted? result) (.ref result 'accepted?))
(def (reason result) (.ref result 'reason))
(def (ready-for-review host)
  (aitia-retirement-host-observe-completion! host)
  (aitia-retirement-host-observe-queue-drained! host)
  (aitia-retirement-host-complete-inventory! host)
  host)

(def retirement-execution-test
  (test-suite "Retirement ingress actual Scheme Host execution"
    (test-case "cancellation is not completion or queue drain"
      (let (host (aitia-retirement-host))
        (check (accepted? (aitia-retirement-host-request-cancellation! host)) => #t)
        (aitia-retirement-host-complete-inventory! host)
        (aitia-retirement-host-close-ingress! host)
        (check (reason (aitia-retirement-host-retire! host)) => 'active-work)
        (check (.ref (aitia-retirement-host-snapshot host) 'retired?) => #f)))
    (test-case "unfenced review cannot retire"
      (let (host (ready-for-review (aitia-retirement-host)))
        (check (accepted? (aitia-retirement-host-review-cut! host)) => #t)
        (check (reason (aitia-retirement-host-retire! host)) => 'ingress-open)
        (check (.ref (aitia-retirement-host-snapshot host) 'authority-epoch) => 0)
        (check (accepted? (aitia-retirement-host-close-ingress! host)) => #t)
        (check (.ref (aitia-retirement-host-snapshot host) 'authority-epoch) => 1)
        (check (accepted? (aitia-retirement-host-retire! host)) => #t)))
    (test-case "late work invalidates the old finalization attempt"
      (let (host (ready-for-review (aitia-retirement-host)))
        (aitia-retirement-host-review-cut! host)
        (aitia-retirement-host-observe-late-activity! host)
        (aitia-retirement-host-close-ingress! host)
        (check (reason (aitia-retirement-host-retire! host)) => 'active-work)
        (check (.ref (aitia-retirement-host-snapshot host) 'retired?) => #f)))
    (test-case "unknown inventory prevents retirement after review"
      (let (host (ready-for-review (aitia-retirement-host)))
        (aitia-retirement-host-review-cut! host)
        (aitia-retirement-host-observe-inventory-gap! host)
        (aitia-retirement-host-close-ingress! host)
        (check (reason (aitia-retirement-host-retire! host)) => 'inventory-unknown)
        (check (.ref (aitia-retirement-host-snapshot host) 'retired?) => #f)))
    (test-case "accepted current grant invokes one real Scheme handoff"
      (let* ((host (aitia-retirement-host))
             (calls 0)
             (reentered #f)
             (handoff (aitia-retirement-effect-handoff
                       (lambda ()
                         (set! calls (+ calls 1))
                         (set! reentered
                               (accepted? (aitia-retirement-host-request-start! host)))))))
        (check (accepted? (aitia-retirement-host-request-start! host)) => #t)
        (let (result (aitia-retirement-host-attempt-start! host handoff))
          (check (accepted? result) => #t)
          (check (.ref result 'handoff-executed?) => #t))
        (check calls => 1)
        (check reentered => #f)
        (check (accepted? (aitia-retirement-host-request-start! host)) => #f)
        (check (reason (aitia-retirement-host-retire! host)) => 'active-work)))
    (test-case "foreign thread cannot use the serialized Host"
      (let* ((host (aitia-retirement-host))
             (result
              (thread-join!
               (thread-start!
                (make-thread
                 (lambda ()
                   (with-catch (lambda (_failure) 'refused)
                               (lambda ()
                                 (aitia-retirement-host-close-ingress! host)
                                 'accepted))))))))
        (check result => 'refused)
        (check (.ref (aitia-retirement-host-snapshot host) 'ingress-open?) => #t)))
    (test-case "post-retirement cached grant cannot execute the handoff"
      (let* ((host (ready-for-review (aitia-retirement-host)))
             (calls 0)
             (handoff (aitia-retirement-effect-handoff
                       (lambda () (set! calls (+ calls 1))))))
        (aitia-retirement-host-review-cut! host)
        (aitia-retirement-host-close-ingress! host)
        (check (accepted? (aitia-retirement-host-retire! host)) => #t)
        (check (accepted? (aitia-retirement-host-request-start! host)) => #t)
        (let (result (aitia-retirement-host-attempt-start! host handoff))
          (check (accepted? result) => #f)
          (check (reason result) => 'stale-grant)
          (check (.ref result 'handoff-executed?) => #f))
        (check calls => 0)
        (check (.ref (aitia-retirement-host-snapshot host) 'active?) => #f)
        (check (.ref (aitia-retirement-host-snapshot host) 'retired?) => #t)))))
