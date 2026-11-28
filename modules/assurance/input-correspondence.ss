;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in "objects.ss" assurance-artifact assurance-claim assurance-obligation
                 assurance-evidence)
        (only-in "observed-support.ss" assurance-observed-support-reader))

(export assurance-agent-input-corresponds? assurance-assess-agent-input-delivery
        assurance-agent-input-support-reader)

(def (nonempty-text? value)
  (and (string? value) (positive? (string-length value))))

;; Compare JSON content by value, including structured constraint content.
(def (json-content=? left right)
  (cond
   ((hash-table? left)
    (and (hash-table? right)
         (= (hash-length left) (hash-length right))
         (let loop ((keys (hash-keys left)))
           (or (null? keys)
               (let (key (car keys))
                 (and (hash-key? right key)
                      (json-content=? (hash-ref left key) (hash-ref right key))
                      (loop (cdr keys))))))))
   ((pair? left)
    (and (pair? right)
         (json-content=? (car left) (car right))
         (json-content=? (cdr left) (cdr right))))
   (else (equal? left right))))

;; Extract the ordered, policy-relevant fragment of a complete provider
;; history. Unpaired outputs and duplicate call identities invalidate it.
(def (required-input-fragment history)
  (and (list? history)
       (let ((calls (make-hash-table))
             (pending 0))
         (let loop ((items history) (rows '()))
           (cond
            ((null? items) (and (zero? pending) (reverse rows)))
            ((not (hash-table? (car items))) #f)
            (else
             (let* ((item (car items))
                    (kind (hash-ref item "type" 'untyped))
                    (role (hash-get item "role")))
               (cond
                ((equal? kind "function_call")
                 (let ((identity (hash-get item "call_id"))
                       (name (hash-get item "name"))
                       (arguments (hash-get item "arguments")))
                   (and (nonempty-text? identity) (nonempty-text? name)
                        (string? arguments) (not (hash-key? calls identity))
                        (begin
                          (hash-put! calls identity 'pending)
                          (set! pending (+ pending 1))
                          (loop (cdr items) (cons (list 'call identity name arguments) rows))))))
                ((equal? kind "function_call_output")
                 (let ((identity (hash-get item "call_id"))
                       (output (hash-get item "output")))
                   (and (nonempty-text? identity) (string? output)
                        (eq? (hash-get calls identity) 'pending)
                        (begin
                          (hash-put! calls identity 'complete)
                          (set! pending (- pending 1))
                          (loop (cdr items) (cons (list 'output identity output) rows))))))
                ((or (eq? kind 'untyped) (equal? kind "message"))
                 (and (hash-key? item "content")
                      (cond
                       ((member role '("system" "developer"))
                        (loop (cdr items)
                              (cons (list 'constraint role (hash-ref item "content")) rows)))
                       ((member role '("user" "assistant"))
                        (loop (cdr items) rows))
                       (else #f))))
                ((equal? kind "reasoning") (loop (cdr items) rows))
                (else #f)))))))))

(def (assurance-agent-input-corresponds? source projected)
  (let ((expected (required-input-fragment source))
        (actual (required-input-fragment projected)))
    (and expected actual (json-content=? expected actual))))

(def (assurance-assess-agent-input-delivery
      project operation revision scope source source-digest packet packet-digest read-source read-packet)
  ((assurance-agent-input-support-reader operation revision scope source source-digest
                                         packet packet-digest read-source read-packet
                                         subject: project)))

;; The caller holds the exact source and consumed packet. This operation
;; retains its Host and admission without exporting either capability.
(def (assurance-agent-input-support-reader
      operation revision scope source source-digest packet packet-digest read-source read-packet
      subject: (subject-value packet-digest)
      current?: (current? (lambda () #t)) clock: (clock (lambda () 0)) lease: (lease 1))
  (let* ((owner "aitia-runtime/recorded-agent-input")
         (method "agent-input-correspondence")
         (version "1")
         (source-id "artifact/agent-input-history")
         (packet-id "artifact/delivered-agent-input")
         (claim-id "claim/agent-input-correspondence")
         (obligation-id "preserve-required-input-fragment")
         (evidence-id "evidence/agent-input-delivery")
         (snapshot-id "recorded-agent-input")
         (source-value (assurance-artifact source-id revision 'supported source-digest
                                           owner: owner media-kind: 'json))
         (packet-value (assurance-artifact packet-id revision 'supported packet-digest
                                           owner: owner media-kind: 'json))
         (claim-value (assurance-claim claim-id revision 'unknown packet-digest
                                       subject: subject-value scope: scope valid-from: operation
                                       predicate: "Delivered input preserves the required history fragment"
                                       support-requirements: (list obligation-id)))
         (obligation-value
          (assurance-obligation obligation-id revision 'unknown packet-digest
                                subject: subject-value claim: claim-id scope: scope
                                snapshot: snapshot-id evidence-kind: 'integration-test
                                capability: 'agent-input-correspondence))
         (evidence-value
          (assurance-evidence evidence-id revision 'supported packet-digest
                              subject: subject-value scope: scope valid-from: operation
                              producer: owner tool: method tool-version: version
                              input-artifacts: (list source-id packet-id)
                              obligation: obligation-id admission-state: 'candidate)))
    (assurance-observed-support-reader
     operation claim-value obligation-value evidence-value (list source-value packet-value)
     (lambda (identity)
       (cond ((equal? identity source-id) source)
             ((equal? identity packet-id) packet)
             (else #f)))
     "delivery"
     (lambda (subject now expiry inputs)
       (assurance-agent-input-corresponds?
        (read-source (.ref (car inputs) 'payload))
        (read-packet (.ref (cadr inputs) 'payload))))
     current?: current? clock: clock lease: lease)))
