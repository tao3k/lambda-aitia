;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o)
        (only-in :clan/poo/mop element?)
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/number UInt)
        (for-template :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in "types.ss" NonEmptyString))
(export gitops-commit-intent gitops-record-commit-approval!
        gitops-revoke-commit-approval! gitops-consume-commit-admission!
        gitops-commit-admission)

(def CommitApproval
  (Record identity: [NonEmptyString] project: [NonEmptyString] intent: [NonEmptyString]
          policy-revision: [NonEmptyString] not-before: [UInt] expires-at: [UInt]))

(def (commit-journal-operations)
  (compiled-role-values 'agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
    '(journal-pack journal-get journal-put! journal-receive!
      journal-begin! journal-commit! journal-abort!)))

(def (gitops-commit-intent project attempt review-context)
  (commit-intent (.get (commit-journal-operations) journal-pack)
    project attempt review-context))

(def (commit-intent pack project attempt review-context)
  (source-lock-payload-digest
   (string->utf8 (pack (list "aitia.commit-intent.v2" project attempt review-context)))))

;; Keep the existing journal addresses so recorded revocations and spent
;; approvals remain visible. Only the admitted intent gains review binding.
(def (journal-key pack kind project value)
  (string-append "aitia/commit/" kind "/"
                 (source-lock-payload-digest
                  (string->utf8 (pack (list "aitia.commit-intent.v1" project value))))))

(def (commit-transition! operations journal project request transition)
  (let (event (journal-key (.get operations journal-pack) "request" project request))
    ((.get operations journal-receive!) journal event request)
    ((.get operations journal-begin!) journal event)
    (with-catch
      (lambda (failure) ((.get operations journal-abort!) journal) (raise failure))
      (lambda ()
        (let (result (transition))
          ((.get operations journal-commit!) journal (and result #t))
          result)))))

;; Only the configured Governance owner may submit authenticated decisions.
;; The journal orders decisions with consumption and never replaces an identity.
(def (gitops-record-commit-approval! journal approval)
  (unless (and (element? CommitApproval approval)
               (< (.get approval not-before) (.get approval expires-at)))
    (error "invalid commit approval"))
  (def operations (commit-journal-operations))
  (def pack (.get operations journal-pack))
  (def journal-get (.get operations journal-get))
  (def journal-put! (.get operations journal-put!))
  (let* ((project-id (.get approval project))
         (review-id (.get approval identity))
         (grant-key (journal-key pack "approval" project-id review-id))
         (revoked-key (journal-key pack "revoked" project-id review-id)))
    (commit-transition! operations journal project-id (list 'approve approval)
      (lambda ()
        (and (not (journal-get journal grant-key))
             (not (journal-get journal revoked-key))
             (begin (journal-put! journal grant-key approval) #t))))))

(def (gitops-revoke-commit-approval! journal project-id review-id)
  (def operations (commit-journal-operations))
  (def pack (.get operations journal-pack))
  (def journal-get (.get operations journal-get))
  (def journal-put! (.get operations journal-put!))
  (let (revoked-key (journal-key pack "revoked" project-id review-id))
    (commit-transition! operations journal project-id (list 'revoke project-id review-id)
      (lambda ()
        (and (not (journal-get journal revoked-key))
             (begin (journal-put! journal revoked-key #t) #t))))))

;; This result records an admission, with no effect outcome yet.
(def (gitops-consume-commit-admission!
      journal project-id attempt-bytes review-context-value approval-id policy-version clock)
  (def operations (commit-journal-operations))
  (def pack (.get operations journal-pack))
  (def journal-get (.get operations journal-get))
  (def journal-put! (.get operations journal-put!))
  (let* ((intent-value (commit-intent pack project-id attempt-bytes review-context-value))
         (attempt-key (journal-key pack "intent" project-id intent-value))
         (spent-key (journal-key pack "spent" project-id approval-id))
         (grant-key (journal-key pack "approval" project-id approval-id))
         (revoked-key (journal-key pack "revoked" project-id approval-id)))
    (def (current?)
      (and (not (journal-get journal attempt-key))
           (not (journal-get journal spent-key))
           (not (journal-get journal revoked-key))
           (let ((approval (journal-get journal grant-key))
                 (now (clock)))
             (and approval (exact-integer? now)
                  (equal? intent-value (.get approval intent))
                  (equal? policy-version (.get approval policy-revision))
                  (<= (.get approval not-before) now)
                  (< now (.get approval expires-at))))))
    (and (current?)
         (commit-transition! operations journal project-id
           (list 'consume project-id intent-value approval-id policy-version attempt-bytes review-context-value)
           (lambda ()
             (and (current?)
                  (let (admission
                        (.o phase: 'admitted project: project-id intent: intent-value
                            approval: approval-id policy-revision: policy-version
                            attempt: attempt-bytes review-context: review-context-value))
                    (journal-put! journal attempt-key admission)
                    (journal-put! journal spent-key intent-value)
                    admission)))))))

;; Recovery can find the original attempt by the consumed approval. This
;; historical row stays available after revocation and carries no authority.
(def (gitops-commit-admission journal project-id review-id)
  (def operations (commit-journal-operations))
  (def pack (.get operations journal-pack))
  (def journal-get (.get operations journal-get))
  (let (intent (journal-get journal (journal-key pack "spent" project-id review-id)))
    (and intent
         (or (journal-get journal (journal-key pack "intent" project-id intent))
             (error "missing commit admission for spent approval")))))
