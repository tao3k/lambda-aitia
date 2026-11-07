;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(.def Published
  identity: 'delivery
  core: (.o requires: (.o GitOps: (.o module-id: 'lambda-aitia/modules/gitops/interface))
            scope-contract: ScopeContract
            exports: (make-delivery-profile-scope GitOps))
  features: (.o))
