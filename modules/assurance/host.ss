;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An application-configured capability for verification. Adapter, clock and
;;; lease are private to the exact issued Host object; neither an editable POO
;;; presentation nor a per-call time argument selects authority.
(import (only-in :clan/poo/object .o .ref .slot? .alist object?)
        (only-in :std/list/list find every filter delete-duplicates/hash)
        (only-in :std/hash/misc hash-remove!)
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify
                 poo-flow-verification-valid?
                 poo-flow-revoke-verification!)
        (only-in :poo-flow/src/feature-system/source-lock-feature
                 source-lock-payload-digest)
        (only-in :poo-flow/src/modules/authorization/providers/cedar/interface
                 poo-flow-cedar-runtime-handoff?
                 poo-flow-cedar-authorization-request
                 poo-flow-cedar-authorization-request?)
        (only-in :poo-flow/lambda-aitia/modules/assurance/types
                 assurance-snapshot? assurance-artifact? assurance-claim?
                 assurance-obligation?
                 assurance-decision? assurance-decision-preflight?
                 AssuranceRequiredSupport AssessmentRequiredSupport
                 AssuranceDecisionPreflight)
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
        assurance-host-source-current?
        assurance-host-admitted-support?
        assurance-host-required-support
        assurance-host-preflight-decision
        assurance-host-decision-preflight-current?
        assurance-host-cedar-request assurance-host-cedar-request-current?
        assurance-host-revoke-decision-preflight!
        assurance-host-revoke-admission!)

(def issued-hosts (make-hash-table-eq weak-keys: #t))
(def issued-host-receipts (make-hash-table-eq weak-keys: #t))
(def issued-admissions (make-hash-table-eq weak-keys: #t))
(def issued-decision-preflights (make-hash-table-eq weak-keys: #t))
(def issued-cedar-requests (make-hash-table-eq weak-keys: #t))

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
      identity-value operation clock lease snapshot-source
      source-reader: (source-reader #f))
  (unless (and (string? identity-value)
               (> (string-length identity-value) 0)
               (procedure? operation) (procedure? clock)
               (exact-integer? lease) (> lease 0)
               (procedure? snapshot-source)
               (or (not source-reader) (procedure? source-reader)))
    (error "invalid assurance verification Host configuration"))
  (let* ((adapter
          (poo-flow-verification-adapter
           identity-value operation assurance-verification-subject-snapshot))
         (host (.o identity: (string-copy identity-value))))
    (hash-put! issued-hosts host
               (vector (string-copy identity-value) adapter clock lease -1
                       snapshot-source 0 #f 0 source-reader))
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
         (host-outcome-inputs-current? host snapshot outcome)
         (let (now (host-instant entry))
           (let (receipt
                 (poo-flow-verify
                  (vector-ref entry 1)
                  (assurance-verification-subject
                   snapshot obligation evidence outcome)
                  now (+ now (vector-ref entry 3))))
             (and receipt
                  (if (host-outcome-inputs-current? host snapshot outcome)
                    (begin
                      (hash-put! issued-host-receipts receipt
                                 (vector host (vector-ref entry 8)))
                      receipt)
                    (begin
                      (poo-flow-revoke-verification! (vector-ref entry 1)
                                                     receipt)
                      #f))))))))

;;; This checks a Host-issued seal; it does not promote evidence or grant an effect.
(def (assurance-host-sealed-support?
      host relation evidence obligation snapshot outcome receipt)
  (let (entry (required-host-entry host))
    (let (issued (hash-get issued-host-receipts receipt))
      (and issued (eq? host (vector-ref issued 0))
           (host-snapshot-current? entry snapshot obligation evidence outcome)
           (host-outcome-inputs-current? host snapshot outcome)
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
              (host-outcome-inputs-current?
               (vector-ref issued 0) snapshot outcome)
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

;;; Source bytes come only from the Host's configured reader. This is a
;;; conditional application trust boundary, not a claim about Git provenance
;;; or the verifier's actual process inputs. Re-read and recheck the cut after
;;; materialization so a moving snapshot cannot qualify an old source.
(def (assurance-host-source-current? host snapshot artifact)
  (let* ((entry (required-host-entry host))
         (reader (vector-ref entry 9)))
    (and reader
         (assurance-snapshot? snapshot)
         (assurance-snapshot-canonical? snapshot)
         (assurance-artifact? artifact)
         (let* ((current (host-current-snapshot entry))
                (expected-cut (assurance-snapshot-semantic-digest snapshot))
                (current-artifact
                 (snapshot-node current (.ref artifact 'identity)))
                (revision (assoc (.ref artifact 'identity)
                                 (.ref current 'source-revisions))))
           (and (equal? expected-cut
                        (assurance-snapshot-semantic-digest current))
                current-artifact
                (assurance-artifact? current-artifact)
                (equal? (assurance-node-canonical current-artifact)
                        (assurance-node-canonical artifact))
                revision
                (equal? (cdr revision) (.ref artifact 'revision))
                (eq? (.ref artifact 'state) 'supported)
                (let (payload (reader (.ref artifact 'identity)))
                  (let (matches?
                        (and (or (string? payload) (u8vector? payload))
                             (equal? (source-lock-payload-digest payload)
                                     (.ref artifact 'content-digest))))
                    (unless matches? (invalidate-host-cut! entry))
                    (and matches?
                         (equal? expected-cut
                                 (assurance-snapshot-semantic-digest
                                  (host-current-snapshot entry)))))))))))

;;; An optional Host source reader strengthens issuance and currentness for
;;; every declared verifier input. With no configured reader the old Host
;;; remains a verification Host, but it cannot claim source-byte checking.
(def (host-outcome-inputs-current? host snapshot outcome)
  (let (entry (required-host-entry host))
    (or (not (vector-ref entry 9))
        (every (lambda (input)
                 (let (artifact (snapshot-node snapshot
                                                (.ref input 'identity)))
                   (and artifact
                        (assurance-host-source-current?
                         host snapshot artifact))))
               (.ref outcome 'inputs)))))

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

(def (decision-depends-on-claim? snapshot decision-value claim-value)
  (find (lambda (relation)
          (and (eq? (.ref relation 'plane) 'structural)
               (eq? (.ref relation 'relation) 'depends-on)
               (equal? (.ref relation 'source)
                       (.ref decision-value 'identity))
               (equal? (.ref relation 'target)
                       (.ref claim-value 'identity))
               (not (memq (.ref relation 'modality)
                          '(hypothesized counterfactual)))))
        (.ref snapshot 'relations)))

(def (decision-preflight-bound? snapshot decision-value claim-value)
  (and (assurance-decision? decision-value)
       (assurance-claim? claim-value)
       (let ((current-decision
              (snapshot-node snapshot (.ref decision-value 'identity)))
             (current-claim
              (snapshot-node snapshot (.ref claim-value 'identity))))
         (and current-decision (assurance-decision? current-decision)
              current-claim (assurance-claim? current-claim)
              (equal? (assurance-node-canonical current-decision)
                      (assurance-node-canonical decision-value))
              (equal? (assurance-node-canonical current-claim)
                      (assurance-node-canonical claim-value))))
       (eq? (.ref decision-value 'outcome) 'unknown)
       (eq? (.ref decision-value 'state) 'unknown)
       (equal? (.ref decision-value 'subject)
               (.ref claim-value 'subject))
       (equal? (.ref decision-value 'snapshot)
               (.ref snapshot 'identity))
       (equal? (.ref decision-value 'policy)
               (.ref snapshot 'policy-identity))
       (decision-depends-on-claim? snapshot decision-value claim-value)))

(def (same-host-cut? host-state snapshot-value epoch-value)
  (and (= epoch-value (vector-ref host-state 8))
       (equal? (assurance-snapshot-semantic-digest snapshot-value)
               (assurance-snapshot-semantic-digest
                (host-current-snapshot host-state)))
       (= epoch-value (vector-ref host-state 8))))

;;; This capability attests a currently bound *undecided* Decision candidate.
;;; It cannot be projected as Cedar permit or Runtime effect authorization.
(def (assurance-host-preflight-decision
      host decision-value claim-value admissions)
  (unless (list? admissions)
    (error "Decision preflight requires an admission list"))
  (let* ((host-state (required-host-entry host))
         (snapshot-value (host-current-snapshot host-state))
         (epoch-value (vector-ref host-state 8)))
    (and (decision-preflight-bound?
          snapshot-value decision-value claim-value)
         (.ref (assurance-host-required-support
                host claim-value admissions)
               'complete?)
         (same-host-cut? host-state snapshot-value epoch-value)
         (let* ((next (+ (vector-ref host-state 6) 1))
                (identity-value
                 (string-append (vector-ref host-state 0) "/decision-preflight/"
                                (number->string next)))
                (issuer-value (vector-ref host-state 0))
                (decision-identity-value (.ref decision-value 'identity))
                (claim-identity-value (.ref claim-value 'identity))
                (snapshot-digest-value (.ref snapshot-value 'digest))
                (semantic-digest-value
                 (assurance-snapshot-semantic-digest snapshot-value))
                (preflight
                 (poo-flow-check-model
                  AssuranceDecisionPreflight
                  (.o (:: @ (poo-flow-model-prototype
                             AssuranceDecisionPreflight))
                      schema: "lambda-aitia.decision-preflight"
                      identity: identity-value issuer: issuer-value
                      decision: decision-identity-value
                      claim: claim-identity-value
                      snapshot-digest: snapshot-digest-value
                      release-authorized?: #f))))
           (vector-set! host-state 6 next)
           (hash-put! issued-decision-preflights preflight
                      (vector host identity-value issuer-value
                              decision-identity-value claim-identity-value
                              snapshot-digest-value semantic-digest-value
                              epoch-value decision-value claim-value
                              admissions))
           preflight))))

(def (decision-preflight-entry host preflight)
  (let (issued (hash-get issued-decision-preflights preflight))
    (and issued (eq? host (vector-ref issued 0))
         (assurance-decision-preflight? preflight)
         (equal? (.ref preflight 'identity) (vector-ref issued 1))
         (equal? (.ref preflight 'issuer) (vector-ref issued 2))
         (equal? (.ref preflight 'decision) (vector-ref issued 3))
         (equal? (.ref preflight 'claim) (vector-ref issued 4))
         (equal? (.ref preflight 'snapshot-digest) (vector-ref issued 5))
         issued)))

(def (assurance-host-decision-preflight-current? host preflight)
  (let* ((host-state (required-host-entry host))
         (issued (decision-preflight-entry host preflight)))
    (and issued
         (= (vector-ref issued 7) (vector-ref host-state 8))
         (let (snapshot-value (host-current-snapshot host-state))
           (and (= (vector-ref issued 7) (vector-ref host-state 8))
                (equal? (.ref snapshot-value 'digest)
                        (vector-ref issued 5))
                (equal? (assurance-snapshot-semantic-digest snapshot-value)
                        (vector-ref issued 6))
                (decision-preflight-bound?
                 snapshot-value (vector-ref issued 8) (vector-ref issued 9))
                (.ref (assurance-host-required-support
                       host (vector-ref issued 9) (vector-ref issued 10))
                      'complete?)
                (same-host-cut?
                 host-state snapshot-value (vector-ref issued 7)))))))

;;; Project a current preflight into POO Flow's inert Cedar request family.
;;; The request is editable input, not a Host seal, Cedar outcome or effect grant.
;;; The Runtime Host must independently validate the current source cut at use.
(def (cedar-request-fingerprint request)
  (list (.ref request 'principal) (.ref request 'action)
        (.ref request 'resource) (.alist (.ref request 'context))
        (.ref request 'intent) (.alist (.ref request 'handoff))))

(def (assurance-host-cedar-request host preflight action-value intent-value
                                    handoff-value)
  (unless (poo-flow-cedar-runtime-handoff? handoff-value)
    (error "Decision Cedar projection requires a POO Flow runtime handoff"))
  (let* ((host-state (required-host-entry host))
         (issued (decision-preflight-entry host preflight)))
    (and issued
         (assurance-host-decision-preflight-current? host preflight)
         (let* ((snapshot-value (host-current-snapshot host-state))
                (epoch-value (vector-ref host-state 8))
                (decision-value (vector-ref issued 8))
                (claim-value (vector-ref issued 9))
                (context-value
                 (.o aitia_schema: "lambda-aitia.cedar-preflight.v1"
                     poo_flow_preflight_only: #t
                     aitia_preflight: (vector-ref issued 1)
                     aitia_decision: (vector-ref issued 3)
                     aitia_claim: (vector-ref issued 4)
                     aitia_snapshot_digest: (vector-ref issued 5)
                     aitia_snapshot_semantic_digest: (vector-ref issued 6)
                     aitia_policy: (.ref decision-value 'policy)
                     aitia_policy_revision: (.ref snapshot-value 'policy-revision)
                     aitia_preflight_only: #t))
                (request
                 (poo-flow-cedar-authorization-request
                  (.ref decision-value 'authority) action-value
                  (.ref claim-value 'subject) context-value intent-value
                  handoff-value)))
           (and (= epoch-value (vector-ref issued 7))
                (same-host-cut? host-state snapshot-value epoch-value)
                (assurance-host-decision-preflight-current? host preflight)
                (begin
                  (hash-put! issued-cedar-requests request
                             (vector host preflight epoch-value
                                     (cedar-request-fingerprint request)))
                  request))))))

;;; Source-owned use-time check for the exact Host-issued request. This does
;;; not evaluate Cedar or permit an effect. A future Runtime integration must
;;; call it at use and retain authorization and effect-handoff ownership.
(def (assurance-host-cedar-request-current? host request)
  (let* ((host-state (required-host-entry host))
         (issued (hash-get issued-cedar-requests request)))
    (and issued
         (eq? host (vector-ref issued 0))
         (poo-flow-cedar-authorization-request? request)
         (object? (.ref request 'context))
         (poo-flow-cedar-runtime-handoff? (.ref request 'handoff))
         (= (vector-ref issued 2) (vector-ref host-state 8))
         (equal? (cedar-request-fingerprint request) (vector-ref issued 3))
         (assurance-host-decision-preflight-current?
          host (vector-ref issued 1))
         (= (vector-ref issued 2) (vector-ref host-state 8)))))

(def (assurance-host-revoke-decision-preflight! host preflight)
  (required-host-entry host)
  (unless (decision-preflight-entry host preflight)
    (error "unissued or modified assurance Decision preflight"))
  (hash-remove! issued-decision-preflights preflight))

(def (assurance-host-revoke-admission! host admission)
  (required-host-entry host)
  (let (issued (admission-entry host admission))
    (unless issued (error "unissued or modified assurance admission"))
    (assurance-host-revoke! host (vector-ref issued 1))
    (hash-remove! issued-admissions admission)))
