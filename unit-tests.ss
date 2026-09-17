#!/usr/bin/env gxi
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :asp-gerbil-scheme/testing-runner-api
                 init-profiled-test-environment!)
        (only-in "testing-interface.ss"
                 +lambda-aitia-testing-interface+))

(init-profiled-test-environment! +lambda-aitia-testing-interface+)
