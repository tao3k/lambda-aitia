;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ScopeContract)
        (only-in "./config.ss" Config))
(export Published)

(.def Published
  identity: 'software-engineering
  core: (.o scope-contract: ScopeContract
            exports: Config)
  features: (.o))
