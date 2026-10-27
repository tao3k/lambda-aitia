#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The package's native spec owns the units; Core owns phase completion.
;;; Never parse SSI or require dynamic objects for executable-only targets.
(import (only-in :yuanxu/module-system/building/artifacts
                 require-build-products! repair-build-products!))
(def (main operation prefix spec-path)
  (unless (member operation '("check" "invalidate-incomplete"))
    (error "unknown native product operation" operation))
  (let* ((spec (call-with-input-file spec-path read))
         (identities
          (filter-map
           (lambda (target)
             (and (pair? target) (eq? (car target) gxc:)
                  (string->symbol (string-append prefix "/" (cadr target))))) spec))
         (libdir (path-expand "lib" (gerbil-path))))
    (when (null? identities) (error "native spec contains no library units" spec-path))
    (when (equal? operation "invalidate-incomplete")
      ;; Invalidate only Core-owned static markers. The native package build
      ;; retains its source receipts, compiler options and actual compilation.
      (repair-build-products! identities libdir))
    (require-build-products! identities libdir)
    (displayln "NATIVE-PRODUCTS-OK package=" prefix " units=" (length identities))))
