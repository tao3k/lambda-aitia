;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o))
(export make-staging-profile)
(def (make-staging-profile gitops)
  (.o (:: self (.get gitops profile)) name: 'staging
    environment: 'staging
    event: 'push
    target-ref: "develop"
    required-checks: '(integration-test security-review)
    reconciliation: 'automatic
    next-profile: 'production
      .matches?: ((.get gitops match-change) (.get self event) (.get self target-ref))))
