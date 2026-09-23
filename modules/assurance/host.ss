;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An application-configured capability for verification. Adapter, clock and
;;; lease are private to the exact issued Host object; neither an editable POO
;;; presentation nor a per-call time argument selects authority.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify
                 poo-flow-revoke-verification!)
        (only-in :poo-flow/lambda-aitia/modules/assurance/evidence-admission
                 assurance-evaluate-evidence-admission
                 assurance-evidence-outcome-bound?
                 assurance-verification-subject
                 assurance-verification-subject-snapshot
                 assurance-support-sealed-under-adapter?))

(export assurance-verification-host assurance-host-verify
        assurance-host-sealed-support? assurance-host-revoke!)

(def issued-hosts (make-hash-table-eq weak-keys: #t))

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

(def (assurance-verification-host identity-value operation clock lease)
  (unless (and (string? identity-value)
               (> (string-length identity-value) 0)
               (procedure? operation) (procedure? clock)
               (exact-integer? lease) (> lease 0))
    (error "invalid assurance verification Host configuration"))
  (let* ((adapter
          (poo-flow-verification-adapter
           identity-value operation assurance-verification-subject-snapshot))
         (host (.o identity: (string-copy identity-value))))
    (hash-put! issued-hosts host
               (vector (string-copy identity-value) adapter clock lease -1))
    host))

;;; An eligible report alone is never an issued seal. The configured operation
;;; must independently return #t over the complete frozen semantic subject.
(def (assurance-host-verify host snapshot obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (eligibility
          (assurance-evaluate-evidence-admission snapshot obligation outcome)))
    (and (.ref eligibility 'eligible?)
         (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (let (now (host-instant entry))
           (poo-flow-verify
            (vector-ref entry 1)
            (assurance-verification-subject
             snapshot obligation evidence outcome)
            now (+ now (vector-ref entry 3)))))))

;;; This checks a Host-issued seal; it does not promote evidence or grant an effect.
(def (assurance-host-sealed-support?
      host relation evidence obligation snapshot outcome receipt)
  (let (entry (required-host-entry host))
    (assurance-support-sealed-under-adapter?
     relation evidence obligation snapshot outcome
     (vector-ref entry 1) receipt (host-instant entry))))

(def (assurance-host-revoke! host receipt)
  (let (entry (required-host-entry host))
    (poo-flow-revoke-verification! (vector-ref entry 1) receipt)))
