;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        :poo-flow/src/module-system/load
        :poo-flow/src/module-system/declaration/interface
        :poo-flow/src/module-system/contribution/interface
        :poo-flow/lambda-aitia/modules/sdlc/config)
(def (selected . flags)
  (sdlc-config (poo-flow-user-module-selection 'custom 'sdlc flags)))
(export sdlc-config-test)
(def sdlc-config-test
  (test-suite "SDLC init selection projection"
    (test-case "custom SDLC module is standard-free"
      (let* ((bundles (poo-flow-modules!
                       :custom (sdlc @ "../lambda-aitia/modules/sdlc")))
             (selection (caar bundles))
             (contribution (sdlc-config selection))
             (standards (.ref (.ref contribution 'profile) 'standards)))
        (check-equal? (poo-flow-user-module-selection-entrypoint selection)
                      "../lambda-aitia/modules/sdlc/interface.ss")
        (check-equal? standards '())
        (check-equal? (.ref (admit-contributions (list contribution) '()) 'accepted?) #t)))
    (test-case "no feature means no NASA selection"
      (check-equal? (.ref (.ref (selected) 'profile) 'standards) '()))
    (test-case "unsupported features and unrelated modules are rejected"
      (check-exception (selected '+nasa) Error?)
      (check-exception (selected '+npr-7150.2) Error?)
      (check-exception (sdlc-config (poo-flow-user-module-selection 'custom 'other '())) Error?))))
