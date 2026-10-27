#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The package's native spec owns the units; Core owns phase completion.
;;; Never parse SSI or require dynamic objects for executable-only targets.
(import (only-in :std/make make)
        (only-in :yuanxu/module-system/building/artifacts
                 require-build-products! repair-build-products!))
(def (main operation prefix spec-path . source-root)
  (unless (member operation '("check" "repair"))
    (error "unknown native product operation" operation))
  (let* ((spec (call-with-input-file spec-path read))
         (libraries (filter (lambda (target)
                              (and (pair? target) (eq? (car target) gxc:))) spec))
         (identities (map (lambda (target)
                            (string->symbol (string-append prefix "/" (cadr target))))
                          libraries))
         (libdir (path-expand "lib" (gerbil-path))))
    (when (null? identities) (error "native spec contains no library units" spec-path))
    (when (equal? operation "repair")
      (unless (= (length source-root) 1)
        (error "native library repair requires the actual source package" source-root))
      ;; Core owns interrupted-unit invalidation. SDK make consumes the original
      ;; declarations/options; executable delivery is not this library demand.
      ;; This operation does not issue an ASCENT package/publication receipt.
      (repair-build-products! identities libdir)
      (make libraries srcdir: (car source-root)
            optimize: (not (equal? (getenv "GERBIL_BUILD_OPTIMIZE" "1") "0"))))
    (require-build-products! identities libdir)
    (displayln "NATIVE-PRODUCTS-OK package=" prefix " units=" (length identities))))
