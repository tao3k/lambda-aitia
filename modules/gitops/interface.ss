;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(.def GitOps
  identity: 'gitops
  tags: '(software-engineering gitops)
  core: (.o requires: (.o)
            scope-contract: GitOpsScopeContract
            exports: Config)
  features: '(github))
