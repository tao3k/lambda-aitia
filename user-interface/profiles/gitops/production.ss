;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o))
(export make-production-profile)
(def (make-production-profile gitops)
  (.o (:: self (.get gitops profile)) name: 'production
    environment: 'production
    event: 'workflow-dispatch
    target-ref: "production"
    required-checks: '(release-authority signed-provenance)
    reconciliation: 'protected
    next-profile: 'complete
      .matches?: ((.get gitops match-change) (.get self event) (.get self target-ref))))
