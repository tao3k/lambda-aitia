;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test "sdlc-selection-fixture.ss")
(export sdlc-npr-selection-test)

(def sdlc-npr-selection-test
  (test-suite "SDLC NPR selection"
    (test-case "NPR 7150.2 cannot be selected as an SDLC feature"
      (check-unknown-sdlc-feature! '+npr-7150.2))))
