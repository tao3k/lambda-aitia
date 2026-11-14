;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        "objects.ss" "dev.ss" "staging.ss" "production.ss")
(export make-delivery-profile-scope)

(def (make-delivery-profile-scope gitops)
  (let ((dev-profile (make-dev-profile gitops))
        (staging-profile (make-staging-profile gitops))
        (production-profile (make-production-profile gitops)))
    (.o dev: dev-profile staging: staging-profile production: production-profile
        profile-module: (make-delivery-profile-module dev-profile staging-profile production-profile))))
