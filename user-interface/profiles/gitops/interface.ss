;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def)
        (rename-in (only-in "../../../modules/gitops/config.ss" Config) (Config GitOps)))
(.def Published
  identity: 'delivery
  core: (.o scope-contract: ScopeContract
            exports: (make-delivery-profile-scope GitOps))
  features: (.o))
