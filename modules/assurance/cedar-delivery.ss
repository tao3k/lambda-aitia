;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref .call .slot? object?)
        (only-in :std/encoding/hex hex-decode)
        (only-in "types.ss" assurance-digest?)
        (only-in :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
                 journal-get journal-receive! journal-begin! journal-put!
                 journal-commit! journal-abort!)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :agentic-ai-lab/modules/authorization/providers/cedar/runtime-port
                 agentic-ai-lab-cedar-runtime-port))
(export assurance-open-cedar-delivery)

;; The same serialized owner holds the live source lookup, private Runtime
;; port and configured delivery operation. Consume is the effect start fence.
(def (assurance-open-cedar-delivery source-admission host executable endpoint artifact snapshot deliver
                                   journal: (journal #f) provider-reader: (provider-reader #f))
  (unless (procedure? deliver) (error "Cedar delivery requires an effect operation"))
  (unless (or (not provider-reader) (and journal (procedure? provider-reader)))
    (error "Cedar reconciliation requires a journal and a provider reader"))
  (let* ((owner (current-thread))
         (active #f)
         (resolved #f)
         (retired (make-hash-table-eq weak-keys: #t))
         (port-failure #f)
         (runtime
          (agentic-ai-lab-cedar-runtime-port
           executable endpoint artifact snapshot
           source-lookup: (lambda (proposal)
                            (and (pair? active) (eq? proposal (car active))
                                 (let (digest ((cdr active)))
                                   (set! resolved (and digest (string-copy digest)))
                                   digest))))))
    (def (require-owner!)
      (unless (and (eq? owner (current-thread)) (not active))
        (error "Cedar delivery requires its idle serialized owner")))
    (def (consume-source! request proposal)
      (when port-failure (raise port-failure))
      (with-catch
        (lambda (exception)
          (hash-put! retired request #t)
          (set! port-failure exception)
          (raise exception))
        (lambda () (.call runtime .consume-source! runtime proposal))))
    (def (operation-key operation)
      (unless (and (string? operation) (> (string-length operation) 0))
        (error "Durable Cedar delivery requires a stable operation identity"))
      (string-append "aitia/cedar/" operation))
    (def (record! key phase-value consumption-value expected (provider-evidence #f))
      (let (event (string-append key "/" (symbol->string phase-value)))
        (journal-receive! journal event (if provider-evidence
                                           (list key phase-value provider-evidence)
                                           (list key phase-value)))
        (journal-begin! journal event)
        (with-catch
          (lambda (failure) (journal-abort! journal) (raise failure))
          (lambda ()
            (let* ((prior (journal-get journal key))
                   (accepted (if expected
                               (and prior (eq? (.ref prior 'phase) expected))
                               (not prior))))
              (when accepted
                (let (provenance (if prior (.ref prior 'consumption) consumption-value))
                  (journal-put! journal key
                    (.o phase: phase-value consumption: provenance
                        provider-observation: provider-evidence))))
              (journal-commit! journal)
              accepted)))))
    (def (provider-evidence operation-value consumption observed)
      (and (object? observed)
           (andmap (lambda (slot) (.slot? observed slot))
                   '(outcome operation intent-digest payload-digest receipt-digest))
           (eq? (.ref observed 'outcome) 'committed)
           (equal? operation-value (.ref observed 'operation))
           (equal? (.ref consumption 'intent-digest) (.ref observed 'intent-digest))
           (equal? (.ref consumption 'payload-digest) (.ref observed 'payload-digest))
           (let (receipt-value (.ref observed 'receipt-digest))
             (and (assurance-digest? receipt-value)
                  (.o outcome: 'committed operation: (string-copy operation-value)
                      intent-digest: (.ref consumption 'intent-digest)
                      payload-digest: (.ref consumption 'payload-digest)
                      receipt-digest: (string-copy receipt-value))))))
    (def (reconcile! operation)
      (and provider-reader
           (let* ((key (operation-key operation))
                  (status (journal-get journal key)))
             (and status (eq? (.ref status 'phase) 'dispatching)
                  (let* ((consumption (.ref status 'consumption))
                         (observation (provider-reader (string-copy operation)))
                         (evidence (provider-evidence operation consumption observation)))
                    (and evidence (record! key 'reconciled #f 'dispatching evidence)
                         (journal-get journal key)))))))
    (def (dispatch-current? key consumption admission-digest)
      (or (not key)
          (and (record! key 'dispatching consumption #f)
               (if (equal? ((cdr active)) admission-digest)
                   #t
                   (begin
                     (unless (record! key 'withheld #f 'dispatching)
                       (error "Durable Cedar withdrawal has no dispatch record"))
                     #f)))))
    (def (deliver-consumed request proposal receipt key)
      (hash-put! retired request #t)
      (let* ((handoff (hash-ref receipt "handoff"))
             (expected (.ref proposal 'handoff))
             (hex (hash-ref handoff "payload_hex"))
             (bytes (hex-decode hex))
             (sequence-value (hash-ref handoff "sequence"))
             (payload-digest-value (hash-ref receipt "payload_digest"))
             (binding (hash-ref receipt "source_binding"))
             (admission (hash-ref binding "admission"))
             (admission-digest (hash-ref admission "admission_digest"))
             (intent-value (hash-ref binding "intent_digest")))
        (unless (and resolved (equal? resolved admission-digest)
                     (equal? intent-value (.ref proposal 'intent))
                     (equal? hex (.ref expected 'payload-hex))
                     (= sequence-value (.ref expected 'sequence))
                     (equal? payload-digest-value (source-lock-payload-digest bytes)))
          (error "Cedar consumed handoff differs from the admitted proposal"))
        (let* ((consumption-value
                (.o grant-id: (hash-ref receipt "grant_id")
                    source-admission-digest: admission-digest
                    proposal-digest: (hash-ref admission "proposal_digest")
                    decision-receipt-digest: (hash-ref binding "decision_receipt_digest")
                    authority-instance: (hash-ref binding "authority_instance")
                    policy-revision: (hash-ref binding "policy_revision")
                    intent-digest: intent-value sequence: sequence-value
                    payload-digest: payload-digest-value)))
          (and (dispatch-current? key consumption-value admission-digest)
               (let (result-value (deliver bytes consumption-value))
                 (when key
                   (unless (record! key 'acknowledged consumption-value 'dispatching)
                     (error "Durable Cedar acknowledgement has no dispatch record")))
                 (.o outcome: 'delivered result: result-value consumption: consumption-value))))))
    (.o .deliver!:
        (lambda (self request context (operation #f))
          (require-owner!)
          (when (and operation (not journal)) (error "Cedar operation requires its durable journal"))
          (let (key (and journal (operation-key operation)))
            (and (not (hash-get retired request))
                 (not (and key (journal-get journal key)))
                 (dynamic-wind
                 (lambda () (set! active 'preparing))
                 (lambda ()
                   (let-values (((proposal lookup)
                                 (source-admission host request context)))
                     (and proposal
                          (begin
                            (set! active (cons proposal lookup))
                            (let (receipt (consume-source! request proposal))
                              (and receipt (deliver-consumed request proposal receipt key)))))))
                   (lambda () (set! resolved #f) (set! active #f))))))
        .reconcile!: (lambda (self operation)
                       (require-owner!)
                       (dynamic-wind
                         (lambda () (set! active 'reconciling))
                         (lambda () (reconcile! operation))
                         (lambda () (set! active #f))))
        .delivery-status: (lambda (self operation)
                            (require-owner!)
                            (and journal (journal-get journal (operation-key operation))))
        .close!: (lambda (self)
                   (require-owner!)
                   (.call runtime .close! runtime)))))
