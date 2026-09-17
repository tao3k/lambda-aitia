#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Optional application and native-binding closure. The SDLC/GitOps core build
;;; remains independent; this adapter compiles final composition before FFI.
(import (only-in :std/build-script defbuild-script)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))

(def +lambda-aitia-native-ffi-spec+
  (cond-expand
   (darwin
    '(gxc: "bindings/c/aitia-native"
           "-ld-options" "-Wl,-undefined,dynamic_lookup"))
   (else
    '(gxc: "bindings/c/aitia-native"))))

(asp-gerbil-scheme-package-spec!
 (lambda-aitia-integration-package @ asp-gerbil-scheme-library-package-prototype)
 (spec lambda-aitia-integration-spec)
 (public-entry-modules '("user-interface/config.ss"))
 (extra-spec `(,+lambda-aitia-native-ffi-spec+)))

(defbuild-script (lambda-aitia-integration-spec))
