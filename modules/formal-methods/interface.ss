;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def FormalMethods
  identity: 'formal-methods
  tags: '(software-engineering formal-methods)
  core: (.o requires: (.o)
            scope-contract: FormalMethodsScopeContract
            exports: Config)
  features: (.o))
