#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json u8vector->json JSONReadOptions current-json-read-options))

;; Test-only relay. Preserve the wire bytes until the issuer reports a real
;; consumption, then forward its frame header without the body.
(def (read-frame port)
  (let* ((header (make-u8vector 4))
         (count (read-subu8vector header 0 4 port)))
    (cond
     ((zero? count) #f)
     ((not (= count 4)) (error "Incomplete Cedar relay header"))
     (else
      (let (size (let loop ((i 0) (n 0))
                   (if (= i 4) n (loop (+ i 1) (+ (* 256 n) (u8vector-ref header i))))))
        (unless (<= 1 size 1048576) (error "Invalid Cedar relay frame length"))
        (let (body (make-u8vector size))
          (unless (= (read-subu8vector body 0 size port) size)
            (error "Incomplete Cedar relay frame"))
          (cons header body)))))))

(def (forward-frame frame port)
  (write-subu8vector (car frame) 0 4 port)
  (write-subu8vector (cdr frame) 0 (u8vector-length (cdr frame)) port)
  (force-output port))

(def (relay arguments)
  (let* ((input (current-input-port))
         (output (current-output-port))
         (issuer (open-process (list path: (getenv "AITIA_CEDAR_ISSUER") arguments: arguments))))
    (input-port-timeout-set! issuer 12.)
    (output-port-timeout-set! issuer 12.)
    (dynamic-wind
      void
      (lambda ()
        (let loop ()
          (let (request (read-frame input))
            (when request
              (forward-frame request issuer)
              (let* ((reply (or (read-frame issuer) (error "Issuer closed before replying")))
                     (message (parameterize ((current-json-read-options
                                              (JSONReadOptions object-as-hash: #t)))
                                (u8vector->json (cdr reply)))))
                (if (equal? (hash-ref message "status") "consumed")
                    (begin
                      (close-output-port issuer)
                      (unless (= (process-status issuer) 0) (error "Issuer did not exit cleanly"))
                      (call-with-output-file (string-append (car arguments) ".consumed")
                        (lambda (port) (write 'consumed port)))
                      (write-subu8vector (car reply) 0 4 output)
                      (force-output output))
                    (begin (forward-frame reply output) (loop))))))))
      (lambda () (close-port issuer)))))

(relay (cddr (command-line)))
