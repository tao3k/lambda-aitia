;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;; Initialize Config under the publication reader before recording scope support.
(import "config.ss")

(.def GitOps
  identity: 'gitops
  tags: '(software-engineering gitops)
  core: (.o requires: (.o)
            scope-contract: GitOpsScopeContract
            exports: Config)
  features: '(github))
