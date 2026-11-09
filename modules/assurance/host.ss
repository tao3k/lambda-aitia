;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An application-configured capability for verification. Adapter, clock and
;;; lease are private to the exact issued Host object; neither an editable POO
;;; presentation nor a per-call time argument selects authority.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/crypto/random random-bytes)
        (only-in :std/list/list find every filter filter-map delete-duplicates/hash)
        (only-in :std/hash/misc hash-remove!)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/contribution/verification
                 yuanxu-verification-adapter yuanxu-verify
                 yuanxu-verification-valid?
                 yuanxu-revoke-verification!)
        (only-in :yuanxu/module-system/feature/source-lock-feature
                 source-lock-payload-digest)
        (only-in "types.ss"
                 assurance-snapshot? assurance-artifact? assurance-claim?
                 assurance-obligation? assurance-assumption? assurance-evidence? assurance-digest?
                 assurance-decision? assurance-decision-preflight?
                 AssuranceRequiredSupport AssessmentRequiredSupport AssuranceSupportWitness
                 AssuranceAssumptionAssessment AssuranceChallengeAssessment
                 AssuranceResidualDisposition AssuranceDecisionPreflight)
        (only-in "func.ss"
                 assurance-snapshot-canonical? assurance-node-canonical
                 assurance-canonical-digest)
        (only-in "evidence-admission.ss"
                 assurance-evaluate-evidence-admission
                 assurance-verifier-outcome-digest
                 assurance-evidence-outcome-bound?
                 assurance-verification-subject
                 assurance-snapshot-semantic-digest
                 assurance-verification-subject-snapshot
                 assurance-candidate-support-structural?
                 assurance-support-sealed-under-adapter?))

(export assurance-verification-host assurance-host-verify
        assurance-host-sealed-support? assurance-host-revoke!
        assurance-host-admit assurance-host-admit-verified
        assurance-host-verification-current? assurance-host-admission-current?
        assurance-host-source-current?
        assurance-host-admitted-support?
        assurance-host-required-support
        assurance-host-preflight-decision
        assurance-host-decision-preflight-current?
        assurance-host-current-preflight-binding assurance-host-governance-source
        assurance-host-revoke-decision-preflight!
        assurance-host-revoke-admission!)

(def issued-hosts (make-hash-table-eq weak-keys: #t))
(def issued-host-receipts (make-hash-table-eq weak-keys: #t))
(def issued-admissions (make-hash-table-eq weak-keys: #t))
(def issued-decision-preflights (make-hash-table-eq weak-keys: #t))

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
      source-reader: (source-reader #f)
      execution-reader: (execution-reader #f)
      governance-reader: (governance-reader #f))
  (unless (and (string? identity-value)
               (> (string-length identity-value) 0)
               (procedure? operation) (procedure? clock)
               (exact-integer? lease) (> lease 0)
               (procedure? snapshot-source)
               (or (not source-reader) (procedure? source-reader))
               (or (not execution-reader)
                   (and source-reader (procedure? execution-reader)))
               (or (not governance-reader) (procedure? governance-reader)))
    (error "invalid assurance verification Host configuration"))
  (let* ((host (.o identity: (string-copy identity-value)))
         (adapter
          (yuanxu-verification-adapter
           identity-value
           (lambda (subject now until)
             (if source-reader
               (let (inputs
                     (host-materialized-inputs
                      host (.ref subject 'snapshot) (.ref subject 'outcome)))
                 (and inputs
                      (let (expected
                            (map (lambda (input)
                                   (vector (string-copy (.ref input 'identity))
                                           (string-copy (.ref input 'revision))
                                           (string-copy (.ref input 'digest))))
                                 inputs))
                        (and (eq? (operation subject now until inputs) #t)
                             (host-handed-inputs-current? inputs expected)))))
               (operation subject now until)))
           assurance-verification-subject-snapshot)))
    (hash-put! issued-hosts host
               (vector (string-copy identity-value) adapter clock lease -1
                       snapshot-source 0 #f 0 source-reader execution-reader governance-reader))
    host))

;;; A configured reader returns the owner-recorded digest of an attempt, or
;;; #f if custody is absent or withdrawn. It must not derive it from a request.
(def (host-execution-current? entry outcome outcome-digest)
  (let (reader (vector-ref entry 10))
    (or (not reader)
        (equal? outcome-digest (reader (.ref outcome 'identity))))))

(def (host-seal-execution-current? entry receipt outcome)
  (let (issued (hash-get issued-host-receipts receipt))
    (and issued
         (or (not (vector-ref entry 10))
             (let (digest-value (assurance-verifier-outcome-digest outcome))
               (and (equal? digest-value (vector-ref issued 2))
                    (or (host-execution-current? entry outcome digest-value)
                        (begin
                          (hash-remove! issued-host-receipts receipt)
                          (yuanxu-revoke-verification! (vector-ref entry 1) receipt)
                          #f))))))))

;;; An eligible report alone is never an issued seal. The configured operation
;;; must independently return #t over the complete frozen semantic subject.
(def (assurance-host-verify host snapshot obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (eligibility
          (assurance-evaluate-evidence-admission snapshot obligation outcome))
         (execution-digest
          (and (vector-ref entry 10) (.ref eligibility 'eligible?)
               (assurance-verifier-outcome-digest outcome))))
    (and (.ref eligibility 'eligible?)
         (host-execution-current? entry outcome execution-digest)
         (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (host-snapshot-current? entry snapshot obligation evidence outcome)
         (host-outcome-inputs-current? host snapshot outcome)
         (let (now (host-instant entry))
           (let (receipt
                 (yuanxu-verify
                  (vector-ref entry 1)
                  (assurance-verification-subject
                   snapshot obligation evidence outcome)
                  now (+ now (vector-ref entry 3))))
             (and receipt
                  (if (and (host-execution-current? entry outcome execution-digest)
                           (host-outcome-inputs-current? host snapshot outcome))
                    (begin
                      (hash-put! issued-host-receipts receipt
                                 (vector host (vector-ref entry 8) execution-digest))
                      receipt)
                    (begin
                      (yuanxu-revoke-verification! (vector-ref entry 1)
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
           (host-seal-execution-current? entry receipt outcome)
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
    (yuanxu-revoke-verification! (vector-ref entry 1) receipt)))

;;; Admission is a separate Host-issued capability over the candidate cut.
;;; It does not mutate AssuranceEvidence or the snapshot that the outcome names.
(def (assurance-host-admit host obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (snapshot (host-current-snapshot entry)))
    (and (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (eq? (.ref evidence 'admission-state) 'candidate)
         (let (receipt (assurance-host-verify host snapshot obligation evidence outcome))
           (and receipt
                (assurance-host-admit-verified host obligation evidence outcome receipt))))))

;;; Verify and Admit can be separate lifecycle stages. Admission consumes an
;;; exact current Host-issued seal; it must not execute a verifier again or
;;; refresh an expired seal from a submitted success report.
(def (assurance-host-verification-current? host receipt snapshot obligation evidence outcome)
  (let* ((entry (required-host-entry host))
         (issued (hash-get issued-host-receipts receipt)))
    (and issued (eq? host (vector-ref issued 0))
         (host-snapshot-current? entry snapshot obligation evidence outcome)
         (= (vector-ref issued 1) (vector-ref entry 8))
         (host-outcome-inputs-current? host snapshot outcome)
         (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (host-seal-execution-current? entry receipt outcome)
         (yuanxu-verification-valid?
          (vector-ref entry 1) receipt
          (assurance-verification-subject snapshot obligation evidence outcome)
          (host-instant entry))
         (= (vector-ref issued 1) (vector-ref entry 8)))))

(def (assurance-host-admit-verified host obligation evidence outcome receipt)
  (let* ((entry (required-host-entry host))
         (snapshot (host-current-snapshot entry)))
    (and (assurance-evidence-outcome-bound? snapshot evidence outcome)
         (eq? (.ref evidence 'admission-state) 'candidate)
         (assurance-host-verification-current?
          host receipt snapshot obligation evidence outcome)
         (if (host-snapshot-current? entry snapshot obligation evidence outcome)
           (let* ((next (+ (vector-ref entry 6) 1))
                  (identity-value
                   (string-append (vector-ref entry 0) "/admission/" (number->string next)))
                  (subject-digest-value
                   (assurance-verification-subject-snapshot
                    (assurance-verification-subject snapshot obligation evidence outcome)))
                  (issued-at-value (.ref receipt 'issued-at))
                  (expires-at-value (.ref receipt 'expires-at))
                  (admission
                   (.o identity: identity-value issuer: (vector-ref entry 0)
                       issued-at: issued-at-value expires-at: expires-at-value
                       subject-digest: subject-digest-value)))
             (vector-set! entry 6 next)
             (hash-put! issued-admissions admission
                        (vector host receipt identity-value (vector-ref entry 0)
                                issued-at-value expires-at-value subject-digest-value
                                obligation evidence outcome (vector-ref entry 8)))
             admission)
           (begin (assurance-host-revoke! host receipt) #f)))))

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
              (host-seal-execution-current? host-state (vector-ref issued 1) outcome)
              (yuanxu-verification-valid?
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
(def (host-source-payload host snapshot artifact)
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
                                  (host-current-snapshot entry)))
                         payload))))))))

(def (assurance-host-source-current? host snapshot artifact)
  (and (host-source-payload host snapshot artifact) #t))

;;; The configured operation receives these POO values as its fourth argument
;;; when source-reader: is present. The Host, not the operation, selects and
;;; validates the bytes. It rehashes the handed values after the operation.
(def (host-materialized-inputs host snapshot outcome)
  (let loop ((remaining (.ref outcome 'inputs)) (collected '()))
    (if (null? remaining)
      (reverse collected)
      (let* ((input (car remaining))
             (artifact (snapshot-node snapshot (.ref input 'identity)))
             (payload-value (and artifact
                                 (host-source-payload host snapshot artifact)))
             (handed-payload
              (and payload-value
                   (if (string? payload-value)
                     (string-copy payload-value)
                     (u8vector-copy payload-value)))))
        (and payload-value
             (loop (cdr remaining)
                   (cons (.o identity: (.ref input 'identity)
                             revision: (.ref input 'revision)
                             digest: (.ref input 'digest)
                             payload: handed-payload)
                         collected)))))))

(def (host-handed-inputs-current? inputs expected)
  (let loop ((remaining inputs) (original expected))
    (cond
     ((null? remaining) (null? original))
     ((null? original) #f)
     (else
      (let ((input (car remaining)) (fields (car original)))
        (and (equal? (.ref input 'identity) (vector-ref fields 0))
             (equal? (.ref input 'revision) (vector-ref fields 1))
             (equal? (.ref input 'digest) (vector-ref fields 2))
             (let (payload-value (.ref input 'payload))
               (and (or (string? payload-value) (u8vector? payload-value))
                    (equal? (source-lock-payload-digest payload-value)
                            (vector-ref fields 2))))
             (loop (cdr remaining) (cdr original))))))))

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

(def (admitted-requirement-support host host-state snapshot obligation-value admissions
                                   authority: (authority #f) output-digest: (output-digest #f))
  (let* ((matching
          (filter (lambda (admission)
                    (let (issued (admission-entry host admission))
                      (and issued
                           (equal? (.ref (vector-ref issued 7) 'identity)
                                   (.ref obligation-value 'identity))
                           (or (not authority)
                               (equal? authority
                                       (.ref (vector-ref issued 9) 'accountable-authority)))
                           (or (not output-digest)
                               (equal? output-digest (.ref (vector-ref issued 9) 'output-digest))))))
                  admissions)))
    (if (null? matching)
      (values 'admission-missing #f)
      (let loop ((remaining matching) (saw-current? #f))
        (if (null? remaining)
          (values (if saw-current? 'evidence-link-missing 'admission-invalid) #f)
          (let* ((issued (admission-entry host (car remaining)))
                 (current (current-admission-snapshot host-state issued)))
            (if (and current
                     (equal? (assurance-snapshot-semantic-digest current)
                             (assurance-snapshot-semantic-digest snapshot)))
              (let* ((evidence-value (vector-ref issued 8))
                     (verifier-result (vector-ref issued 9))
                     (support-relation
                      (find (lambda (candidate)
                              (assurance-candidate-support-structural?
                               candidate evidence-value obligation-value snapshot))
                            (.ref snapshot 'relations))))
                (if support-relation
                  (values #f
                          (validate
                           AssuranceSupportWitness
                           (.o (:: @ (.ref AssuranceSupportWitness 'proto))
                               obligation: (.ref obligation-value 'identity)
                               evidence: (.ref evidence-value 'identity)
                               admission: (string-copy (vector-ref issued 2))
                               relation: (.ref support-relation 'identity)
                               outcome: (.ref verifier-result 'identity)
                               outcome-digest: (assurance-verifier-outcome-digest verifier-result)
                               scope: (.ref obligation-value 'scope)
                               declared-evidence-kind: (.ref obligation-value 'evidence-kind)
                               capability: (.ref obligation-value 'capability)
                               producer: (.ref evidence-value 'producer)
                               tool: (.ref evidence-value 'tool)
                               tool-version: (.ref evidence-value 'tool-version)
                               input-artifacts: (.ref evidence-value 'input-artifacts)
                               expires-at: (vector-ref issued 5))))
                  (loop (cdr remaining) #t)))
              (loop (cdr remaining) saw-current?))))))))

(def (required-support-row host host-state snapshot claim-value identity admissions
                           target: (target claim-value) authority: (authority #f)
                           output-digest: (output-digest #f))
  (let* ((obligation (snapshot-node snapshot identity))
         ((values reason witness)
          (cond
           ((not (and obligation (assurance-obligation? obligation)))
            (values 'obligation-missing #f))
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
            (values 'obligation-stale #f))
           ((not (required-support-link? snapshot obligation target))
            (values 'support-link-missing #f))
           (else
            (admitted-requirement-support
             host host-state snapshot obligation admissions
             authority: authority output-digest: output-digest)))))
    (cons (support-assessment-row identity reason) witness)))

(def (support-assessment-row identity reason)
  (validate AssessmentRequiredSupport
    (.o (:: @ (.ref AssessmentRequiredSupport 'proto))
        obligation: identity supported?: (not reason) blocker: reason)))

;; Review is scoped evidence for an explicit premise. A matching authority
;; string on its own has no standing without a current Host admission.
(def (assumption-review-witness host host-state snapshot assumption rows admissions)
  (ormap
   (lambda (row)
     (and (.ref row 'supported?)
          (let (obligation (snapshot-node snapshot (.ref row 'obligation)))
            (and (eq? (.ref obligation 'evidence-kind) 'human-review)
                 (eq? (.ref obligation 'capability) 'assumption-review)
                 (required-support-link? snapshot obligation assumption)
                 (let-values (((_ witness)
                               (admitted-requirement-support
                                host host-state snapshot obligation admissions
                                authority: (.ref assumption 'owner))))
                   witness)))))
   rows))

(def (assumption-assessment host host-state snapshot claim-value rows admissions identity)
  (let* ((node (snapshot-node snapshot identity))
         (assumption (and node (assurance-assumption? node) node))
         (owner-value (and assumption (.ref assumption 'owner)))
         (policy-value (and assumption (.ref assumption 'review-policy)))
         ((values reason witness)
          (cond
           ((not assumption) (values 'assumption-missing #f))
           ((not (equal? (.ref assumption 'scope) (.ref claim-value 'scope)))
            (values 'scope-mismatch #f))
           ((not (memq (.ref assumption 'state) '(unknown supported)))
            (values 'assumption-unavailable #f))
           ((not (equal? policy-value "human-review"))
            (values 'review-policy-unhandled #f))
           ;; The Host clock is monotonic. It cannot interpret a date.
           ((.ref assumption 'expires-at) (values 'validity-unqualified #f))
           (else
            (let (review (and (vector-ref host-state 10)
                              (assumption-review-witness
                               host host-state snapshot assumption rows admissions)))
              (values (and (not review) 'review-missing) review))))))
    (validate AssuranceAssumptionAssessment
      (.o (:: @ (.ref AssuranceAssumptionAssessment 'proto))
          assumption: identity owner: owner-value review-policy: policy-value
          obligation: (and witness (.ref witness 'obligation))
          admission: (and witness (.ref witness 'admission)) blocker: reason))))

;; A challenge remains visible even if its cited evidence is missing or out
;; of scope. Only a matching citation and defeat edge acquire trace fields.
(def (challenge-assessment snapshot claim-value node)
  (let* ((identity (.ref node 'identity))
         (citation (.ref node 'evidence))
         (evidence-node (snapshot-node snapshot citation))
         (relation-value
          (find (lambda (edge)
                  (and (eq? (.ref edge 'relation) 'defeats)
                       (eq? (.ref edge 'modality) 'observed)
                       (equal? (.ref edge 'source) identity)
                       (equal? (.ref edge 'target) (.ref claim-value 'identity))))
                (.ref snapshot 'relations)))
         (digest-value
          (and relation-value evidence-node (assurance-evidence? evidence-node)
               (eq? (.ref node 'state) 'supported)
               (eq? (.ref evidence-node 'state) 'supported)
               (equal? (.ref node 'subject) (.ref claim-value 'subject))
               (equal? (.ref node 'revision) (.ref claim-value 'revision))
               (equal? (.ref evidence-node 'revision) (.ref claim-value 'revision))
               (equal? (.ref evidence-node 'subject) (.ref claim-value 'subject))
               (equal? (.ref evidence-node 'scope) (.ref claim-value 'scope))
               (.ref evidence-node 'content-digest))))
    (validate AssuranceChallengeAssessment
      (.o (:: @ (.ref AssuranceChallengeAssessment 'proto))
          challenge: identity revision: (.ref node 'revision)
          kind: (.ref node 'kind) state: (.ref node 'state)
          subject: (.ref node 'subject) evidence: citation
          evidence-digest: digest-value
          scope: (and digest-value (.ref evidence-node 'scope))
          obligation: (and digest-value (.ref evidence-node 'obligation))
          relation: (and relation-value (.ref relation-value 'identity))))))

;; Governance can accept exposure to a residual. Its review is attached to
;; the Decision and never becomes a support witness for the engineering claim.
(def (residual-disposition host host-state snapshot claim-value row admissions)
  (let* ((residual (.ref row 'obligation))
         (decision-ids
          (delete-duplicates/hash
           (filter-map (lambda (edge)
                         (and (eq? (.ref edge 'relation) 'requires-review)
                              (not (memq (.ref edge 'modality) '(hypothesized counterfactual)))
                              (equal? (.ref edge 'source) residual)
                              (.ref edge 'target)))
                       (.ref snapshot 'relations))))
         (decision-value
          (and (pair? decision-ids) (null? (cdr decision-ids))
               (snapshot-node snapshot (car decision-ids)))))
    (and decision-value (assurance-decision? decision-value)
         (eq? (.ref decision-value 'state) 'supported)
         (eq? (.ref decision-value 'outcome) 'allow)
         (equal? (.ref decision-value 'subject) (.ref claim-value 'subject))
         (equal? (.ref decision-value 'revision) (.ref snapshot 'revision))
         (equal? (.ref decision-value 'snapshot) (.ref snapshot 'identity))
         (equal? (.ref decision-value 'policy) (.ref snapshot 'policy-identity))
         (decision-depends-on-claim? snapshot decision-value claim-value)
         (let* ((authority-value (.ref decision-value 'authority))
                (decision-digest
                 (assurance-canonical-digest (assurance-node-canonical decision-value)))
                (review
                 (ormap (lambda (node)
                          (and (assurance-obligation? node)
                               (eq? (.ref node 'evidence-kind) 'human-review)
                               (eq? (.ref node 'capability) 'residual-risk-acceptance)
                               (not (member (.ref node 'identity)
                                            (.ref claim-value 'support-requirements)))
                               (cdr (required-support-row
                                     host host-state snapshot claim-value (.ref node 'identity)
                                     admissions target: decision-value authority: authority-value
                                     output-digest: decision-digest))))
                        (.ref snapshot 'nodes))))
           (and review
                (validate AssuranceResidualDisposition
                  (.o (:: @ (.ref AssuranceResidualDisposition 'proto))
                      obligation: residual decision: (.ref decision-value 'identity)
                      authority: authority-value policy: (.ref decision-value 'policy)
                      policy-revision: (.ref snapshot 'policy-revision)
                      admission: (.ref review 'admission)
                      outcome-digest: (.ref review 'outcome-digest))))))))

;;; Inert, explainable input for a later Decision evaluator. Completion means
;;; only that every declared support requirement has a current Host witness;
;;; it does not resolve policy, validity intervals or Runtime effect authority.
(def (assurance-host-required-support host claim-value admissions)
  (unless (and (assurance-claim? claim-value) (list? admissions))
    (error "invalid required-support inputs"))
  (let* ((host-state (required-host-entry host))
         (snapshot (host-current-snapshot host-state))
         (initial-digest (vector-ref host-state 7))
         (initial-epoch (vector-ref host-state 8))
         (current-claim (snapshot-node snapshot (.ref claim-value 'identity)))
         (required-identities (.ref claim-value 'support-requirements))
         (assessments
          (map (lambda (identity)
                 (required-support-row
                  host host-state snapshot claim-value identity admissions))
               required-identities))
         (checked-rows (map car assessments))
         (assumption-rows
          (map (lambda (identity)
                 (assumption-assessment host host-state snapshot claim-value
                                        checked-rows admissions identity))
               (.ref claim-value 'assumptions)))
         (challenge-nodes
          (filter (lambda (node)
                    (and (memq (.ref node 'kind) '(counterexample finding))
                         (equal? (.ref node 'challenges) (.ref claim-value 'identity))))
                  (.ref snapshot 'nodes)))
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
           (if (find (lambda (row) (.ref row 'blocker)) assumption-rows)
             '(assumptions-unresolved) '())
           (if (pair? (.ref claim-value 'defeaters))
             '(defeaters-unresolved) '())
           (if (memq (.ref claim-value 'state)
                     '(violated stale conflicted hypothesized counterfactual
                       not-applicable))
             '(claim-state-blocked) '())
           (if (pair? challenge-nodes)
             '(challenge-unresolved) '())))
         (dispositions
          (if (and (vector-ref host-state 10)
                   (not (memq 'claim-not-current global-blockers))
                   (not (memq 'snapshot-conflicted global-blockers))
                   (not (memq 'snapshot-unresolved global-blockers)))
            (filter-map (lambda (row)
                          (and (memq (.ref row 'blocker) '(admission-missing admission-invalid))
                               (residual-disposition host host-state snapshot claim-value
                                                     row admissions)))
                        checked-rows)
            '()))
         (_ (host-current-snapshot host-state))
         (final-blockers
          (append global-blockers
                  (if (and (= initial-epoch (vector-ref host-state 8))
                           (equal? initial-digest (vector-ref host-state 7)))
                    '() '(source-changed))))
         (invalid-cut
          (cond ((memq 'source-changed final-blockers) 'source-changed)
                ((memq 'claim-not-current final-blockers) 'claim-not-current)
                (else #f)))
         (challenge-rows
          (if invalid-cut '()
            (map (lambda (node) (challenge-assessment snapshot claim-value node))
                 challenge-nodes)))
         (rows (if invalid-cut
                 (map (lambda (identity) (support-assessment-row identity invalid-cut))
                      required-identities)
                 (map (lambda (row)
                        (if (and (eq? (.ref row 'blocker) 'admission-missing)
                                 (find (lambda (challenge)
                                         (equal? (.ref challenge 'obligation)
                                                 (.ref row 'obligation)))
                                       challenge-rows))
                          (support-assessment-row (.ref row 'obligation) 'counterevidence-present)
                          row))
                      checked-rows))))
    (validate
     AssuranceRequiredSupport
     (.o (:: @ (.ref AssuranceRequiredSupport 'proto))
         schema: "lambda-aitia.required-support"
         claim: (.ref claim-value 'identity)
         claim-revision: (.ref claim-value 'revision)
         subject: (.ref claim-value 'subject)
         predicate: (.ref claim-value 'predicate)
         scope: (.ref claim-value 'scope)
         assumptions: (.ref claim-value 'assumptions)
         assumption-assessments:
         (if invalid-cut
           (map (lambda (row)
                  (validate AssuranceAssumptionAssessment
                    (.o (:: @ row) obligation: #f admission: #f blocker: invalid-cut)))
                assumption-rows)
           assumption-rows)
         defeaters: (.ref claim-value 'defeaters)
         challenges: challenge-rows
         residual-dispositions: (if invalid-cut '() dispositions)
         snapshot-digest: (.ref snapshot 'digest)
         semantic-snapshot-digest: (string-copy initial-digest)
         requirements: rows blockers: final-blockers
         witnesses: (if invalid-cut
                      '()
                      (filter (lambda (witness) witness) (map cdr assessments)))
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
;;; It conveys no policy decision or effect authorization.
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
                 (validate
                  AssuranceDecisionPreflight
                  (.o (:: @ (.ref AssuranceDecisionPreflight 'proto))
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

;; A policy adapter may project a current preflight into its request format.
;; These descriptive facts convey no authority and expose no Host state.
(def (assurance-host-current-preflight-binding host preflight)
  (let* ((state (required-host-entry host))
         (issued (decision-preflight-entry host preflight)))
    (and issued
         (assurance-host-decision-preflight-current? host preflight)
         (let* ((snapshot (host-current-snapshot state))
                (epoch (vector-ref issued 7))
                (decision-node (vector-ref issued 8))
                (claim-node (vector-ref issued 9)))
           (and (same-host-cut? state snapshot epoch)
                (equal? (assurance-snapshot-semantic-digest snapshot) (vector-ref issued 6))
                (.o preflight: (string-copy (vector-ref issued 1))
                    decision: (string-copy (vector-ref issued 3))
                    claim: (string-copy (vector-ref issued 4))
                    snapshot-digest: (string-copy (vector-ref issued 5))
                    snapshot-semantic-digest: (string-copy (vector-ref issued 6))
                    policy: (string-copy (.ref decision-node 'policy))
                    policy-revision: (string-copy (.ref snapshot 'policy-revision))
                    principal: (string-copy (.ref decision-node 'authority))
                    resource: (string-copy (.ref claim-node 'subject))))))))

;; The owner-configured Governance reader is the independent authority.
;; The provider adapter supplies its exact proposal binding and currentness.
(def (assurance-host-governance-source host preflight key request proposal current?)
  (let* ((state (required-host-entry host))
         (reader (vector-ref state 11))
         (until (and reader (+ (host-instant state) (vector-ref state 3)))))
    (def (live?)
      (and (assurance-host-decision-preflight-current? host preflight)
           (current?)
           (< (host-instant state) until)))
    (and reader (live?)
         (let (approved (reader (string-copy key) request proposal))
           (and (assurance-digest? approved) (live?)
                (let* ((approval-digest (string-copy approved))
                       (admission-digest
                        (assurance-canonical-digest
                         (list 'aitia/governance-source-admission.v1 (vector-ref state 0)
                               (random-bytes 32) key approval-digest)))
                       (owner (current-thread))
                       (retired? #f))
                  (lambda ()
                    (unless (eq? owner (current-thread))
                      (error "Governance source admission requires its serialized owner"))
                    (cond
                     (retired? #f)
                     ((and (live?)
                           (equal? approval-digest (reader (string-copy key) request proposal))
                           (live?))
                      (string-copy admission-digest))
                     (else (set! retired? #t) #f)))))))))

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
