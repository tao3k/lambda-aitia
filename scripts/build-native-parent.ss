#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Aitia owns demand; Core traverses imports; the parent owns compiler options.
(import (for-syntax
          (only-in :gerbil/tools/gxpkg pkg-root-dir)
          (only-in :yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source!
   (path-expand "github.com/tao3k/agentic-ai-lab" (pkg-root-dir)) 'agentic-ai-lab))
(import (only-in :gerbil/tools/gxpkg pkg-root-dir)
        (only-in :std/source this-source-file)
        (only-in :std/make make)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :yuanxu/module-system/building/source-package register-module-build-source!)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :yuanxu/module-system/building/artifacts
                 repair-build-products! require-build-products!)
        (only-in :agentic-ai-lab/build-spec agentic-ai-lab-build-spec)
        (only-in "../testing-observer.ss" lambda-aitia-selected-test-files)
        (only-in "../build.ss" lambda-aitia-native-spec)
        (only-in "../integration-build.ss" lambda-aitia-integration-spec)
        (only-in "./check-native-products.ss" native-library-targets native-library-identities))
;; The pinned v0.19 SDK owns metadata generation but does not export this
;; metadata-only SPI. Bind that actual SDK procedure; never reproduce its schema.
;; An SDK change that removes it fails this entry instead of manufacturing data.
(extern namespace: gerbil/tools/gxpkg pkg-manifest!)
(def (main . arguments)
  (unless (null? arguments) (error "native parent demand has no alternate selectors" arguments))
  (def root (path-normalize (path-expand ".." (path-directory (this-source-file)))))
  (def parent (path-expand "github.com/tao3k/agentic-ai-lab" (pkg-root-dir)))
  (register-module-build-source! parent 'agentic-ai-lab)
  ;; Native version metadata is input provenance, not whole-package completion.
  (pkg-manifest! "github.com/tao3k/agentic-ai-lab")
  (def libraries
    (parameterize ((current-directory root))
      (native-library-targets
       (append (lambda-aitia-native-spec) (lambda-aitia-integration-spec)))))
  (def tests
    (parameterize ((current-directory root)) (lambda-aitia-selected-test-files "t")))
  (def entries
    (append
     (map (lambda (target)
            (let (file (cadr target))
              (path-expand (if (string-suffix? ".ss" file) file (string-append file ".ss")) root)))
          libraries)
     (map (lambda (file) (path-expand file root)) tests)))
  (def prefix "agentic-ai-lab/")
  (def seen (make-hash-table-eq))
  (def demand (make-hash-table-eq))
  (for-each
   (lambda (file)
     (for-each-build-module (core-import-module file)
       (lambda (context)
         (let* ((identity (expander-context-id context))
                (name (and (symbol? identity) (symbol->string identity))))
           (when (and name (string-prefix? prefix name)
                      (not (string-prefix? "agentic-ai-lab/lambda-aitia/" name))
                      (not (string-prefix? "agentic-ai-lab/dev/" name)))
             (hash-put! demand identity
               (string-append (substring name (string-length prefix) (string-length name)) ".ss")))))
       seen)) entries)
  ;; Development testing support remains an explicit later CI demand. The
  ;; production parent's own source projection supplies all special FFI options.
  (def spec
    (parameterize ((current-directory parent))
      (agentic-ai-lab-build-spec (hash-values demand))))
  (def identities (native-library-identities "agentic-ai-lab" (native-library-targets spec)))
  (def libdir (path-expand "lib" (gerbil-path)))
  (displayln "AITIA-PARENT-DEMAND entries=" (length entries)
             " testFiles=" (length tests) " parentUnits=" (length identities))
  (force-output)
  (repair-build-products! identities libdir)
  (make spec srcdir: parent)
  (require-build-products! identities libdir)
  (displayln "AITIA-NATIVE-PARENT-BUILD-OK units=" (length identities)))
