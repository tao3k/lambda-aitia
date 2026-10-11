;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; This fixture drives real plan / verification / admission / preflight /
;;; token / reservation APIs. It never imports model expected states.
;;; Configured local runtime callbacks are controls, not a native Cedar proof.
(import :std/test (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface
        (only-in :poo-flow/modules/authorization/providers/cedar/interface
                 poo-flow-cedar-decision poo-flow-cedar-runtime-handoff))
(export make-lifecycle-fixture lifecycle-action! lifecycle-state
        lifecycle-get lifecycle-set! lifecycle-cut)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def (lifecycle-cut revision)
  (let* ((rev (number->string revision))
         (artifact (assurance-artifact "source" rev 'supported
                     (if (= revision 1) digest-a digest-b) owner: "fixture" media-kind: 'scheme-source))
         (claim (assurance-claim "claim" rev 'unknown digest-b subject: "release" predicate: "ready"
                  support-requirements: '("test") scope: "repo" valid-from: "2026-10-11"))
         (obligation (assurance-obligation "test" rev 'unknown digest-a subject: "release"
                       claim: "claim" snapshot: "cut" evidence-kind: 'native-test
                       capability: 'gerbil-test scope: "repo"))
         (evidence (assurance-evidence "evidence" rev 'supported digest-b producer: "fixture"
                     tool: "local-verifier" tool-version: "1" input-artifacts: '("source")
                     obligation: "test" subject: "release" scope: "repo"
                     valid-from: "2026-10-11" admission-state: 'candidate))
         (decision (assurance-decision "decision" rev 'unknown digest-a subject: "release"
                     snapshot: "cut" policy: "policy" authority: "owner" outcome: 'unknown))
         (relations (list
                     (assurance-relation "input" 'structural 'depends-on "claim" "source" 'declared)
                     (assurance-relation "support" 'assurance 'supports "test" "claim" 'declared)
                     (assurance-relation "discharge" 'assurance 'discharges "evidence" "test" 'observed)
                     (assurance-relation "decision-input" 'structural 'depends-on "decision" "claim" 'declared))))
    (def (snapshot bound)
      (assurance-snapshot "cut" rev "graph" (list (cons "source" rev))
        (list (cons "claim" rev)) (string-append "events/" rev) "policy" "1"
        (list artifact claim bound evidence decision) relations))
    (let* ((bound (assurance-bind-obligation-to-snapshot obligation (snapshot obligation)))
           (cut (snapshot bound))
           (outcome (assurance-verifier-outcome "outcome" 'succeeded producer: "fixture"
                      tool: "local-verifier" tool-version: "1" obligation: "test"
                      subject: "release" scope: "repo" snapshot-revision: rev
                      snapshot-context-digest: (.ref cut 'context-digest)
                      inputs: (list (assurance-verifier-input artifact)) output-digest: digest-b)))
      (let ((revision-value revision) (evidence-value evidence) (outcome-value outcome)
            (claim-value claim) (decision-value decision))
        (.o revision: revision-value snapshot: cut obligation: bound evidence: evidence-value
            outcome: outcome-value claim: claim-value decision: decision-value)))))
(def cuts (vector (lifecycle-cut 1) (lifecycle-cut 2)))
(def (lifecycle-get fixture key) (hash-ref fixture key))
(def (lifecycle-set! fixture key value) (hash-put! fixture key value))
(def (increment! fixture key) (lifecycle-set! fixture key (+ 1 (lifecycle-get fixture key))))
(def (make-lifecycle-fixture)
  (let (fixture (make-hash-table-eq))
    (for-each (lambda (key) (lifecycle-set! fixture key #f))
              '(installed reported plan seal admission admission-seal preflight request grant reservation
                started authorization-hook delivery-hook))
    (for-each (lambda (key) (lifecycle-set! fixture key 0))
              '(clock verifier-calls authorization-calls delivery-calls service-effects
                grant-epoch grant-until reservation-revision reservation-epoch reservation-until delivery-status))
    (lifecycle-set! fixture 'delivery-mode 'delivered)
    (lifecycle-set! fixture 'policy-mode 'permit)
    (lifecycle-set! fixture 'cut (vector-ref cuts 0))
    (lifecycle-set! fixture 'verification-host
      (assurance-verification-host "lifecycle/verification"
        (lambda (subject now until)
          (increment! fixture 'verifier-calls)
          (lifecycle-get fixture 'installed))
        (lambda () (lifecycle-get fixture 'clock)) 1
        (lambda () (.ref (lifecycle-get fixture 'cut) 'snapshot))))
    (lifecycle-set! fixture 'effect-host
      (assurance-effect-host
        (lambda (request)
          (increment! fixture 'authorization-calls)
          (when (lifecycle-get fixture 'authorization-hook)
            ((lifecycle-get fixture 'authorization-hook)))
          (poo-flow-cedar-decision "local-runtime-decision" (lifecycle-get fixture 'policy-mode)
            "policy" digest-a digest-b '()))
        (lambda (request token)
          (increment! fixture 'delivery-calls)
          (when (lifecycle-get fixture 'delivery-hook)
            ((lifecycle-get fixture 'delivery-hook)))
          (unless (eq? (lifecycle-get fixture 'delivery-mode) 'failed)
            (increment! fixture 'service-effects))
          (lifecycle-get fixture 'delivery-mode))
        (lambda () (lifecycle-get fixture 'clock)) 1))
    fixture))

(def (lifecycle-action! fixture name)
  (let* ((cut (lifecycle-get fixture 'cut)) (vh (lifecycle-get fixture 'verification-host))
         (rh (lifecycle-get fixture 'effect-host))
         (snapshot (.ref cut 'snapshot)) (obligation (.ref cut 'obligation))
         (evidence (.ref cut 'evidence)) (outcome (.ref cut 'outcome)))
    (case name
      ((init Terminal) #t)
      ((InstallAdapter) (lifecycle-set! fixture 'installed #t) #t)
      ((ReportSuccess) (lifecycle-set! fixture 'reported #t) #t)
      ((Plan)
       (let (plan (assurance-plan-verification "plan" snapshot '("source")
                     (assurance-verification-policy "policy" "1" '(gerbil-test))))
         (unless (equal? (.ref plan 'selected-obligations) '("test"))
           (error "fixture obligation was not selected"))
         (lifecycle-set! fixture 'plan plan) #t))
      ((Verify)
       (and (lifecycle-get fixture 'plan)
            (let (seal (assurance-host-verify vh snapshot obligation evidence outcome))
              (lifecycle-set! fixture 'seal seal) (if seal #t #f))))
      ((Admit UnsafeLateAdmit)
       (let (admission (assurance-host-admit-verified vh obligation evidence outcome
                         (lifecycle-get fixture 'seal)))
         (when admission
           (lifecycle-set! fixture 'admission admission)
           (lifecycle-set! fixture 'admission-seal (lifecycle-get fixture 'seal)))
         (if admission #t #f)))
      ((Decide)
       (let (preflight (assurance-host-preflight-decision vh (.ref cut 'decision)
                         (.ref cut 'claim) (if (lifecycle-get fixture 'admission)
                                            (list (lifecycle-get fixture 'admission)) '())))
         (when preflight (lifecycle-set! fixture 'preflight preflight))
         (if preflight #t #f)))
      ((Authorize UnsafeEarlyGrant)
       (let* ((request (assurance-host-cedar-request vh (lifecycle-get fixture 'preflight)
                         (string-copy "Release") (string-copy digest-a) (poo-flow-cedar-runtime-handoff
                                              1 #u8(1) digest-a digest-a digest-b digest-b)))
              (grant (and request (assurance-effect-host-authorize! rh vh request))))
         (when grant
           (lifecycle-set! fixture 'request request)
           (lifecycle-set! fixture 'grant grant)
           (lifecycle-set! fixture 'grant-epoch (.ref grant 'epoch))
           (lifecycle-set! fixture 'grant-until (.ref grant 'expires-at)))
         (if grant #t #f)))
      ((StartEffect UnsafeStart UnsafeAfterRevoke)
       (let (reservation (assurance-effect-host-reserve! rh (lifecycle-get fixture 'grant)))
         (when reservation
           (lifecycle-set! fixture 'reservation reservation)
           (lifecycle-set! fixture 'started #t)
           (lifecycle-set! fixture 'reservation-revision (.ref cut 'revision))
           (lifecycle-set! fixture 'reservation-epoch (lifecycle-get fixture 'grant-epoch))
           (lifecycle-set! fixture 'reservation-until (lifecycle-get fixture 'grant-until)))
         (if reservation #t #f)))
      ((DeliverEffect RejectDelivery FailDelivery UnknownDelivery UnsafeDelivery UnsafeBeforeStart UnsafeReplay)
       (lifecycle-set! fixture 'delivery-mode
         (case name ((FailDelivery) 'failed) ((UnknownDelivery) 'indeterminate) (else 'delivered)))
       (let* ((receipt (assurance-effect-host-deliver! rh (lifecycle-get fixture 'reservation)))
              (status (case (.ref receipt 'outcome)
                        ((delivered) 1) ((rejected) 2) ((failed) 3) ((indeterminate) 4))))
         ;; Unsafe probes must not rewrite an already attributable outcome.
         (unless (memq name '(UnsafeDelivery UnsafeBeforeStart UnsafeReplay))
           (lifecycle-set! fixture 'delivery-status status))
         receipt))
      ((Tick) (increment! fixture 'clock) #t)
      ((ChangeSource)
       (lifecycle-set! fixture 'cut (vector-ref cuts 1))
       (for-each (lambda (key) (lifecycle-set! fixture key #f)) '(plan seal admission preflight request))
       (lifecycle-set! fixture 'grant-until 0) #t)
      ((Revoke)
       (when (lifecycle-get fixture 'admission)
         (assurance-host-revoke-admission! vh (lifecycle-get fixture 'admission)))
       (when (and (lifecycle-get fixture 'seal)
                  (not (eq? (lifecycle-get fixture 'seal) (lifecycle-get fixture 'admission-seal))))
         (assurance-host-revoke! vh (lifecycle-get fixture 'seal)))
       (for-each (lambda (key) (lifecycle-set! fixture key #f)) '(seal admission preflight request))
       (assurance-effect-host-revoke! rh) #t)
      (else (error "unknown lifecycle action" name)))))

(def (lifecycle-state fixture)
  (let* ((cut (lifecycle-get fixture 'cut)) (rev (.ref cut 'revision))
         (vh (lifecycle-get fixture 'verification-host)) (rh (lifecycle-get fixture 'effect-host))
         (seal (lifecycle-get fixture 'seal)) (grant (lifecycle-get fixture 'grant)))
    (.o revision: rev planned: (if (lifecycle-get fixture 'plan) rev 0)
        verified: (if seal rev 0) sealUntil: (if seal (.ref seal 'expires-at) 0)
        admitted: (if (assurance-host-admission-current? vh (lifecycle-get fixture 'admission)) rev 0)
        decided: (if (assurance-host-decision-preflight-current? vh (lifecycle-get fixture 'preflight)) rev 0)
        granted: (if (assurance-effect-host-grant-current? rh grant) rev 0)
        grantEpoch: (lifecycle-get fixture 'grant-epoch) grantUntil: (lifecycle-get fixture 'grant-until)
        epoch: (assurance-effect-host-epoch rh) clock: (lifecycle-get fixture 'clock)
        adapterInstalled: (lifecycle-get fixture 'installed) reportedSuccess: (lifecycle-get fixture 'reported)
        effectStarted: (lifecycle-get fixture 'started) startSafe: #t
        reservationRevision: (lifecycle-get fixture 'reservation-revision)
        reservationEpoch: (lifecycle-get fixture 'reservation-epoch)
        reservationUntil: (lifecycle-get fixture 'reservation-until)
        deliveryStatus: (lifecycle-get fixture 'delivery-status)
        deliveryCalls: (lifecycle-get fixture 'delivery-calls) deliverySafe: #t)))
