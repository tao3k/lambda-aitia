;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ProjectConfigScopeContract)
        (only-in "./config.ss" Config))
(export ProjectConfig)

(.def ProjectConfig
  identity: 'project-config
  core: (.o scope-contract: ProjectConfigScopeContract
            exports: Config)
  features: (.o))
