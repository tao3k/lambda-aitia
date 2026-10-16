;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; ITF is projected to data, never evaluated. The native test lifecycle owns
;;; execution; the Quint runner only supplies model states and action names.
(import :std/test
        (only-in :clan/poo/object .ref)
        :poo-flow/lambda-aitia/modules/sdlc/retirement-host)
(export retirement-replay-test)

(def (invoke-action name host handoff)
  (case name
    ((init Terminal) #f)
    ((RequestCancellation) (aitia-retirement-host-request-cancellation! host))
    ((ObserveCompletion) (aitia-retirement-host-observe-completion! host))
    ((ObserveQueueDrained) (aitia-retirement-host-observe-queue-drained! host))
    ((CompleteInventory) (aitia-retirement-host-complete-inventory! host))
    ((ReviewCut) (aitia-retirement-host-review-cut! host))
    ((ObserveLateActivity) (aitia-retirement-host-observe-late-activity! host))
    ((ObserveInventoryGap) (aitia-retirement-host-observe-inventory-gap! host))
    ((CloseIngress) (aitia-retirement-host-close-ingress! host))
    ((Request) (aitia-retirement-host-request-start! host))
    ((Start Reject TrustCachedGrant) (aitia-retirement-host-attempt-start! host handoff))
    ((Retire RetireWithoutFence) (aitia-retirement-host-retire! host))
    (else (error "unknown replay action" name))))

(def (check-state host expected)
  (let (snapshot (aitia-retirement-host-snapshot host))
    (for-each (lambda (field)
                (check (.ref snapshot (car field)) => (cadr field))) expected)
    (check (.ref snapshot 'handoff-in-progress?) => #f)))

(def (replay lane trace)
  (let* ((host (aitia-retirement-host))
         (calls 0)
         (expected-calls 0)
         (handoff (aitia-retirement-effect-handoff
                   (lambda () (set! calls (+ calls 1))))))
    (let loop ((states trace))
      (unless (null? states)
        (let* ((row (car states)) (name (car row))
               (before (aitia-retirement-host-snapshot host))
               (result (invoke-action name host handoff))
               (fault? (and (not (eq? lane 'safe)) (null? (cdr states)))))
          (cond
           (fault?
            (check (memq name '(RetireWithoutFence TrustCachedGrant)) ? pair?)
            (check (.ref result 'accepted?) => #f)
            (check (.ref result 'handoff-executed?) => #f)
            (check (.ref result 'reason)
                   => (if (eq? name 'RetireWithoutFence) 'ingress-open 'stale-grant))
            ;; The intentionally unsafe model's final state must NOT match
            ;; Scheme. Compare the unchanged cut, except consumed start flags.
            (for-each
             (lambda (slot)
               (check (.ref (aitia-retirement-host-snapshot host) slot)
                      => (.ref before slot)))
             '(active? queued? retired? ingress-open? authority-epoch))
            (when (eq? name 'TrustCachedGrant)
              (check (.ref (aitia-retirement-host-snapshot host) 'pending?) => #f)
              (check (.ref (aitia-retirement-host-snapshot host) 'attempted?) => #t)))
           (else
            (when result
              (check (.ref result 'accepted?) => (not (eq? name 'Reject)))
              (check (.ref result 'handoff-executed?)
                     => (if (memq name '(Start TrustCachedGrant)) #t #f)))
            (when (memq name '(Start TrustCachedGrant))
              (set! expected-calls (+ expected-calls 1)))
            (check-state host (cadr row))))
          (check calls => expected-calls)
          (loop (cdr states)))))))

(def retirement-replay-test
  (test-suite "Quint MBT / real Scheme Host correspondence"
    (test-case "safe state traces and typed unsafe-model refusals"
      (let (fixture (getenv "AITIA_QUINT_REPLAY" #f))
        (unless fixture (error "run via just check-quint-scheme; model traces are required"))
        (let (lanes (call-with-input-file fixture read))
          (check (map car lanes) => '(safe unfenced cached))
          (for-each
           (lambda (lane)
             (check (pair? (cadr lane)) => #t)
             (for-each (lambda (trace) (replay (car lane) trace)) (cadr lane)))
           lanes))))))
