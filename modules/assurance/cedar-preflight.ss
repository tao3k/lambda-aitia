;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref .slot? .alist object?)
        (only-in :agentic-ai-lab/modules/authorization/providers/cedar/objects
                 agentic-ai-lab-cedar-runtime-handoff?
                 agentic-ai-lab-cedar-authorization-request
                 agentic-ai-lab-cedar-authorization-request?)
        (only-in "func.ss" assurance-canonical-digest)
        (only-in :lambda-aitia/modules/assurance/host assurance-host-current-preflight-binding
                 assurance-host-decision-preflight-current?
                 assurance-host-governance-source))
(export assurance-host-cedar-request assurance-host-cedar-request-current?
        assurance-host-cedar-source-admission)

(def issued-cedar-requests (make-hash-table-eq weak-keys: #t))

(def (cedar-request-fingerprint request)
  ;; Freeze a value digest, not aliases to caller-visible mutable strings.
  (assurance-canonical-digest
   (list (.ref request 'principal) (.ref request 'action)
         (.ref request 'resource) (.alist (.ref request 'context))
         (.ref request 'intent) (.alist (.ref request 'handoff)))))

(def (assurance-host-cedar-request host preflight action-value intent-value handoff-value)
  (unless (agentic-ai-lab-cedar-runtime-handoff? handoff-value)
    (error "Decision Cedar projection requires an Agentic AI Lab runtime handoff"))
  (let (binding (assurance-host-current-preflight-binding host preflight))
    (and binding
         (let* ((context
                 (.o aitia_schema: "lambda-aitia.cedar-preflight.v1"
                     agentic_ai_lab_preflight_only: #t
                     aitia_preflight: (.ref binding 'preflight)
                     aitia_decision: (.ref binding 'decision)
                     aitia_claim: (.ref binding 'claim)
                     aitia_snapshot_digest: (.ref binding 'snapshot-digest)
                     aitia_snapshot_semantic_digest: (.ref binding 'snapshot-semantic-digest)
                     aitia_policy: (.ref binding 'policy)
                     aitia_policy_revision: (.ref binding 'policy-revision)
                     aitia_preflight_only: #t))
                (request
                 (agentic-ai-lab-cedar-authorization-request
                  (.ref binding 'principal) action-value (.ref binding 'resource)
                  context intent-value handoff-value))
                (fingerprint (cedar-request-fingerprint request)))
           (and (assurance-host-decision-preflight-current? host preflight)
                (begin
                  (hash-put! issued-cedar-requests request (vector host preflight fingerprint))
                  request))))))

(def (assurance-host-cedar-request-current? host request)
  (let (issued (hash-get issued-cedar-requests request))
    (and issued
         (eq? host (vector-ref issued 0))
         (agentic-ai-lab-cedar-authorization-request? request)
         (object? (.ref request 'context))
         (agentic-ai-lab-cedar-runtime-handoff? (.ref request 'handoff))
         (equal? (cedar-request-fingerprint request) (vector-ref issued 2))
         (assurance-host-decision-preflight-current? host (vector-ref issued 1))
         (equal? (cedar-request-fingerprint request) (vector-ref issued 2)))))

(def (assurance-host-cedar-source-admission host request policy-context)
  (unless (and (object? policy-context)
               (not (.slot? policy-context 'agentic_ai_lab))
               (not (.slot? policy-context 'agentic_ai_lab_preflight_only)))
    (error "Cedar policy context contains reserved authority fields"))
  (if (assurance-host-cedar-request-current? host request)
    (let* ((issued (hash-get issued-cedar-requests request))
           (proposal
            (agentic-ai-lab-cedar-authorization-request
             (.ref request 'principal) (.ref request 'action) (.ref request 'resource)
             (.o (:: @ policy-context) agentic_ai_lab_preflight_only: #t)
             (.ref request 'intent) (.ref request 'handoff)))
           (fingerprint (cedar-request-fingerprint proposal))
           (key (assurance-canonical-digest
                 (list 'aitia/cedar-governance-admission.v1
                       (cedar-request-fingerprint request) fingerprint)))
           (resolve
            (assurance-host-governance-source
             host (vector-ref issued 1) key request proposal
             (lambda ()
               (and (equal? (vector-ref issued 2) (cedar-request-fingerprint request))
                    (equal? fingerprint (cedar-request-fingerprint proposal)))))))
      (if resolve (values proposal resolve) (values #f #f)))
    (values #f #f)))
