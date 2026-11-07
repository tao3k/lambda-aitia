#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in "./testing-observer.ss" run-observed-module-tests)
        (only-in "./init.ss" lambda-aitia.init.exports))

(let (owners (cddr (command-line)))
  (when (null? owners)
    (error "usage: run-module-test.ss <module-id> ..."))
  (run-observed-module-tests lambda-aitia.init.exports (map string->symbol owners)))
