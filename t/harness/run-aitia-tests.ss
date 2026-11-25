;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/misc/process run-process)
        (only-in :std/list/list partition)
        (only-in :clan/poo/object .get .call)
        (only-in :std/source this-source-file)
        (only-in :tao3k/yuanxu/module-system/source/directory module-directory-context)
        (only-in :tao3k/yuanxu/module-system/building/test-projection admit-module-test-layout!)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))
(export main default-test-files admit-aitia-test-layout!)

(def (admit-aitia-test-layout!)
  (def init (path-normalize (path-expand "../../init.ss" (path-directory (this-source-file)))))
  (def context
    (module-directory-context init
      (lambda (_) (error "test roster must leave publications cold"))
      publication-prepares-source?: #t))
  (def tests
    (.call (.get lambda-aitia.init.exports tests qualification)
      .select (.get context loader-roots)))
  (def files (.get tests spec))
  ((.get tests admit-current))
  (admit-module-test-layout! context files
    require-owner-tests?: #f
    independent-directories:
    '("fixtures" "harness" "integration" "library" "qualification" "support")))

(def (local-path root file)
  (def normalized (path-normalize file))
  (if (string-prefix? root normalized)
    (substring normalized (string-length root) (string-length normalized))
    file))

(def (directory-tests dir)
  (list-sort string<?
    (map (lambda (name) (string-append dir "/" name))
         (filter (cut string-suffix? "-test.ss" <>) (directory-files dir)))))

(def (grouped-tests dir)
  (foldr append '()
    (map (lambda (group) (directory-tests (string-append dir "/" group)))
         (list-sort string<? (directory-files dir)))))

(def (default-test-files)
  (def root (path-normalize (current-directory)))
  (append (list-sort string<? (map (cut local-path root <>) (admit-aitia-test-layout!)))
          (list-sort string<? (grouped-tests "t/library"))
          (list-sort string<? (directory-tests "t/integration"))))

(def (expand-target target)
  (def root (path-normalize (current-directory)))
  (cond
    ((string-prefix? "--module=" target)
     (let* ((owner (string->symbol (substring target 9 (string-length target))))
            (selection (.call (.get lambda-aitia.init.exports tests) .select (list owner)))
            (files (.get selection spec)))
       ((.get selection admit-current))
       (unless (pair? files)
         (error "no tests declared by selected Aitia module" owner))
       (list-sort string<? (map (cut local-path root <>) files))))
    ((and (file-exists? target)
          (eq? (file-info-type (file-info target)) 'directory))
     (directory-tests (path-strip-trailing-directory-separator target)))
    ((file-exists? target)
     (list target))
    (else
     (error "unknown Lambda Aitia test target" target))))

;; Bounded heap selection: default 512 MiB; catalog/SDLC-graph suites use 2 GiB.
(def (large-heap-test? file)
  (let (base (path-strip-directory file))
    (or (string-prefix? "nasa-" base)
        (member base '("sdlc-test.ss"
                       "sdlc-trace-test.ss"
                       "sdlc-config-test.ss"
                       "sdlc-npr-selection-test.ss"
                       "source-admission-test.ss")))))

(def (independent-test? file)
  (let (base (path-strip-directory file))
    (member base '("job-retirement-impact-test.ss"
                   "aitia-operations-test.ss"
                   "decision-preflight-test.ss"
                   "source-admission-test.ss"))))

(def (vm-for-file default-vm file)
  (if (large-heap-test? file) "-:max-heap=2G" default-vm))

;; Group same-directory, same-heap-profile files (up to 8 per batch), keeping
;; independent tests isolated so one gerbil test process owns each batch.
(def (test-batches default-vm files)
  (let loop ((remaining files) (batch '()) (batch-vm #f) (size 0) (batches '()))
    (match remaining
      ([] (reverse (if (null? batch)
                     batches
                     (cons (cons batch-vm (reverse batch)) batches))))
      ([file . rest]
       (let (vm (vm-for-file default-vm file))
         (cond
           ((independent-test? file)
            (let (flushed (if (null? batch)
                            batches
                            (cons (cons batch-vm (reverse batch)) batches)))
              (loop rest '() #f 0 (cons (cons vm (list file)) flushed))))
           ((and (pair? batch)
                 (or (= size 8)
                     (not (equal? vm batch-vm))
                     (not (equal? (path-directory file) (path-directory (car batch))))))
            (loop remaining '() #f 0 (cons (cons batch-vm (reverse batch)) batches)))
           (else
            (loop rest (cons file batch) vm (1+ size) batches))))))))

(def (order-by-heap default-vm files)
  (let-values (((large ordinary)
                (partition large-heap-test? files)))
    (append large ordinary)))

(def (run-batch vm file-budget files)
  (displayln "AITIA-TEST-BATCH " vm " " (string-join files " "))
  (force-output)
  (def command ["timeout" "--foreground" "--signal=TERM" "--kill-after=5s" file-budget
                "gerbil" vm "test" . files])
  (def expected (filter (cut string-suffix? "-test.ss" <>) files))
  (def harness-receipt (string-append "HARNESS-OK " (object->string files)))
  (def status #f)
  (def module-ok? #f)
  (def harness-ok? #f)
  (def final-ok? #f)
  (def failed? #f)
  (run-process command stdin-redirection: #f stderr-redirection: #t
    check-status: (lambda (result _) (set! status result))
    coprocess:
    (lambda (port)
      (let next ((line (read-line port)))
        (unless (eof-object? line)
          (displayln line)
          (force-output)
          (cond
            ((string-prefix? "MODULE-OK " line)
             (set! module-ok? #t)
             (set! expected
               (filter (lambda (file)
                         (not (string=? line (string-append "MODULE-OK " file))))
                       expected)))
            ((string=? harness-receipt line) (set! harness-ok? #t))
            ((and harness-ok? (string=? line "OK")) (set! final-ok? #t))
            ((or (ormap (lambda (marker) (string-prefix? marker line))
                        '("ERROR CASE" "ERROR CHECK" "ERROR HARNESS" "ERROR MODULE"))
                 (string-contains line "Heap overflow")
                 (string-contains line "Stack overflow"))
             (set! failed? #t)))
          (next (read-line port))))))
  (def ok? (and (eqv? status 0) module-ok? harness-ok? final-ok? (null? expected) (not failed?)))
  (unless ok?
    (displayln "AITIA-TEST-BATCH-FAILED status=" status " missing-module-receipts=" expected)
    (force-output))
  ok?)

(def (main vm file-budget . paths)
  (def files
    (if (null? paths)
      (default-test-files)
      (foldr append '() (map expand-target paths))))
  (def batches
    (test-batches vm (order-by-heap vm files)))
  (def failed? #f)
  (for-each (lambda (entry)
              (unless (run-batch (car entry) file-budget (cdr entry))
                (set! failed? #t)))
            batches)
  (when failed? (exit 1)))
