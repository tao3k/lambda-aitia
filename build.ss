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

(import (only-in :std/build-script defbuild-script)
        (only-in :std/source this-source-file)
        (only-in "./init.ss" std-make-spec))

;; The selected Module Graph owns every source target, including the runtime
;; entrypoints declared by SDLC. Gerbil owns command dispatch.
(cond-expand
 (darwin (defbuild-script std-make-spec optimize: #f))
 (else (defbuild-script std-make-spec)))
