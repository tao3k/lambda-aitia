;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :clan/poo/object .o .call .ref .get)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
                 journal-open journal-close! journal-verify! journal-cut!)
        (only-in :std/encoding/json string->json JSONReadOptions)
        :agentic-ai-lab/modules/authorization/providers/cedar/objects
        (only-in "../../../modules/assurance/cedar-delivery.ss" assurance-open-cedar-delivery)
        (only-in "../../../modules/assurance/cedar-preflight.ss" assurance-host-cedar-source-admission)
        (only-in "../../../t/assurance/unit/decision-preflight-test.ss" make-cedar-delivery-fixture))
(export cedar-delivery-test make-cedar-restart-suite)

(def (open-cedar-delivery host executable endpoint artifact snapshot deliver
                           journal: (journal #f) provider-reader: (provider-reader #f))
  (assurance-open-cedar-delivery assurance-host-cedar-source-admission
                                 host executable endpoint artifact snapshot deliver
                                 journal: journal provider-reader: provider-reader))

(def (digest digit) (string-append "sha256:" (make-string 64 digit)))
(def schema
  "{\"\":{\"entityTypes\":{\"User\":{},\"Job\":{}},\"actions\":{\"release\":{\"appliesTo\":{\"principalTypes\":[\"User\"],\"resourceTypes\":[\"Job\"],\"context\":{\"type\":\"Record\",\"attributes\":{\"approved\":{\"type\":\"Boolean\"}}}}}}}}")

(def (snapshot)
  (agentic-ai-lab-cedar-authority-snapshot
   (agentic-ai-lab-cedar-authority-context "aitia.authority" "aitia.runtime" 1 (digest #\2) 7 1 0)
   (agentic-ai-lab-cedar-proof-binding "aitia.composition" '("aitia.profile")
      (digest #\1) (digest #\3) (digest #\4) (digest #\5) (digest #\a) (digest #\b)
      '("AgenticAILabProof.Runtime.CedarRuntime" "AgenticAILabProof.Runtime.CedarRuntimeHost"))
   (list (agentic-ai-lab-cedar-policy
          "release" "permit(principal == User::\"maintainer\", action == Action::\"release\", resource == Job::\"release\") when { context.approved };"))
   (agentic-ai-lab-cedar-schema schema)
   (agentic-ai-lab-cedar-entities "[]")
   (list (agentic-ai-lab-cedar-runtime-capability "Action::\"release\"" 1
           source-admission-required?: #t))))

(def (call-with-cedar-host run)
  (call-with-temporary-directory "aitia-cedar"
    (lambda (root)
      (let* ((issuer (getenv "AITIA_CEDAR_ISSUER"))
             (artifact (getenv "AITIA_CEDAR_HOST"))
             (endpoint (path-expand "runtime.sock" root))
             (server (open-process
                      (list path: issuer arguments: (list "serve-host" artifact endpoint)))))
        (input-port-timeout-set! server 12.)
        (dynamic-wind
          void
          (lambda ()
            (let (ready (string->json (read-line server) (JSONReadOptions object-as-hash: #t)))
              (check-equal? (hash-ref ready "schema_id") "agentic-ai-lab.cedar-runtime-ready.v1")
              (check-equal? (hash-ref ready "endpoint") endpoint))
            (run issuer artifact endpoint (path-expand "effect.bin" root))
            (check-equal? (process-status server) 0))
          (lambda () (close-port server)))))))

(def (exercise-durable-delivery database effect provider-receipt operation-id confirmed phase)
  (call-with-cedar-host
   (lambda (issuer artifact endpoint ignored)
     (let ((journal (journal-open database))
           (reads 0)
           (provider-reads 0)
           (provider-mode 'unknown))
       (dynamic-wind
         void
         (lambda ()
           (let-values (((host request)
                         (make-cedar-delivery-fixture
                          (lambda args
                            (set! reads (+ reads 1))
                            (digest #\d)))))
             (let ((delivery
                    (open-cedar-delivery
                     host issuer endpoint artifact (snapshot)
                     (lambda (bytes receipt)
                       (when (eq? phase 'restart)
                         (error "durable operation was sent again"))
                       (if (eq? phase 'acknowledge)
                           'ok
                           (begin
                             (call-with-output-file effect
                               (lambda (port)
                                 (write-subu8vector bytes 0 (u8vector-length bytes) port)))
                             (call-with-output-file provider-receipt
                               (lambda (port)
                                 (write (list operation-id (.ref receipt 'intent-digest)) port)))
                             (error "test: durable acknowledgement lost"))))
                     journal: journal
                     provider-reader:
                     (lambda (requested)
                       (set! provider-reads (+ provider-reads 1))
                       (check-equal? requested operation-id)
                       (let* ((record (call-with-input-file provider-receipt read))
                              (bytes (make-u8vector 3)))
                         (check-equal?
                          (call-with-input-file effect
                            (lambda (port) (read-subu8vector bytes 0 3 port))) 3)
                         (.o outcome: (if (eq? provider-mode 'unknown) 'unknown 'committed)
                             operation: (if (eq? provider-mode 'operation) "other" (car record))
                             intent-digest: (if (eq? provider-mode 'intent) (digest #\e) (cadr record))
                             payload-digest: (if (eq? provider-mode 'payload) (digest #\e)
                                                 (source-lock-payload-digest bytes))
                             receipt-digest: (if (eq? provider-mode 'receipt) "invalid"
                                                (source-lock-payload-digest
                                                 (string->utf8 (object->string record)))))))))
                   (context (.o approved: #t)))
               (dynamic-wind
                 void
                 (lambda ()
                   (case phase
                     ((restart)
                      (for-each
                       (lambda (key)
                         (check-equal?
                          (.call delivery .deliver! delivery request context key) #f))
                       (list operation-id confirmed))
                      (check-equal? reads 0))
                     ((acknowledge)
                      (let (result (.call delivery .deliver! delivery request context confirmed))
                        (check-equal? (.ref result 'outcome) 'delivered)
                        (check-equal? (.ref result 'result) 'ok)))
                     (else
                      (check-exception
                       (.call delivery .deliver! delivery request context operation-id) Error?)))
                   (let* ((status (.call delivery .delivery-status delivery operation-id))
                          (consumption (.ref status 'consumption)))
                     (check-equal? (.ref status 'phase) 'dispatching)
                     (check-equal? (.ref consumption 'payload-digest)
                                   (source-lock-payload-digest #u8(1 2 3))))
                   (unless (eq? phase 'lost)
                     (let (status (.call delivery .delivery-status delivery confirmed))
                       (check-equal? (.ref status 'phase) 'acknowledged)))
                   (when (eq? phase 'restart)
                     (for-each
                      (lambda (mode)
                        (set! provider-mode mode)
                        (check-equal? (.call delivery .reconcile! delivery operation-id) #f)
                        (let (status (.call delivery .delivery-status delivery operation-id))
                          (check-equal? (.ref status 'phase) 'dispatching)))
                      '(unknown operation intent payload receipt))
                     (set! provider-mode 'committed)
                     (let* ((status (.call delivery .reconcile! delivery operation-id))
                            (observed (.ref status 'provider-observation)))
                       (check-equal? (.ref status 'phase) 'reconciled)
                       (check-equal? (.ref observed 'operation) operation-id)
                       (check-equal? (.ref observed 'payload-digest)
                                     (source-lock-payload-digest #u8(1 2 3))))
                     (check-equal? (.call delivery .reconcile! delivery operation-id) #f)
                     (check-equal? (.call delivery .reconcile! delivery confirmed) #f)
                     (check-equal? provider-reads 6)
                     (check-equal? reads 0))
                   (check-equal? (file-exists? effect) #t)
                   (journal-verify! journal))
                 (lambda () (.call delivery .close! delivery))))))
         (lambda () (journal-close! journal)))))))

(def (make-cedar-restart-suite database effect provider-receipt operation-id confirmed)
  (test-suite "Cedar recovery in a fresh process"
    (test-case "refuse resend and reconcile the stored operation"
      (exercise-durable-delivery database effect provider-receipt operation-id confirmed 'restart))))

(def cedar-delivery-test
  (test-suite "AITIA source-bound dual Cedar delivery"
    (test-case "live source admission fences one actual write"
      (call-with-cedar-host
       (lambda (issuer artifact endpoint path)
        (let ((reads 0) (approval 'missing) (writes 0) (consumption #f))
        (let-values (((host request)
                      (make-cedar-delivery-fixture
                       (lambda (key original proposal)
                         (set! reads (+ reads 1))
                         (case approval
                           ((missing) #f)
                           ((withdraw-at-consume) (and (< reads 4) (digest #\c)))
                           (else (digest #\d)))))))
          (let ((delivery
                 (open-cedar-delivery
                  host issuer endpoint artifact (snapshot)
                  (lambda (bytes receipt)
                    (set! consumption receipt)
                    (call-with-output-file path
                      (lambda (port) (write-subu8vector bytes 0 (u8vector-length bytes) port)))
                    (set! writes (+ writes 1))
                    #f)))
                (context (.o approved: #t)))
            (dynamic-wind
              void
              (lambda ()
                (check-equal? (.call delivery .deliver! delivery request context) #f)
                (check-equal? consumption #f)
                (check-equal? (file-exists? path) #f)
                (set! reads 0)
                (set! approval 'withdraw-at-consume)
                (check-equal? (.call delivery .deliver! delivery request context) #f)
                (check-equal? reads 4)
                (check-equal? (file-exists? path) #f)
                (set! approval 'current)
                (let (receipt (.call delivery .deliver! delivery request context))
                  (check-equal? writes 1)
                  (check-equal? (.ref receipt 'outcome) 'delivered)
                  (check-equal? (.ref receipt 'result) #f)
                  (check-equal? (.ref receipt 'consumption) consumption))
                (check-equal? (.call delivery .deliver! delivery request context) #f)
                (check-equal? writes 1)
                (check-equal? (.ref consumption 'sequence) 1)
                (check-equal? (.ref consumption 'intent-digest) (.ref request 'intent))
                (check-equal? (.ref consumption 'payload-digest)
                              (source-lock-payload-digest #u8(1 2 3)))
                (for-each
                 (lambda (slot) (check-equal? (string-length (.ref consumption slot)) 71))
                 '(source-admission-digest proposal-digest decision-receipt-digest))
                (let (bytes (make-u8vector 3))
                  (check-equal?
                   (call-with-input-file path (lambda (port) (read-subu8vector bytes 0 3 port))) 3)
                  (check-equal? bytes #u8(1 2 3))))
              (lambda () (.call delivery .close! delivery)))))))))
    (test-case "a failing private consume exchange retires the request without delivery"
      (call-with-cedar-host
       (lambda (issuer artifact endpoint path)
         (let ((reads 0) (deliveries 0))
           (let-values (((host request)
                         (make-cedar-delivery-fixture
                          (lambda args
                            (set! reads (+ reads 1))
                            (when (= reads 4) (error "test: source read interrupted"))
                            (digest #\d)))))
             (let ((delivery
                    (open-cedar-delivery
                     host issuer endpoint artifact (snapshot)
                     (lambda (bytes receipt)
                       (set! deliveries (+ deliveries 1)))))
                   (context (.o approved: #t)))
               (dynamic-wind
                 void
                 (lambda ()
                   (check-exception (.call delivery .deliver! delivery request context) Error?)
                   (check-equal? reads 4)
                   (check-equal? (.call delivery .deliver! delivery request context) #f)
                   (check-equal? reads 4)
                   (check-equal? deliveries 0)
                   (check-equal? (file-exists? path) #f))
                 (lambda () (.call delivery .close! delivery)))))))))
    (test-case "the issuer consumes but its reply is truncated before effect delivery"
      (call-with-cedar-host
       (lambda (issuer artifact endpoint path)
         (let ((reads 0) (deliveries 0))
           (let-values (((host request)
                         (make-cedar-delivery-fixture
                          (lambda args
                            (set! reads (+ reads 1))
                            (digest #\d)))))
             (let ((delivery
                    (open-cedar-delivery
                     host (path-expand "dev/proof/scheme/cedar-consume-loss.ss")
                     endpoint artifact (snapshot)
                     (lambda (bytes receipt)
                       (set! deliveries (+ deliveries 1)))))
                   (context (.o approved: #t)))
               (dynamic-wind
                 void
                 (lambda ()
                   (check-exception (.call delivery .deliver! delivery request context) Error?)
                   (check-equal? (call-with-input-file (string-append endpoint ".consumed") read)
                                 'consumed)
                   (check-equal? reads 4)
                   (check-equal? (.call delivery .deliver! delivery request context) #f)
                   (check-equal? reads 4)
                   (check-equal? deliveries 0))
                 (lambda () (.call delivery .close! delivery)))))))))
    (test-case "the durable operation remains fenced under a fresh delivery owner"
      (call-with-temporary-directory "aitia-cedar-dispatch"
        (lambda (root)
          (let ((database (path-expand "delivery.sqlite" root))
                (effect (path-expand "effect.bin" root))
                (provider-receipt (path-expand "provider-receipt" root))
                (operation-id "project/job-42/release")
                (confirmed "project/job-43/release"))
            (for-each
             (lambda (phase)
               (exercise-durable-delivery database effect provider-receipt operation-id confirmed phase))
             '(lost acknowledge))
            (let (reader
                  (open-process
                   (list path: "gxi"
                         stderr-redirection: #t
                         arguments:
                         (list "-:max-heap=512M" "-e"
                               (call-with-output-string
                                (lambda (port)
                                  (write
                                   '(begin
                                      (import :std/test/base "./dev/proof/scheme/cedar-delivery-test.ss")
                                      (let* ((args (cdddr (command-line)))
                                             (suite (apply make-cedar-restart-suite args)))
                                        (parameterize ((current-test-config
                                                        (TestConfig verbosity: 5 capture-output?: #f)))
                                          (exit (if (test-result-ok? (test-suite! suite)) 0 1)))))
                                   port)))
                               database effect provider-receipt operation-id confirmed))))
              (dynamic-wind
                void
                (lambda ()
                  (let loop ()
                    (let (line (read-line reader))
                      (unless (eof-object? line) (displayln line) (loop))))
                  (check-equal? (process-status reader) 0))
                (lambda () (close-port reader))))))))
    (test-case "withdrawal after the journal commit leaves a withheld operation"
      (call-with-cedar-host
       (lambda (issuer artifact endpoint path)
         (let ((journal (journal-open (string-append path ".sqlite")))
               (operation "project/withdrawn/release")
               (withdrawn? #f)
               (deliveries 0)
               (observations 0))
           (dynamic-wind
             void
             (lambda ()
               (journal-cut! journal
                 (lambda (cut event)
                   (when (and (eq? cut 'after-commit)
                              (equal? event (string-append "aitia/cedar/" operation "/dispatching")))
                     (set! withdrawn? #t))))
               (let-values (((host request)
                             (make-cedar-delivery-fixture
                              (lambda args (and (not withdrawn?) (digest #\d))))))
                 (let ((delivery
                        (open-cedar-delivery
                         host issuer endpoint artifact (snapshot)
                         (lambda (bytes receipt) (set! deliveries (+ deliveries 1)))
                         journal: journal
                         provider-reader: (lambda (key) (set! observations (+ observations 1)) #f)))
                       (context (.o approved: #t)))
                   (dynamic-wind
                     void
                     (lambda ()
                       (check-equal? (.call delivery .deliver! delivery request context operation) #f)
                       (check-equal? withdrawn? #t)
                       (let* ((status (.call delivery .delivery-status delivery operation))
                              (consumption (.ref status 'consumption)))
                         (check-equal? (.ref status 'phase) 'withheld)
                         (check-equal? (.ref consumption 'payload-digest)
                                       (source-lock-payload-digest #u8(1 2 3))))
                       (check-equal? (.call delivery .deliver! delivery request context operation) #f)
                       (check-equal? (.call delivery .reconcile! delivery operation) #f)
                       (check-equal? deliveries 0)
                       (check-equal? observations 0)
                       (journal-verify! journal))
                     (lambda () (.call delivery .close! delivery))))))
             (lambda () (journal-close! journal)))))))
    (test-case "a write with a lost acknowledgement leaves consumption evidence and stays spent"
      (call-with-cedar-host
       (lambda (issuer artifact endpoint path)
         (let-values (((host request)
                       (make-cedar-delivery-fixture (lambda args (digest #\d)))))
           (let* ((consumption #f)
                  (delivery
                   (open-cedar-delivery
                    host issuer endpoint artifact (snapshot)
                    (lambda (bytes receipt)
                      (set! consumption receipt)
                      (call-with-output-file path
                        (lambda (port) (write-subu8vector bytes 0 (u8vector-length bytes) port)))
                      (error "test: acknowledgement lost"))))
                  (context (.o approved: #t)))
             (dynamic-wind
               void
               (lambda ()
                 (check-exception (.call delivery .deliver! delivery request context) Error?)
                 (check-equal? (file-exists? path) #t)
                 (check-equal? (.ref consumption 'payload-digest)
                               (source-lock-payload-digest #u8(1 2 3)))
                 (check-equal? (.call delivery .deliver! delivery request context) #f))
               (lambda () (.call delivery .close! delivery))))))))))
