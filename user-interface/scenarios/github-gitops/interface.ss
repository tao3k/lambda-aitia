;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(.def Published
  identity: 'github-gitops
  core: (.o requires: (.o Delivery: (.o module-id: 'lambda-aitia/user-interface/profiles/gitops/interface)
                        Nasa: (.o module-id: 'lambda-aitia/user-interface/profiles/nasa/interface))
            scope-contract: ScopeContract
            exports: (make-github-gitops-scope Delivery Nasa))
  features: (.o))
