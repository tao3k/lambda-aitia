;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .o .def))
(export OpenGitOpsProfile)

(def GitOpsProfile
  (.o gitops-profile?: #t
      identity: "gitops/profile"
      owner: 'lambda-aitia
      name: 'gitops
      environment: 'unbound
      event: 'reconciliation
      target-ref: "unbound"
      required-checks: '()
      reconciliation: 'continuous
      next-profile: 'complete
      principles: '()
      source-url: #f
      runtime-executed: #f
      .matches?: (lambda (_change) #f)))

(.def (OpenGitOpsProfile @ GitOpsProfile)
  ;; The public identity is stable; standard revisions belong in evidence,
  ;; not in Scheme/Python namespaces or exported binding names.
  (identity "open-gitops")
  (name 'open-gitops)
  (principles '(declarative versioned-and-immutable pulled-automatically
                continuously-reconciled))
  (source-url "https://opengitops.dev/"))
