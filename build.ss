#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Production roots use Core's existing import closure and official Make.
(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in :tao3k/yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file))
                                 'lambda-aitia))

(import (only-in :std/build-script defbuild-script)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/object .call .get)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :tao3k/yuanxu/module-system/building/source-package call-with-build-input-path)
        (only-in :tao3k/yuanxu/module-system/building/products
                 build-output-directory current-build-output-directory current-build-source-directory))
(export main aitia-build-projection aitia-make)

;; These entrypoints belong to the package. SDLC owns its Module projection.
(def aitia-program-targets '("bindings/operations" "rust/scheme/program"))
(def (aitia-build-projection)
  (def entry (this-source-file))
  (def root (path-directory entry))
  (yuanxu-project-source-spec (path-expand "init.ss" root)
    aitia-program-targets root entry))

(def (aitia-make spec . arguments)
  (def entry (this-source-file))
  (def root (or (current-build-source-directory) (path-directory entry)))
  (let ()
    (def (this-source-file)
      (path-expand (path-strip-directory entry) root))
    (cond-expand
     (darwin
      (defbuild-script spec libdir: (current-build-output-directory) optimize: #f))
     (else
      (defbuild-script spec libdir: (current-build-output-directory))))
    (call-with-build-input-path (build-output-directory)
      (lambda () (apply main arguments)) make-source: root)))

(def (build-package arguments)
  (def projection (aitia-build-projection))
  (def (make-targets) (apply aitia-make (.get projection spec) arguments))
  (match arguments
    (["clean"] (.call projection .with-clean-outputs make-targets))
    (["spec"] (make-targets))
    (else (.call projection .with-compiler-inputs make-targets))))

(def (main . arguments)
  (if (equal? arguments '("meta"))
      (aitia-make '() "meta")
      (build-package arguments)))
