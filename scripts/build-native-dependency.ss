#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Use the SDK's native package API. A CI build does not request editor TAGS.
(import (only-in :gerbil/tools/gxpkg pkg-build with-pkg-build-env))
;; v0.19 exposes install/update/build publicly, but its source-only acquisition
;; procedure is an SDK SPI. Bind the real owner rather than reproduce Git/tag
;; handling or trigger recursive compilation during source registration.
(extern namespace: gerbil/tools/gxpkg pkg-fetch)
(def (main manifest repository (operation "build"))
  (unless (member operation '("build" "register"))
    (error "unknown native dependency operation" operation))
  (let* ((metadata (call-with-input-file manifest read))
         (pins (filter (lambda (dependency)
                         (string-prefix? (string-append repository "@") dependency))
                       (pgetq depend: metadata '()))))
    (unless (= (length pins) 1)
      (error "Aitia must declare exactly one pinned native dependency" pins))
    (with-pkg-build-env
      (pkg-fetch repository
                 (substring (car pins) (+ (string-length repository) 1)
                            (string-length (car pins))))
      ;; pkg-build writes the real native manifest and executes the package's
      ;; own build entry. Only the unrelated global editor-index pass is absent.
      (when (equal? operation "build") (pkg-build repository)))
    (displayln (if (equal? operation "build")
                 "AITIA-NATIVE-DEPENDENCY-BUILD-OK pin="
                 "AITIA-NATIVE-DEPENDENCY-REGISTER-OK pin=")
               (car pins))))
