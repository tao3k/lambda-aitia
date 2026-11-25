;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" GitOpsScopeContract)
        (only-in "./config.ss" Config))
(export GitOps)

(.def GitOps
  identity: 'gitops
  tags: '(software-engineering gitops)
  core: (.o scope-contract: GitOpsScopeContract
            exports: Config)
  features: '(github))
