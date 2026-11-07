#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Observe the actual SDK owners; never create a second scheduler.
(import (only-in :std/make make)
        (only-in :gerbil/compiler/base __available-cores))
;; The pinned SDK does not export its settings reader. Observe that exact SPI;
;; this diagnostic never substitutes its algorithm or changes its result.
(extern namespace: std/make gerbil-build-cores)
(export main)
(def (main . arguments)
  (unless (null? arguments) (error "capacity admission has no override" arguments))
  (def selected (getenv "GERBIL_BUILD_CORES" #f))
  (def expected (and selected (string->number selected)))
  (unless (and (exact-integer? expected) (> expected 0))
    (error "runner must declare a positive native compiler capacity" selected))
  (def frontend (gerbil-build-cores))
  (unless (and (= frontend expected) (= __available-cores expected))
    (error "native compiler capacity lost across environment handoff"
           expected frontend __available-cores))
  (displayln "AITIA-NATIVE-CAPACITY-OK declared=" expected
             " make=" frontend " compiler=" __available-cores
             " machine=" (##cpu-count)
             " GAMBOPT=" (getenv "GAMBOPT" "")))
