;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An application-configured capability for verification. Adapter, clock and
;;; lease are private to the exact issued Host object; neither an editable POO
;;; presentation nor a per-call time argument selects authority.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/list/list find every filter delete-duplicates/hash)
        (only-in :std/hash/misc hash-remove!)
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify
                 poo-flow-verification-valid?
                 poo-flow-revoke-verification!)
        (only-in :poo-flow/lambda-aitia/modules/assurance/types
                 assurance-snapshot? assurance-claim? assurance-obligation?
                 AssuranceRequiredSupport AssessmentRequiredSupport)
        (only-in :poo-flow/lambda-aitia/modules/assurance/funs
                 assurance-snapshot-canonical? assurance-node-canonical)
        (only-in :poo-flow/lambda-aitia/modules/assurance/evidence-admission
                 assurance-evaluate-evidence-admission
                 assurance-evidence-outcome-bound?
                 assurance-verification-subject
                 assurance-snapshot-semantic-digest
                 assurance-verification-subject-snapshot
                 assurance-candidate-support-structural?
                 assurance-support-sealed-under-adapter?))

(export assurance-verification-host assurance-host-verify
        assurance-host-sealed-support? assurance-host-revoke!
        assurance-host-admit assurance-host-admission-current?
        assurance-host-admitted-support?
        assurance-host-required-support
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
    (unless (and (assurance-snapshot? snapshot)
                 (assurance-snapshot-canonical? snapshot))
      (invalidate-host-cut! entry)
      (error "assurance Host snapshot source returned a noncanonical snapshot"))
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

(def (current-admission-snapshot host-state issued)
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
               subject now)
              snapshot))))

(def (assurance-host-admission-current? host admission)
  (let (host-state (required-host-entry host))
    (and (current-admission-snapshot
          host-state (admission-entry host admission)) #t)))

;;; Consume an exact Host admission as one current assurance-edge witness.
;;; This does not close the claim's full support set or authorize a Decision.
(def (assurance-host-admitted-support? host relation admission)
  (let* ((host-state (required-host-entry host))
         (issued (admission-entry host admission)))
    (and issued
         (let (snapshot (current-admission-snapshot host-state issued))
           (and snapshot
                (assurance-candidate-support-structural?
                 relation (vector-ref issued 8) (vector-ref issued 7)
                 snapshot))))))

(def (snapshot-node snapshot identity)
  (find (lambda (node) (equal? (.ref node 'identity) identity))
        (.ref snapshot 'nodes)))

(def (required-support-link? snapshot obligation claim)
  (find (lambda (relation)
          (and (eq? (.ref relation 'plane) 'assurance)
               (eq? (.ref relation 'relation) 'supports)
               (equal? (.ref relation 'source) (.ref obligation 'identity))
               (equal? (.ref relation 'target) (.ref claim 'identity))
               (not (memq (.ref relation 'modality)
                          '(hypothesized counterfactual)))))
        (.ref snapshot 'relations)))

(def (admitted-requirement-blocker host host-state snapshot obligation admissions)
  (let* ((matching
          (filter (lambda (admission)
                    (let (issued (admission-entry host admission))
                      (and issued
                           (equal? (.ref (vector-ref issued 7) 'identity)
                                   (.ref obligation 'identity)))))
                  admissions)))
    (if (null? matching)
      'admission-missing
      (let loop ((remaining matching) (saw-current? #f))
        (if (null? remaining)
          (if saw-current? 'evidence-link-missing 'admission-invalid)
          (let* ((issued (admission-entry host (car remaining)))
                 (current (current-admission-snapshot host-state issued)))
            (if (and current
                     (equal? (assurance-snapshot-semantic-digest current)
                             (assurance-snapshot-semantic-digest snapshot)))
              (if (find (lambda (relation)
                          (assurance-candidate-support-structural?
                           relation (vector-ref issued 8) obligation snapshot))
                        (.ref snapshot 'relations))
                #f
                (loop (cdr remaining) #t))
              (loop (cdr remaining) saw-current?))))))))

(def (required-support-row host host-state snapshot claim-value identity admissions)
  (let* ((obligation (snapshot-node snapshot identity))
         (reason
          (cond
           ((not (and obligation (assurance-obligation? obligation)))
            'obligation-missing)
           ((or (not (equal? (.ref obligation 'claim) (.ref claim-value 'identity)))
                (not (equal? (.ref obligation 'subject) (.ref claim-value 'subject)))
                (not (equal? (.ref obligation 'scope) (.ref claim-value 'scope)))
                (not (equal? (.ref obligation 'snapshot)
                             (.ref snapshot 'identity)))
                (not (equal? (.ref obligation 'snapshot-revision)
                             (.ref snapshot 'revision)))
                (not (equal? (.ref obligation 'snapshot-context-digest)
                             (.ref snapshot 'context-digest)))
                (memq (.ref obligation 'state)
                      '(violated stale conflicted hypothesized counterfactual
                        not-applicable)))
            'obligation-stale)
           ((not (required-support-link? snapshot obligation claim-value))
            'support-link-missing)
           (else
            (admitted-requirement-blocker
             host host-state snapshot obligation admissions)))))
    (poo-flow-check-model
     AssessmentRequiredSupport
     (.o (:: @ (poo-flow-model-prototype AssessmentRequiredSupport))
         obligation: identity supported?: (not reason) blocker: reason))))

;;; Inert, explainable input for a later Decision evaluator. Completion means
;;; only that every declared support requirement has a current Host witness;
;;; it does not resolve policy, validity intervals or Runtime effect authority.
(def (assurance-host-required-support host claim-value admissions)
  (unless (and (assurance-claim? claim-value) (list? admissions))
    (error "invalid required-support inputs"))
  (let* ((host-state (required-host-entry host))
         (snapshot (host-current-snapshot host-state))
         (initial-epoch (vector-ref host-state 8))
         (current-claim (snapshot-node snapshot (.ref claim-value 'identity)))
         (required-identities (.ref claim-value 'support-requirements))
         (rows
          (map (lambda (identity)
                 (required-support-row
                  host host-state snapshot claim-value identity admissions))
               required-identities))
         (global-blockers
          (append
           (if (pair? (.ref snapshot 'conflicts)) '(snapshot-conflicted) '())
           (if (pair? (.ref snapshot 'unresolved)) '(snapshot-unresolved) '())
           (if (and current-claim (assurance-claim? current-claim)
                    (equal? (assurance-node-canonical claim-value)
                            (assurance-node-canonical current-claim))
                    (member (cons (.ref claim-value 'identity)
                                  (.ref claim-value 'revision))
                            (.ref snapshot 'claim-revisions)))
             '() '(claim-not-current))
           (if (null? required-identities) '(no-requirements) '())
           (if (= (length required-identities)
                  (length (delete-duplicates/hash required-identities)))
             '() '(duplicate-requirements))
           (if (pair? (.ref claim-value 'assumptions))
             '(assumptions-unresolved) '())
           (if (pair? (.ref claim-value 'defeaters))
             '(defeaters-unresolved) '())
           (if (memq (.ref claim-value 'state)
                     '(violated stale conflicted hypothesized counterfactual
                       not-applicable))
             '(claim-state-blocked) '())
           (if (find (lambda (node)
                       (and (memq (.ref node 'kind)
                                  '(counterexample finding))
                            (equal? (.ref node 'challenges)
                                    (.ref claim-value 'identity))))
                     (.ref snapshot 'nodes))
             '(challenge-unresolved) '())))
         (final-snapshot (host-current-snapshot host-state))
         (final-blockers
          (append global-blockers
                  (if (and (= initial-epoch (vector-ref host-state 8))
                           (equal?
                            (assurance-snapshot-semantic-digest snapshot)
                            (assurance-snapshot-semantic-digest final-snapshot)))
                    '() '(source-changed)))))
    (poo-flow-check-model
     AssuranceRequiredSupport
     (.o (:: @ (poo-flow-model-prototype AssuranceRequiredSupport))
         schema: "lambda-aitia.required-support"
         claim: (.ref claim-value 'identity)
         snapshot-digest: (.ref snapshot 'digest)
         requirements: rows blockers: final-blockers
         complete?: (and (null? final-blockers)
                         (pair? rows)
                         (every (lambda (row) (.ref row 'supported?)) rows))
         release-authorized?: #f))))

(def (assurance-host-revoke-admission! host admission)
  (required-host-entry host)
  (let (issued (admission-entry host admission))
    (unless issued (error "unissued or modified assurance admission"))
    (assurance-host-revoke! host (vector-ref issued 1))
    (hash-remove! issued-admissions admission)))
