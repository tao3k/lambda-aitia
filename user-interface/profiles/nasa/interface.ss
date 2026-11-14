;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def Published
  identity: 'nasa-7150-2d
  core: (.o requires: (.o Sdlc: (.o module-id: 'lambda-aitia/modules/sdlc/interface)
                        Catalog: (.o module-id: 'lambda-aitia/modules/nasa-7150-2d-catalog/interface))
            scope-contract: ScopeContract
            exports: (make-nasa-profile-scope Sdlc Catalog))
  features: (.o))
