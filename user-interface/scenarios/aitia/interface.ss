;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def Published
  identity: 'aitia
  core: (.o requires:
            (.o Project: (.o module-id: 'lambda-aitia/user-interface/profiles/software-engineering/interface))
            scope-contract: ScopeContract
            exports: (make-aitia-scope Project))
  features: (.o))
