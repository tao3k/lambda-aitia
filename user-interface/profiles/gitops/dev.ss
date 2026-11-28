;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o))
(export make-dev-profile)
(def (make-dev-profile gitops)
  (.o (:: self (.get gitops profile)) name: 'dev
    environment: 'dev
    event: 'pull-request
    target-ref: "develop"
    required-checks: '(commit-policy build unit-test)
    reconciliation: 'automatic
    next-profile: 'staging
      .matches?: ((.get gitops match-change) (.get self event) (.get self target-ref))))
