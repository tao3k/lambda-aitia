;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def ProjectConfig
  identity: 'project-config
  core: (.o requires: (.o)
            scope-contract: ProjectConfigScopeContract
            exports: Config)
  features: (.o))
