;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure structural eligibility only. The Host still owns adapter identity,
;;; execution attestation and the transition to admitted evidence.
(import (only-in :clan/poo/object .o .ref)
        (only-in :std/list/list find every)
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/lambda-aitia/modules/assurance/funs
                 assurance-canonical-digest assurance-node-canonical)
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-verifier-input assurance-verifier-outcome
        assurance-evaluate-evidence-admission)

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
