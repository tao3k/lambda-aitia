;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :poo-flow/lambda-aitia/modules/gitops/interface)
(export production)
(define-gitops-profile production OpenGitOpsProfile
  environment: 'production
  event: 'workflow-dispatch
  target-ref: "production"
  required-checks: '(release-authority signed-provenance)
  reconciliation: 'protected
  next-profile: 'complete)
