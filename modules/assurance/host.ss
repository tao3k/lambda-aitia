;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An application-configured capability for verification. Adapter, clock and
;;; lease are private to the exact issued Host object; neither an editable POO
;;; presentation nor a per-call time argument selects authority.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/hash/misc hash-remove!)
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify
                 poo-flow-verification-valid?
                 poo-flow-revoke-verification!)
        (only-in :poo-flow/lambda-aitia/modules/assurance/types
                 assurance-snapshot?)
        (only-in :poo-flow/lambda-aitia/modules/assurance/evidence-admission
                 assurance-evaluate-evidence-admission
                 assurance-evidence-outcome-bound?
                 assurance-verification-subject
                 assurance-snapshot-semantic-digest
                 assurance-verification-subject-snapshot
                 assurance-support-sealed-under-adapter?))

(export assurance-verification-host assurance-host-verify
        assurance-host-sealed-support? assurance-host-revoke!
        assurance-host-admit assurance-host-admission-current?
        assurance-host-revoke-admission!)

(def issued-hosts (make-hash-table-eq weak-keys: #t))
(def issued-host-receipts (make-hash-table-eq weak-keys: #t))
(def issued-admissions (make-hash-table-eq weak-keys: #t))

(def (host-entry host)
  (let (entry (hash-get issued-hosts host))
    (and entry (object? host) (.slot? host 'identity)
         (equal? (.ref host 'identity) (vector-ref entry 0))
         entry)))

(def (required-host-entry host)
  (or (host-entry host)
      (error "unissued or modified assurance verification Host")))

(def (host-instant entry)
  (let (now ((vector-ref entry 2)))
    (unless (and (exact-integer? now) (>= now 0))
      (error "assurance Host clock must return a nonnegative instant"))
    (when (< now (vector-ref entry 4))
      (error "assurance Host clock moved backwards"))
    (vector-set! entry 4 now)
    now))

(def (invalidate-host-cut! entry)
  ;; A weak receipt index avoids retaining every old seal for the Host's life.
  ;; The epoch blocks all prior seals at this Host even if the old cut returns.
  (vector-set! entry 8 (+ (vector-ref entry 8) 1)))

(def (host-current-snapshot entry)
  (let (snapshot ((vector-ref entry 5)))
    (unless (assurance-snapshot? snapshot)
      (invalidate-host-cut! entry)
      (error "assurance Host snapshot source returned an invalid snapshot"))
    (let ((current-digest (assurance-snapshot-semantic-digest snapshot))
          (previous-digest (vector-ref entry 7)))
      (when (and previous-digest
                 (not (equal? previous-digest current-digest)))
        (invalidate-host-cut! entry))
      (vector-set! entry 7 (string-copy current-digest)))
    snapshot))

(def (host-snapshot-current? entry snapshot obligation evidence outcome)
  (equal?
   (assurance-verification-subject-snapshot
    (assurance-verification-subject snapshot obligation evidence outcome))
   (assurance-verification-subject-snapshot
    (assurance-verification-subject
     (host-current-snapshot entry) obligation evidence outcome))))

(def (assurance-verification-host
      identity-value operation clock lease snapshot-source)
  (unless (and (string? identity-value)
               (> (string-length identity-value) 0)
               (procedure? operation) (procedure? clock)
               (exact-integer? lease) (> lease 0)
               (procedure? snapshot-source))
    (error "invalid assurance verification Host configuration"))
  (let* ((adapter
          (poo-flow-verification-adapter
           identity-value operation assurance-verification-subject-snapshot))
         (host (.o identity: (string-copy identity-value))))
    (hash-put! issued-hosts host
               (vector (string-copy identity-value) adapter clock lease -1
                       snapshot-source 0 #f 0))
    host))

;;; An eligible report alone is never an issued seal. The configured operation
;;; must independently return #t over the complete frozen semantic subject.
(def (assurance-host-verify host snapshot obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (eligibility
          (assurance-evaluate-evidence-admission snapshot obligation outcome)))
    (and (.ref eligibility 'eligible?)
         (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (host-snapshot-current? entry snapshot obligation evidence outcome)
         (let (now (host-instant entry))
           (let (receipt
                 (poo-flow-verify
                  (vector-ref entry 1)
                  (assurance-verification-subject
                   snapshot obligation evidence outcome)
                  now (+ now (vector-ref entry 3))))
             (when receipt
               (hash-put! issued-host-receipts receipt
                          (vector host (vector-ref entry 8))))
             receipt)))))

;;; This checks a Host-issued seal; it does not promote evidence or grant an effect.
(def (assurance-host-sealed-support?
      host relation evidence obligation snapshot outcome receipt)
  (let (entry (required-host-entry host))
    (let (issued (hash-get issued-host-receipts receipt))
      (and issued (eq? host (vector-ref issued 0))
           (host-snapshot-current? entry snapshot obligation evidence outcome)
           (= (vector-ref issued 1) (vector-ref entry 8))
         (assurance-support-sealed-under-adapter?
          relation evidence obligation snapshot outcome
          (vector-ref entry 1) receipt (host-instant entry))))))

(def (assurance-host-revoke! host receipt)
  (let* ((entry (required-host-entry host))
         (issued (hash-get issued-host-receipts receipt)))
    (unless (and issued (eq? host (vector-ref issued 0)))
      (error "receipt was not issued by this assurance Host"))
    (hash-remove! issued-host-receipts receipt)
    (poo-flow-revoke-verification! (vector-ref entry 1) receipt)))

;;; Admission is a separate Host-issued capability over the candidate cut.
;;; It does not mutate AssuranceEvidence or the snapshot that the outcome names.
(def (assurance-host-admit host obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (snapshot (host-current-snapshot entry)))
    (and (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (eq? (.ref evidence 'admission-state) 'candidate)
         (let (receipt
               (assurance-host-verify
                host snapshot obligation evidence outcome))
           (and receipt
                (if (host-snapshot-current?
                     entry snapshot obligation evidence outcome)
                  (let* ((next (+ (vector-ref entry 6) 1))
                         (identity-value
                          (string-append (vector-ref entry 0) "/admission/"
                                         (number->string next)))
                         (subject-digest-value
                          (assurance-verification-subject-snapshot
                           (assurance-verification-subject
                            snapshot obligation evidence outcome)))
                         (issued-at-value (.ref receipt 'issued-at))
                         (expires-at-value (.ref receipt 'expires-at))
                         (admission
                          (.o identity: identity-value
                              issuer: (vector-ref entry 0)
                              issued-at: issued-at-value
                              expires-at: expires-at-value
                              subject-digest: subject-digest-value)))
                    (vector-set! entry 6 next)
                    (hash-put! issued-admissions admission
                               (vector host receipt identity-value
                                       (vector-ref entry 0) issued-at-value
                                       expires-at-value subject-digest-value
                                       obligation evidence outcome
                                       (vector-ref entry 8)))
                    admission)
                  (begin
                    (assurance-host-revoke! host receipt)
                    #f)))))))

(def (admission-entry host admission)
  (let (entry (hash-get issued-admissions admission))
    (and entry (eq? host (vector-ref entry 0))
         (object? admission)
         (.slot? admission 'identity) (.slot? admission 'issuer)
         (.slot? admission 'issued-at) (.slot? admission 'expires-at)
         (.slot? admission 'subject-digest)
         (equal? (.ref admission 'identity) (vector-ref entry 2))
         (equal? (.ref admission 'issuer) (vector-ref entry 3))
         (equal? (.ref admission 'issued-at) (vector-ref entry 4))
         (equal? (.ref admission 'expires-at) (vector-ref entry 5))
         (equal? (.ref admission 'subject-digest) (vector-ref entry 6))
         entry)))

(def (assurance-host-admission-current? host admission)
  (let* ((host-state (required-host-entry host))
         (issued (admission-entry host admission)))
    (and issued
         (let* ((now (host-instant host-state))
                (snapshot (host-current-snapshot host-state))
                (obligation (vector-ref issued 7))
                (evidence (vector-ref issued 8))
                (outcome (vector-ref issued 9))
                (eligibility
                 (assurance-evaluate-evidence-admission
                  snapshot obligation outcome))
                (subject
                 (assurance-verification-subject
                  snapshot obligation evidence outcome)))
           (and (= (vector-ref issued 10) (vector-ref host-state 8))
                (<= (vector-ref issued 4) now)
                (< now (vector-ref issued 5))
                (.ref eligibility 'eligible?)
                (assurance-evidence-outcome-bound?
                 snapshot evidence outcome)
                (eq? (.ref evidence 'admission-state) 'candidate)
                (equal? (assurance-verification-subject-snapshot subject)
                        (vector-ref issued 6))
                (poo-flow-verification-valid?
                 (vector-ref host-state 1) (vector-ref issued 1)
                 subject now))))))

(def (assurance-host-revoke-admission! host admission)
  (required-host-entry host)
  (let (issued (admission-entry host admission))
    (unless issued (error "unissued or modified assurance admission"))
    (assurance-host-revoke! host (vector-ref issued 1))
    (hash-remove! issued-admissions admission)))
