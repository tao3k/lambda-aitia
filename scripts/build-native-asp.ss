#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Use the SDK's native package API. A CI build does not request editor TAGS.
(import (only-in :gerbil/tools/gxpkg pkg-update pkg-build with-pkg-build-env))
(def (main manifest)
  (let* ((metadata (call-with-input-file manifest read))
         (pins (filter (lambda (dependency)
                         (string-prefix? "github.com/tao3k/asp-gerbil-scheme@" dependency))
                       (pgetq depend: metadata '()))))
    (unless (= (length pins) 1)
      (error "Aitia must declare exactly one pinned native ASP requirement" pins))
    (with-pkg-build-env
      (pkg-update (car pins))
      ;; pkg-build writes the real native manifest and executes the package's
      ;; own build entry. Only the unrelated global editor-index pass is absent.
      (pkg-build "github.com/tao3k/asp-gerbil-scheme"))
    (displayln "AITIA-NATIVE-ASP-BUILD-OK pin=" (car pins))))
