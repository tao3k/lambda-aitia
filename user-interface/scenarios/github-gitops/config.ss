;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o) "objects.ss")
(export make-github-gitops-scope)

(def (make-github-gitops-scope delivery nasa)
  (.o scenario: (make-github-gitops-scenario delivery nasa)))
