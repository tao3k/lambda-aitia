;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def Assurance
  identity: 'assurance
  tags: '(software-engineering assurance)
  core: (.o requires: (.o)
            scope-contract: AssuranceScopeContract
            exports: Config)
  features: (.o))
