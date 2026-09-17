;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :poo-flow/lambda-aitia/modules/gitops/interface)
(export staging)
(define-gitops-profile staging OpenGitOpsProfile
  environment: 'staging
  event: 'push
  target-ref: "develop"
  required-checks: '(integration-test security-review)
  reconciliation: 'automatic
  next-profile: 'production)
