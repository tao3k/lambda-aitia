;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/list/list find)
        (only-in :std/encoding/json JSONReadOptions json->string string->json)
        (only-in :clan/poo/object .ref)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :agentic-ai-lab/modules/temporal-causality/runtime/monotonic-clock
                 monotonic-seconds)
        (only-in :agentic-ai-lab/modules/ai-agentic-context/query-provider
                 context-query-export context-query-current? context-query-lineage)
        (only-in :orgize/languages/org/modules/org-elements/source-interface
                 org-source-element-graph org-source-element-field)
        (only-in :orgize/languages/org/modules/org-elements/query
                 org-element-map make-org-element-query-context)
        (only-in "input-correspondence.ss"
                 assurance-agent-input-corresponds? assurance-agent-input-support-reader))
(export assurance-deliver-context-input assurance-prepare-context-input
        assurance-prepare-context-body)

(def input-options
  (JSONReadOptions key-as-symbol: #f array-as-vector: #f object-as-hash: #t))

(def (read-input text)
  (string->json text input-options))

(def (read-request-input text)
  (let (request (read-input text))
    (and (hash-table? request) (hash-get request "input"))))

(def (selected-history source element-id)
  (let* ((graph (org-source-element-graph (.ref source 'source)))
         (matches
          (org-element-map (make-org-element-query-context graph) "headline"
                           (lambda (row)
                             (equal? element-id (org-source-element-field row "property:ID"))))))
    (and (pair? matches) (null? (cdr matches))
         (org-source-element-field (car matches) "property:AGENT_INPUT"))))

;; The application supplies the live Lab Query owner and an observation
;; reference. Only that owner's journal can supply the selected input.
;; The result stays owner-local. The transport must successfully consume
;; the checked body before the application can expose its assessor.
(def (assurance-prepare-context-input owner reference settings projected)
  (and (list? projected)
       (hash-table? settings)
       (not (hash-key? settings "input"))
       (let (request (hash-copy settings))
         (hash-put! request "input" (list->vector projected))
         (assurance-prepare-context-body owner reference (json->string request)))))

;; Recovery checks the original bytes instead of rendering another request.
(def (assurance-prepare-context-body owner reference body)
  (let* ((journal (context-query-export owner))
         (observed (find (lambda (row) (equal? reference (.ref row 'semantic-digest)))
                         (.ref journal 'queries))))
    (and observed
         (context-query-current? owner observed)
         (let* ((cut (.ref observed 'source-cut))
                (lineage (context-query-lineage observed))
                (ids (.ref lineage 'org-ids))
                (history (and (pair? ids) (null? (cdr ids))
                              (selected-history cut (car ids)))))
           (and history
                (<= (+ (u8vector-length (string->utf8 history))
                       (u8vector-length (string->utf8 body)))
                    (* 4 1024 1024))
                (assurance-agent-input-corresponds? (read-input history)
                                                    (read-request-input body))
                (context-query-current? owner observed)
                (let (reader
                      (delay
                        (assurance-agent-input-support-reader
                         (.ref cut 'semantic-digest)
                         (.ref observed 'semantic-digest)
                         (string-append (.ref cut 'identity) "/" (car ids))
                         history (source-lock-payload-digest history)
                         body (source-lock-payload-digest body)
                         read-input read-request-input
                         current?: (lambda () (context-query-current? owner observed))
                         clock: (lambda () (inexact->exact (floor (monotonic-seconds))))
                         lease: 300)))
                  (vector body (lambda () ((force reader))))))))))

;; The second result is a read-only assessment operation for a completed send.
(def (assurance-deliver-context-input owner reference settings projected send)
  (let (prepared (assurance-prepare-context-input owner reference settings projected))
    (if prepared
        (let* ((body (vector-ref prepared 0))
               (delivered (string-copy body))
               (result (send delivered)))
          (values result (and result (equal? delivered body) (vector-ref prepared 1))))
        (values #f #f))))
