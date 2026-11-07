#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Production roots use Core's existing import closure and official Make.
(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in :yuanxu/module-system/building/source-package register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file))
                                 'lambda-aitia))

(import (only-in :clan/poo/object .get)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in :yuanxu/module-system/building/products current-build-module-roots)
        (only-in "./init.ss" lambda-aitia.init.exports))

;;; Installation requests no business roots. Core derives actual role/import
;;; closure for explicit --modules requests; no second source list lives here.
(def (lambda-aitia-spec)
  (let ((roots (or (current-build-module-roots) '()))
        (spec (.get lambda-aitia.init.exports std-make-spec)))
    (parameterize ((current-build-module-roots roots))
      (spec '()))))

;; Preserve the existing Darwin cross-module specialization restriction.
(cond-expand
 (darwin (defbuild-script (lambda-aitia-spec) optimize: #f))
 (else (defbuild-script (lambda-aitia-spec))))
