;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :yuanxu/module-system/selection/syntax
                 agentic-ai-lab-modules!)
        :yuanxu/module-system/selection/objects
        (only-in :clan/poo/object .ref)
        (only-in :agentic-ai-lab/core/contribution/objects admit-contributions)
        :agentic-ai-lab/lambda-aitia/modules/sdlc/config)
(def (selected . flags)
  (sdlc-config (agentic-ai-lab-user-module-selection 'custom 'sdlc flags)))
(export sdlc-config-test)
(def sdlc-config-test
  (test-suite "SDLC init selection projection"
    (test-case "custom SDLC module is standard-free"
      (let* ((bundles (agentic-ai-lab-modules!
                       :custom (sdlc @ "../lambda-aitia/modules/sdlc")))
             (selection (caar bundles))
             (contribution (sdlc-config selection))
             (standards (.ref (.ref contribution 'profile) 'standards)))
        (check-equal? (agentic-ai-lab-user-module-selection-entrypoint selection)
                      "../lambda-aitia/modules/sdlc/interface.ss")
        (check-equal? standards '())
        (check-equal? (.ref (admit-contributions (list contribution) '()) 'accepted?) #t)))
    (test-case "no feature means no NASA selection"
      (check-equal? (.ref (.ref (selected) 'profile) 'standards) '()))
    (test-case "unsupported features and unrelated modules are rejected"
      (check-exception (selected '+nasa) Error?)
      (check-exception (selected '+npr-7150.2) Error?)
      (check-exception (sdlc-config (agentic-ai-lab-user-module-selection 'custom 'other '())) Error?))))
