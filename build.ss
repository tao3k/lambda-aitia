#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Native Lambda Aitia build.  ASP owns closure projection and std/make owns
;;; currentness, scheduling, and clean.

(import (only-in :std/build-script defbuild-script)
        (only-in :asp-gerbil-scheme/building-api
                 asp-gerbil-scheme-package-spec!
                 asp-gerbil-scheme-library-package-prototype))

(def +lambda-aitia-public-entry-modules+
  '("interface.ss"
    "bindings/c/aitia-contract.ss"
    "modules/ADR/interface.ss"
    "modules/assurance/interface.ss"
    "modules/gitops/interface.ss"
    "modules/sdlc/interface.ss"
    "modules/sdlc/standards/interface.ss"
    "user-interface/profiles/github/actions.ss"
    "user-interface/profiles/gitops/dev.ss"
    "user-interface/profiles/gitops/staging.ss"
    "user-interface/profiles/gitops/production.ss"
    "user-interface/profiles/sdlc/nasa-7150-2d.ss"))

(asp-gerbil-scheme-package-spec!
 (lambda-aitia-package @ asp-gerbil-scheme-library-package-prototype)
 (spec lambda-aitia-native-spec)
 (public-entry-modules +lambda-aitia-public-entry-modules+)
 (extra-spec
  '((gxc: "testing-interface")
    (gxc: "testing-observer"))))

(defbuild-script (lambda-aitia-native-spec))
