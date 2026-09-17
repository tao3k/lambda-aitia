;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Provider adapter only. The GitOps module performs the pure policy decision.
(import :poo-flow/lambda-aitia/modules/gitops/interface)
(export github-change github-check github-run-gitops)
(def (github-change event repository revision source-ref target-ref pull-request)
  (gitops-change 'github event repository revision source-ref target-ref pull-request))
(def (github-check name repository revision conclusion)
  (gitops-check name repository revision conclusion))
(def (github-run-gitops composition change checks)
  (gitops-evaluate composition change checks))
