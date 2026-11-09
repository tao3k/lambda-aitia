;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json JSONReadOptions string->json)
        (only-in :clan/poo/object .ref)
        (only-in :yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :agentic-ai-lab/modules/ai-agentic-context/query-provider
                 context-query-host context-org-source context-org-query
                 context-query-source! context-query-execute context-query-withdraw!)
        (rename-in (only-in "../../../modules/assurance/context-delivery.ss"
                            assurance-deliver-context-input)
                   (assurance-deliver-context-input deliver))
        (only-in "../../../modules/assurance/input-correspondence.ss"
                 assurance-agent-input-support-reader))
(export context-delivery-test)

(def json-options
  (JSONReadOptions key-as-symbol: #f array-as-vector: #f object-as-hash: #t))
(def original "[{\"role\":\"developer\",\"content\":\"Read only\"},{\"type\":\"function_call\",\"call_id\":\"q\",\"name\":\"inspect\",\"arguments\":\"{}\"},{\"type\":\"function_call_output\",\"call_id\":\"q\",\"output\":\"found\"}]")
(def changed "[{\"role\":\"developer\",\"content\":\"Do not use tools\"}]")

(def (publish owner generation text)
  (let* ((source (context-query-source!
                  owner
                  (context-org-source
                   "context" generation
                   (string-append
                    ":PROPERTIES:\n:ID: source\n:CONTRACT_ID: context.evidence-source.v1\n"
                    ":CONTRACT_REVISION: 1\n:END:\n\n#+title: Provider input\n\n"
                    "* Selected history\n:PROPERTIES:\n:ID: history\n:AGENT_INPUT: "
                    text "\n:END:\n"))))
         (observed (context-query-execute owner "context" (context-org-query source "history"))))
    (.ref observed 'semantic-digest)))

(def context-delivery-test
  (test-suite
   "Lab Context provider delivery"
   (test-case
    "A retained Host verifies once and does not renew an expired seal"
    (let ((now 10) (checks 0) (live? #t))
      (def (read-history text)
        (set! checks (+ checks 1))
        (string->json text json-options))
      (def (reader)
        (let (digest (source-lock-payload-digest original))
          (assurance-agent-input-support-reader
           "operation" "revision" "source/history" original digest original digest
           read-history (lambda (text) (string->json text json-options))
           current?: (lambda () live?) clock: (lambda () now) lease: 5)))
      (let (assess (reader))
        (check-equal? (.ref (assess) 'complete?) #t)
        (set! now 14)
        (check-equal? (.ref (assess) 'complete?) #t)
        (check-equal? checks 1)
        (set! now 15)
        (check-equal? (assess) 'reopened)
        (set! now 14)
        (check-equal? (assess) 'reopened)
        (check-equal? checks 1))
      (let (assess (reader))
        (check-equal? (.ref (assess) 'complete?) #t)
        (set! live? #f)
        (check-equal? (assess) 'reopened)
        (set! live? #t)
        (check-equal? (assess) 'reopened)
        (check-equal? checks 2))))
   (test-case
    "Only a current owner observation can support delivery"
    (let* ((owner (context-query-host))
           (foreign (context-query-host))
           (initial (publish owner 1 original))
           (settings (make-hash-table))
           (input (string->json original json-options))
           (sends 0))
      (hash-put! settings "model" "fixture")
      (def (send body) (set! sends (+ sends 1)) body)
      (def (refused host reference projected)
        (let-values (((result assess) (deliver host reference settings projected send)))
          (check-equal? result #f)
          (check-equal? assess #f)))
      (refused foreign initial input)
      (refused owner "forged-reference" input)
      (refused owner initial (string->json changed json-options))
      (check-equal? sends 0)
      (let-values (((result assess)
                    (deliver owner initial settings input (lambda (body) #f))))
        (check-equal? result #f)
        (check-equal? assess #f))
      (let-values (((body assess) (deliver owner initial settings input send)))
        (let* ((request (string->json body json-options))
               (support (assess)))
          (check-equal? (hash-ref request "model") "fixture")
          (check-equal? (length (hash-ref request "input")) 3)
          (check-equal? (.ref support 'complete?) #t)
          (check-equal? (.ref support 'release-authorized?) #f)
          (check-equal? (.ref support 'claim-revision) initial)
          (check-equal? (.ref support 'subject) (source-lock-payload-digest body))
          (check-equal? (length (.ref support 'witnesses)) 1))
        (let (replacement (publish owner 2 changed))
          (check-equal? (assess) 'reopened)
          (refused owner initial input)
          (refused owner replacement input)
          (let-values (((updated check-updated)
                        (deliver owner replacement settings (string->json changed json-options) send)))
            (check-equal? (.ref (check-updated) 'complete?) #t)
            (context-query-withdraw! owner "context" 3)
            (check-equal? (check-updated) 'reopened)
            (refused owner replacement (string->json changed json-options))
            (publish owner 4 original)
            (check-equal? (assess) 'reopened)
            (check-equal? sends 2)
            (let (latest (publish owner 5 original))
              (let-values (((sent assess-race)
                            (deliver owner latest settings input
                                     (lambda (body)
                                       (publish owner 6 changed)
                                       (send body)))))
                (check-equal? (string? sent) #t)
                (check-equal? (assess-race) 'reopened)
                (check-equal? sends 3))))))))))
