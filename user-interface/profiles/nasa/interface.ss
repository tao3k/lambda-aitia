;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ScopeContract)
        (only-in "./config.ss" NasaProfileScope))
(export Published)

(.def Published
  identity: 'nasa-7150-2d
  core: (.o scope-contract: ScopeContract
            exports: NasaProfileScope)
  features: (.o))
