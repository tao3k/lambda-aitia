;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure eligibility and sealed support checks. The Host still owns adapter
;;; identity, execution attestation and the transition to admitted evidence.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil/core list-sort)
        (only-in :std/list/list find every)
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-valid?)
        (only-in :poo-flow/lambda-aitia/modules/assurance/funs
                 assurance-canonical-digest assurance-node-canonical
                 assurance-relation-canonical)
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-verifier-input assurance-verifier-outcome
        assurance-evaluate-evidence-admission
        assurance-evidence-outcome-bound?
        assurance-verification-subject
        assurance-snapshot-semantic-digest
        assurance-verification-subject-snapshot
        assurance-support-sealed-under-adapter?)

(def (assurance-verifier-input artifact)
  (unless (assurance-artifact? artifact)
    (error "verifier input requires an artifact"))
  (poo-flow-check-model
   AssuranceVerifierInput
   (.o (:: @ (poo-flow-model-prototype AssuranceVerifierInput))
       identity: (.ref artifact 'identity)
       revision: (.ref artifact 'revision)
       digest: (.ref artifact 'content-digest))))

(def (assurance-verifier-outcome identity-value status-value
                                 producer: producer-value tool: tool-value
                                 tool-version: tool-version-value
                                 obligation: obligation-value
                                 subject: subject-value scope: scope-value
                                 snapshot-revision: snapshot-revision-value
                                 snapshot-context-digest: context-value
                                 inputs: input-values
                                 output-digest: (output-value #f)
                                 accountable-authority: (authority-value #f)
                                 review-scope: (review-scope-value #f))
  (poo-flow-check-model
   AssuranceVerifierOutcome
   (.o (:: @ (poo-flow-model-prototype AssuranceVerifierOutcome))
       identity: identity-value status: status-value
       producer: producer-value tool: tool-value
       tool-version: tool-version-value
       obligation: obligation-value subject: subject-value scope: scope-value
       snapshot-revision: snapshot-revision-value
       snapshot-context-digest: context-value inputs: input-values
       output-digest: output-value accountable-authority: authority-value
       review-scope: review-scope-value)))

(def (snapshot-node snapshot identity)
  (find (lambda (node) (string=? (.ref node 'identity) identity))
        (.ref snapshot 'nodes)))
(def (current-input? snapshot input)
  (let ((artifact (snapshot-node snapshot (.ref input 'identity))))
    (and artifact (assurance-artifact? artifact)
         (string=? (.ref input 'revision) (.ref artifact 'revision))
         (string=? (.ref input 'digest) (.ref artifact 'content-digest)))))
(def (duplicate-inputs? inputs)
  (let loop ((rest inputs) (seen '()))
    (and (pair? rest)
         (let ((identity (.ref (car rest) 'identity)))
           (or (member identity seen)
               (loop (cdr rest) (cons identity seen)))))))

(def (outcome-canonical reported-result)
  (list (.ref reported-result 'identity) (.ref reported-result 'status)
        (.ref reported-result 'producer) (.ref reported-result 'tool)
        (.ref reported-result 'tool-version)
        (.ref reported-result 'obligation) (.ref reported-result 'subject)
        (.ref reported-result 'scope)
        (.ref reported-result 'snapshot-revision)
        (.ref reported-result 'snapshot-context-digest)
        (map (lambda (input)
               (list (.ref input 'identity) (.ref input 'revision)
                     (.ref input 'digest)))
             (.ref reported-result 'inputs))
        (.ref reported-result 'output-digest)
        (.ref reported-result 'accountable-authority)
        (.ref reported-result 'review-scope)))

(def (assurance-verification-subject snapshot-value obligation-value
                                     evidence-value outcome-value)
  (poo-flow-check-model
   AssuranceVerificationSubject
   (.o (:: @ (poo-flow-model-prototype AssuranceVerificationSubject))
       snapshot: snapshot-value obligation: obligation-value
       evidence: evidence-value outcome: outcome-value)))

(def (snapshot-semantic-fields snapshot-value)
  (list (.ref snapshot-value 'identity)
           (.ref snapshot-value 'revision)
           (.ref snapshot-value 'graph-identity)
           (.ref snapshot-value 'source-revisions)
           (.ref snapshot-value 'claim-revisions)
           (.ref snapshot-value 'fact-cut)
           (.ref snapshot-value 'policy-identity)
           (.ref snapshot-value 'policy-revision)
           (.ref snapshot-value 'evidence-identities)
           (.ref snapshot-value 'state)
           (.ref snapshot-value 'context-digest)
           (.ref snapshot-value 'digest)
           (map assurance-node-canonical (.ref snapshot-value 'nodes))
           (map assurance-relation-canonical
                (.ref snapshot-value 'relations))
           (.ref snapshot-value 'unresolved)
           (.ref snapshot-value 'conflicts)))

;;; Use the entire semantic snapshot, not its editable displayed digest slot,
;;; when the Host detects a change and advances its invalidation epoch.
(def (assurance-snapshot-semantic-digest snapshot-value)
  (unless (assurance-snapshot? snapshot-value)
    (error "invalid assurance snapshot"))
  (assurance-canonical-digest
   (cons 'lambda-aitia.snapshot-semantic
         (snapshot-semantic-fields snapshot-value))))

;;; POO Flow's adapter freezes this string before and after its host-trusted
;;; operation. Recompute from every semantic field: mutating only a displayed
;;; snapshot digest must not preserve an issued seal.
(def (assurance-verification-subject-snapshot subject-value)
  (unless (assurance-verification-subject? subject-value)
    (error "invalid assurance verification subject"))
  (assurance-canonical-digest
   (append
    (cons 'lambda-aitia.verification-subject
          (snapshot-semantic-fields (.ref subject-value 'snapshot)))
    (list (assurance-node-canonical (.ref subject-value 'obligation))
          (assurance-node-canonical (.ref subject-value 'evidence))
          (outcome-canonical (.ref subject-value 'outcome))))))

(def (snapshot-relation snapshot-value identity-value)
  (find (lambda (relation)
          (string=? (.ref relation 'identity) identity-value))
        (.ref snapshot-value 'relations)))
(def (same-text-inventory? left right)
  (and (= (length left) (length right))
       (equal? (list-sort string<? left) (list-sort string<? right))))

(def (assurance-evidence-outcome-bound? snapshot evidence outcome)
  (and (assurance-snapshot? snapshot)
       (assurance-evidence? evidence)
       (assurance-verifier-outcome? outcome)
       (let (current-evidence
             (snapshot-node snapshot (.ref evidence 'identity)))
         (and current-evidence (assurance-evidence? current-evidence)
              (equal? (assurance-node-canonical current-evidence)
                      (assurance-node-canonical evidence))
              (equal? (.ref evidence 'content-digest)
                      (.ref outcome 'output-digest))
              (equal? (.ref evidence 'producer) (.ref outcome 'producer))
              (equal? (.ref evidence 'tool) (.ref outcome 'tool))
              (equal? (.ref evidence 'tool-version)
                      (.ref outcome 'tool-version))
              (same-text-inventory?
               (.ref evidence 'input-artifacts)
               (map (lambda (input) (.ref input 'identity))
                    (.ref outcome 'inputs)))))))

;;; Shape alone never grants support. This check is private to the sealed
;;; admission boundary and cannot be used as a public authorization shortcut.
(def (structural-support? relation evidence obligation)
  (and (assurance-relation? relation)
       (assurance-evidence? evidence)
       (assurance-obligation? obligation)
       (eq? (.ref relation 'plane) 'assurance)
       (memq (.ref relation 'relation) '(supports discharges))
       (equal? (.ref relation 'source) (.ref evidence 'identity))
       (equal? (.ref relation 'target) (.ref obligation 'identity))
       (equal? (.ref evidence 'obligation) (.ref obligation 'identity))
       (equal? (.ref evidence 'subject) (.ref obligation 'subject))
       (equal? (.ref evidence 'scope) (.ref obligation 'scope))
       (equal? (.ref evidence 'revision) (.ref obligation 'revision))
       (eq? (.ref evidence 'state) 'supported)
       (eq? (.ref evidence 'admission-state) 'admitted)
       (not (memq (.ref relation 'modality) '(hypothesized counterfactual)))))

;;; Conditional low-level check: this does not establish that the supplied
;;; adapter and clock belong to the application-configured Host.
(def (assurance-support-sealed-under-adapter?
      relation evidence obligation snapshot outcome adapter issued-receipt now)
  (and (structural-support? relation evidence obligation)
       (assurance-snapshot? snapshot)
       (assurance-verifier-outcome? outcome)
       (let ((current-relation
              (snapshot-relation snapshot (.ref relation 'identity)))
             (structural
              (assurance-evaluate-evidence-admission
               snapshot obligation outcome)))
         (and (assurance-evidence-outcome-bound? snapshot evidence outcome)
              current-relation
              (equal? (assurance-relation-canonical current-relation)
                      (assurance-relation-canonical relation))
              (.ref structural 'eligible?)
              (poo-flow-verification-valid?
               adapter issued-receipt
               (assurance-verification-subject
                snapshot obligation evidence outcome)
               now)))))

(def (assurance-evaluate-evidence-admission snapshot obligation outcome)
  (unless (and (assurance-snapshot? snapshot)
               (assurance-obligation? obligation)
               (assurance-verifier-outcome? outcome))
    (error "invalid evidence admission inputs"))
  (let* ((reported-result outcome)
         (required-obligation obligation)
         (current-snapshot snapshot)
         (inputs (.ref outcome 'inputs))
         (current-obligation
          (snapshot-node snapshot (.ref obligation 'identity)))
         (admission-blocker
          (cond
           ((not (eq? (.ref outcome 'status) 'succeeded))
            'outcome-not-successful)
           ((pair? (.ref snapshot 'conflicts)) 'snapshot-conflicted)
           ((or (not current-obligation)
                (not (assurance-obligation? current-obligation))
                (not (equal? (assurance-node-canonical obligation)
                             (assurance-node-canonical current-obligation)))
                (not (equal? (.ref obligation 'snapshot)
                             (.ref snapshot 'identity)))
                (not (equal? (.ref obligation 'snapshot-revision)
                             (.ref snapshot 'revision)))
                (not (equal? (.ref obligation 'snapshot-context-digest)
                             (.ref snapshot 'context-digest))))
            'stale-obligation)
           ((or (not (equal? (.ref outcome 'obligation)
                             (.ref obligation 'identity)))
                (not (equal? (.ref outcome 'subject)
                             (.ref obligation 'subject)))
                (not (equal? (.ref outcome 'scope)
                             (.ref obligation 'scope)))
                (not (equal? (.ref outcome 'snapshot-revision)
                             (.ref snapshot 'revision)))
                (not (equal? (.ref outcome 'snapshot-context-digest)
                             (.ref snapshot 'context-digest))))
            'outcome-binding-mismatch)
           ((not (.ref outcome 'output-digest)) 'missing-output)
           ((null? inputs) 'missing-inputs)
           ((duplicate-inputs? inputs) 'duplicate-inputs)
           ((not (every (lambda (input) (current-input? snapshot input))
                        inputs))
            'input-binding-mismatch)
           ((and (eq? (.ref obligation 'evidence-kind) 'human-review)
                 (or (not (.ref outcome 'accountable-authority))
                     (not (.ref outcome 'review-scope))
                     (not (equal? (.ref outcome 'review-scope)
                                  (.ref obligation 'scope)))))
            'human-authority-missing)
           (else #f)))
         (reported-digest
          (assurance-canonical-digest (outcome-canonical reported-result)))
         (receipt-digest
          (assurance-canonical-digest
           (list 'lambda-aitia.evidence-admission
                 reported-digest (assurance-node-canonical required-obligation)
                 (.ref current-snapshot 'digest) admission-blocker))))
    (poo-flow-check-model
     AssuranceEvidenceAdmissionReceipt
     (.o (:: @ (poo-flow-model-prototype AssuranceEvidenceAdmissionReceipt))
         schema: "lambda-aitia.evidence-admission"
         outcome: (.ref reported-result 'identity)
         obligation: (.ref required-obligation 'identity)
         outcome-digest: reported-digest
         snapshot-digest: (.ref current-snapshot 'digest)
         digest: receipt-digest
         eligible?: (not admission-blocker) blocker: admission-blocker
         verifier-executed?: #f release-authorized?: #f))))
