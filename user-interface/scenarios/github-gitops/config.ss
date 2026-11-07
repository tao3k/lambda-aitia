;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o) "objects.ss")
(export make-github-gitops-scope)

(def (make-github-gitops-scope gitops delivery nasa)
  (.o scenario: (make-github-gitops-scenario delivery nasa)
      change: (lambda (event repository revision source-ref target-ref pull-request)
                ((.get gitops change) 'github event repository revision
                                     source-ref target-ref pull-request))
      check: (.get gitops check)
      evaluate: (.get gitops evaluate)))
