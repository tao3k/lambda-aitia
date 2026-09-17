;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :poo-flow/lambda-aitia/modules/gitops/interface)
(export dev)
(define-gitops-profile dev OpenGitOpsProfile
  environment: 'dev
  event: 'pull-request
  target-ref: "develop"
  required-checks: '(commit-policy build unit-test)
  reconciliation: 'automatic
  next-profile: 'staging)
