;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/error (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface
        :poo-flow/lambda-aitia/t/formal/lifecycle-fixture)
(export lifecycle-boundary-test)
(def (drive fixture actions)
  (for-each (lambda (action) (check (lifecycle-action! fixture action) => #t)) actions)
  fixture)
(def (ready)
  (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify Admit Decide Authorize)))
(def lifecycle-boundary-test
  (test-suite "Lifecycle authorization, reservation and delivery boundaries"
    (test-case "Admit consumes the prior seal without executing or renewing verification"
      (let (f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify)))
        (check (lifecycle-get f 'verifier-calls) => 1)
        (check (lifecycle-action! f 'Admit) => #t)
        (check (lifecycle-get f 'verifier-calls) => 1)
        (check (.ref (lifecycle-get f 'admission) 'expires-at) => 1))
      (let (f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify Tick)))
        (check (lifecycle-action! f 'Admit) => #f)
        (check (lifecycle-get f 'verifier-calls) => 1)))
    (test-case "untrusted report cannot admit authorize reserve or deliver"
      (let (f (drive (make-lifecycle-fixture) '(ReportSuccess)))
        (check (lifecycle-action! f 'UnsafeLateAdmit) => #f)
        (check (lifecycle-action! f 'UnsafeEarlyGrant) => #f)
        (check (lifecycle-action! f 'UnsafeStart) => #f)
        (check (.ref (lifecycle-action! f 'UnsafeBeforeStart) 'outcome) => 'rejected)
        (check (lifecycle-get f 'authorization-calls) => 0)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "copied seals and foreign Host seals cannot admit"
      (let* ((f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify)))
             (other (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify)))
             (seal (lifecycle-get f 'seal)))
        (lifecycle-set! f 'seal (.o (:: @ seal)))
        (check (lifecycle-action! f 'Admit) => #f)
        (lifecycle-set! f 'seal (lifecycle-get other 'seal))
        (check (lifecycle-action! f 'Admit) => #f)))
    (test-case "deny and indeterminate never receive a grant"
      (for-each
       (lambda (mode)
         (let (f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify Admit Decide)))
           (lifecycle-set! f 'policy-mode mode)
           (check (lifecycle-action! f 'Authorize) => #f)
           (check (lifecycle-get f 'authorization-calls) => 1)
           (check (lifecycle-action! f 'StartEffect) => #f)
           (check (lifecycle-get f 'delivery-calls) => 0))) '(forbid indeterminate)))
    (test-case "reserve is not delivery; current reservation hands off exactly once"
      (let (f (ready))
        (check (lifecycle-action! f 'StartEffect) => #t)
        (check (lifecycle-get f 'service-effects) => 0)
        (check (lifecycle-action! f 'StartEffect) => #f)
        (check (.ref (lifecycle-action! f 'DeliverEffect) 'delivered?) => #t)
        (check (.ref (lifecycle-action! f 'UnsafeReplay) 'outcome) => 'rejected)
        (check (lifecycle-get f 'delivery-calls) => 1)
        (check (lifecycle-get f 'service-effects) => 1)))
    (test-case "renewed verification does not renew an old grant or reservation"
      (let (f (ready))
        (check (lifecycle-action! f 'Verify) => #t)
        (check (lifecycle-action! f 'StartEffect) => #t)
        (check (.ref (lifecycle-action! f 'DeliverEffect) 'delivered?) => #t))
      (let (f (drive (ready) '(StartEffect Tick Verify Admit Decide Authorize)))
        (check (.ref (lifecycle-get f 'grant) 'expires-at) => 2)
        (check (.ref (lifecycle-action! f 'DeliverEffect) 'outcome) => 'rejected)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "expiry revoke and source change between reserve and delivery fail closed"
      (for-each
       (lambda (change)
         (let (f (drive (ready) '(StartEffect)))
           (check (lifecycle-action! f change) => #t)
           (check (.ref (lifecycle-action! f 'UnsafeDelivery) 'outcome) => 'rejected)
           (check (lifecycle-get f 'delivery-calls) => 0)
           (check (lifecycle-get f 'service-effects) => 0))) '(Tick Revoke ChangeSource)))
    (test-case "source change during authorization cannot publish a grant"
      (let (f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify Admit Decide)))
        (lifecycle-set! f 'authorization-hook
          (lambda () (lifecycle-set! f 'cut (lifecycle-cut 2))))
        (check (lifecycle-action! f 'Authorize) => #f)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "permit cannot publish after policy callback expiry or request mutation"
      (for-each
       (lambda (change)
         (let* ((f (ready)) (request (lifecycle-get f 'request)))
           (lifecycle-set! f 'authorization-hook
             (lambda ()
               (case change
                 ((expiry) (lifecycle-set! f 'clock 1))
                 ((request) (string-set! (.ref request 'action) 0 #\X)))))
           (check (assurance-effect-host-authorize! (lifecycle-get f 'effect-host)
                    (lifecycle-get f 'verification-host) request) => #f)
           (check (lifecycle-get f 'authorization-calls) => 2)
           (check (lifecycle-action! f 'StartEffect) => #f)
           (check (lifecycle-get f 'delivery-calls) => 0))) '(expiry request)))
    (test-case "copied grant extended expiry and copied reservation are refused"
      (let* ((f (ready)) (host (lifecycle-get f 'effect-host))
             (grant (lifecycle-get f 'grant)))
        (check (assurance-effect-host-reserve! host (.o (:: @ grant))) => #f)
        (check (assurance-effect-host-reserve! host (.o (:: @ grant) expires-at: 99)) => #f)
        (let (reservation (assurance-effect-host-reserve! host grant))
          (check (.ref (assurance-effect-host-deliver! host (.o (:: @ reservation))) 'outcome) => 'rejected)
          (check (.ref (assurance-effect-host-deliver! host reservation) 'delivered?) => #t))))
    (test-case "foreign Host grant and reservation never reach a runtime callback"
      (let* ((f (ready)) (other (ready)) (host (lifecycle-get other 'effect-host))
             (grant (lifecycle-get f 'grant)))
        (check (assurance-effect-host-reserve! host grant) => #f)
        (check (lifecycle-action! f 'StartEffect) => #t)
        (check (.ref (assurance-effect-host-deliver! host (lifecycle-get f 'reservation)) 'outcome) => 'rejected)
        (check (lifecycle-get other 'delivery-calls) => 0)
        (check (.ref (lifecycle-action! f 'DeliverEffect) 'delivered?) => #t)))
    (test-case "issued token binding mutation fails closed, including after reservation"
      (for-each
       (lambda (reserve-first?)
         (let* ((f (ready)) (grant (lifecycle-get f 'grant))
                (binding (.ref (.ref grant 'token) 'binding))
                (digest (.ref binding 'bundle-digest)))
           (when reserve-first? (check (lifecycle-action! f 'StartEffect) => #t))
           (string-set! digest 0 (if (char=? (string-ref digest 0) #\a) #\b #\a))
           (if reserve-first?
             (check (.ref (lifecycle-action! f 'DeliverEffect) 'outcome) => 'rejected)
             (check (lifecycle-action! f 'StartEffect) => #f))
           (check (lifecycle-get f 'delivery-calls) => 0))) '(#f #t)))
    (test-case "copied and intent-substituted requests cannot invoke authorization"
      (let* ((f (ready)) (host (lifecycle-get f 'effect-host))
             (vh (lifecycle-get f 'verification-host)) (request (lifecycle-get f 'request)))
        (check (assurance-effect-host-authorize! host vh (.o (:: @ request))) => #f)
        (check (assurance-effect-host-authorize! host vh (.o (:: @ request) intent: "other")) => #f)
        (check (lifecycle-get f 'authorization-calls) => 1)))
    (test-case "observed source ABA cannot revive an old grant"
      (let* ((f (ready)) (cut (lifecycle-get f 'cut)))
        (lifecycle-set! f 'cut (lifecycle-cut 2))
        (check (lifecycle-action! f 'StartEffect) => #f)
        (lifecycle-set! f 'cut cut)
        (check (lifecycle-action! f 'StartEffect) => #f)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "in-place request string and handoff payload changes revoke the frozen request"
      (for-each
       (lambda (field)
         (let* ((f (ready)) (request (lifecycle-get f 'request))
                (text (if (eq? field 'payload-hex)
                        (.ref (.ref request 'handoff) field) (.ref request field))))
           (string-set! text 0 (if (char=? (string-ref text 0) #\a) #\b #\a))
           (check (assurance-host-cedar-request-current? (lifecycle-get f 'verification-host) request) => #f)
           (check (assurance-effect-host-authorize! (lifecycle-get f 'effect-host)
                    (lifecycle-get f 'verification-host) request) => #f)
           (check (lifecycle-action! f 'StartEffect) => #f)
           (check (lifecycle-get f 'authorization-calls) => 1)
           (check (lifecycle-get f 'delivery-calls) => 0))) '(intent action payload-hex)))
    (test-case "authorization exception releases the fence without publishing authority"
      (let (f (drive (make-lifecycle-fixture) '(InstallAdapter Plan Verify Admit Decide)))
        (lifecycle-set! f 'authorization-hook (lambda () (error "policy runtime failure")))
        (check-exception (lifecycle-action! f 'Authorize) Error?)
        (check (lifecycle-get f 'grant) => #f)
        (lifecycle-set! f 'authorization-hook #f)
        (check (lifecycle-action! f 'Authorize) => #t)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "unknown acknowledgement is not delivered and cannot be retried"
      (let (f (drive (ready) '(StartEffect)))
        (check (.ref (lifecycle-action! f 'UnknownDelivery) 'delivered?) => #f)
        (check (lifecycle-get f 'service-effects) => 1)
        (check (.ref (lifecycle-action! f 'UnsafeReplay) 'outcome) => 'rejected)
        (check (lifecycle-get f 'service-effects) => 1)))
    (test-case "failed delivery is attributable failure, not success or retry authority"
      (let (f (drive (ready) '(StartEffect)))
        (check (.ref (lifecycle-action! f 'FailDelivery) 'outcome) => 'failed)
        (check (lifecycle-get f 'service-effects) => 0)
        (check (.ref (lifecycle-action! f 'UnsafeReplay) 'outcome) => 'rejected)
        (check (lifecycle-get f 'delivery-calls) => 1)))
    (test-case "malformed acknowledgement consumes the attempt without success or retry"
      (let (f (drive (ready) '(StartEffect)))
        ;; Use the API directly: the model fixture deliberately chooses only
        ;; its three typed runtime outcomes.
        (lifecycle-set! f 'delivery-mode 'not-an-acknowledgement)
        (check-exception (assurance-effect-host-deliver! (lifecycle-get f 'effect-host)
                           (lifecycle-get f 'reservation)) Error?)
        (check (.ref (lifecycle-action! f 'UnsafeReplay) 'outcome) => 'rejected)
        (check (lifecycle-get f 'delivery-calls) => 1)))
    (test-case "deadline crossed during grant validation cannot reserve or deliver"
      (for-each
       (lambda (reserve-first?)
         (let ((f (ready)) (reads 0))
           (when reserve-first? (check (lifecycle-action! f 'StartEffect) => #t))
           ;; The effect clock advances from 0 to the strict deadline during
           ;; this API call. The verification Host remains current at 0.
           (lifecycle-set! f 'effect-clock-hook
             (lambda ()
               (let (now (min reads 1))
                 (set! reads (+ reads 1))
                 now)))
           (if reserve-first?
             (check (.ref (lifecycle-action! f 'DeliverEffect) 'outcome) => 'rejected)
             (check (lifecycle-action! f 'StartEffect) => #f))
           (check reads => 2)
           (check (lifecycle-get f 'delivery-calls) => 0)
           (check (lifecycle-get f 'service-effects) => 0))) '(#f #t)))
    (test-case "clock rollback cannot restore an expired grant"
      (let* ((f (ready)) (host (lifecycle-get f 'effect-host)))
        (lifecycle-set! f 'clock 1)
        (check (assurance-effect-host-grant-current? host (lifecycle-get f 'grant)) => #f)
        (lifecycle-set! f 'clock 0)
        (check-exception (lifecycle-action! f 'StartEffect) Error?)
        (check (lifecycle-get f 'delivery-calls) => 0)))
    (test-case "throwing and reentrant delivery stays consumed and releases the transient fence"
      (let (f (drive (ready) '(StartEffect)))
        (lifecycle-set! f 'delivery-hook
          (lambda ()
            (check-exception (assurance-effect-host-revoke! (lifecycle-get f 'effect-host)) Error?)
            (error "runtime failure")))
        (check-exception (lifecycle-action! f 'DeliverEffect) Error?)
        (check (.ref (lifecycle-action! f 'UnsafeReplay) 'outcome) => 'rejected)
        (assurance-effect-host-revoke! (lifecycle-get f 'effect-host))
        (check (lifecycle-get f 'delivery-calls) => 1)))))
