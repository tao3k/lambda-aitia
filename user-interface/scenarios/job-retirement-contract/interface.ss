;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def Published
  identity: 'job-retirement-contract
  core: (.o requires: (.o Sdlc: (.o module-id: 'lambda-aitia/modules/sdlc/interface))
            scope-contract: ScopeContract
            exports: (make-job-retirement-scope Sdlc))
  features: (.o))
