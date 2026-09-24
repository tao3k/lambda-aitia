;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/error Error?)
        (only-in :gerbil/core path-expand)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil/core string-suffix?)
        (only-in :poo-flow/src/feature-system/interface
                 sources-lock-freeze
                 write-sources-lock-module)
        (only-in :poo-flow/src/modules/standards/interface
                 poo-flow-standard-digest
                 poo-flow-standard-materialization-receipt-valid?
                 poo-flow-standard-resolution-receipt-bundle
                 poo-flow-standard-resolution-receipt-valid?
                 poo-flow-standard-validate
                 poo-flow-standard-validation-closure?)
        :poo-flow/lambda-aitia/modules/sdlc/standards/sources
        :poo-flow/lambda-aitia/modules/sdlc/standards/interface)

(export nasa-standard-provider-test)

(def (lambda-aitia-root)
  (if (file-exists? "modules/sdlc/standards/sources/chapter2.html")
    "."
    "packages/lambda-aitia"))

(def (provider-phase phase)
  (displayln "[lambda-aitia-test] module=sdlc provider=nasa-7150-2d phase=" phase)
  (force-output))

(def (read-lambda-aitia-source relative-path)
  (call-with-input-file
   (path-expand relative-path (lambda-aitia-root))
   read-all-as-string))

(def nasa-standard-provider-test
  (test-suite
   "NASA NPR 7150.2D Standards Core Provider"
   (test-case
    "Standards family shares the public NASA SDLC identity"
    (check-equal? (.ref Nasa7150_2DStandardFamily 'identity)
                  "nasa/sdlc/npr-7150.2")
    (check-equal? (.ref Nasa7150_2DStandardFamily 'semantic-kind) 'sdlc))
   (test-case
    "declares all immutable NASA source facts through Sources Lock Feature"
    (check-equal? (.ref Nasa7150_2DSourcesLock 'feature-id) 'sources-lock)
    (check-equal? (.ref Nasa7150_2DSourcesLock 'entry-count) 6)
    (check-equal? (.ref Nasa7150_2DSourcesLock 'byte-count) 197510))
   (test-case
    "source.lock.ss is the deterministic product of declarations and bytes"
    (let* ((generated-lock
            (sources-lock-freeze
             "lambda-aitia/nasa/sdlc/npr-7150.2/D/sources"
             "2022-03-08"
             Nasa7150_2DSources
             read-lambda-aitia-source
             '((authority . nasa-nodis)
               (standard . "NPR 7150.2D")
               (effective . "2022-03-08"))))
           (generated-source
            (call-with-output-string
             (lambda (port)
               (write-sources-lock-module
                port 'Nasa7150_2DSourcesLock generated-lock))))
           (checked-in-source
            (read-lambda-aitia-source
             "modules/sdlc/standards/source.lock.ss")))
      (check-equal? (.ref generated-lock 'digest)
                    (.ref Nasa7150_2DSourcesLock 'digest))
      (check-equal? (.ref generated-lock '.valid?) #t)
      (check-equal? generated-source checked-in-source)))
   (test-case
    "resolves one exact edition without loading six source artifacts"
    (let* ((source-provider
            (begin
              (provider-phase 'source-provider-start)
              (nasa-7150-2d-local-source-provider (lambda-aitia-root))))
           (module
            (begin
              (provider-phase 'module-start)
              (let (value (nasa-7150-2d-standards-module source-provider))
                (provider-phase 'module-complete)
                value)))
           (receipt
            (begin
              (provider-phase 'resolve-start)
              (nasa-7150-2d-resolve
               module (poo-flow-standard-digest 'nasa-test-terminology))))
           (bundle
            (begin
              (provider-phase 'resolve-complete)
              (poo-flow-standard-resolution-receipt-bundle receipt))))
      (check-equal? (poo-flow-standard-resolution-receipt-valid? receipt) #t)
      (check-equal? (.ref bundle 'edition-count) 1)
      (check-equal? (.ref bundle 'artifact-count) 6)
      (check-equal? (.ref bundle 'byte-count) 197510)
      (check-equal? (.ref bundle 'runtime-executed?) #f)))
   (test-case
    "materializes exact checked-in NODIS bytes only on explicit demand"
    (let* ((module
            (nasa-7150-2d-standards-module
             (nasa-7150-2d-local-source-provider (lambda-aitia-root))))
           (receipts (nasa-7150-2d-materialize-sources module)))
      (check-equal? (length receipts) 6)
      (check-equal?
       (andmap poo-flow-standard-materialization-receipt-valid? receipts)
       #t)
      (check-equal?
       (apply +
              (map (lambda (receipt)
                     (.ref (.ref receipt 'load-receipt) 'loaded-bytes))
                   receipts))
       197510)))
   (test-case
    "rejects a changed source before artifact materialization"
    (let* ((source-provider-value
            (nasa-7150-2d-local-source-provider (lambda-aitia-root)))
           (read-source-value (.ref source-provider-value '.read-source))
           (changed-source-provider
            (.o (:: @ source-provider-value)
                identity: "lambda-aitia/nasa-source/changed-fixture"
                .read-source:
                (lambda (relative-path)
                  (let (payload (read-source-value relative-path))
                    (if (string-suffix? "chapter2.html" relative-path)
                      (string-append payload "changed")
                      payload)))))
           (module
            (nasa-7150-2d-standards-module changed-source-provider)))
      (check-exception
       (nasa-7150-2d-materialize-sources module)
       Error?)))
   (test-case
    "projects all 130 reviewed requirements into one provider-neutral closure"
    (let* ((module
            (nasa-7150-2d-standards-module
             (nasa-7150-2d-local-source-provider (lambda-aitia-root))))
           (closure
            (nasa-7150-2d-validation-closure
             module 'sdlc-project
             (poo-flow-standard-digest 'nasa-project-snapshot)))
           (provider (.ref (.ref module 'providers) 'nasa)))
      (check-equal? (poo-flow-standard-validation-closure? closure) #t)
      (check-equal? (length (.ref closure 'constraints)) 130)
      (check-equal? (.ref closure 'runtime-executed?) #f)
      (check-exception
       (poo-flow-standard-validate provider closure (.o))
       Error?)))))
