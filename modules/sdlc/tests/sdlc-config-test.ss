;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/contribution/objects admit-contributions)
        (only-in "../../../init.ss" lambda-aitia.init.exports)
        "sdlc-selection-fixture.ss")
(export sdlc-config-test)

(def sdlc-config-test
  (test-suite "SDLC init selection projection"
    (test-case "the selected SDLC scope is standard-free"
      (let* ((sdlc (.get lambda-aitia.init.exports modules sdlc))
             (contribution (.get sdlc default-contribution)))
        (check-equal? (.get sdlc profile standards) '())
        (check-equal? (.get contribution profile standards) '())
        (check-equal? (.get (admit-contributions (list contribution) '()) accepted?) #t)))
    (test-case "NASA cannot be selected as an SDLC feature"
      (check-unknown-sdlc-feature! '+nasa))))
