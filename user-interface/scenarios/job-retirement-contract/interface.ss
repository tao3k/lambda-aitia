;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ScopeContract)
        (only-in "./config.ss" make-job-retirement-scope)
        (only-in "../../../modules/sdlc/config.ss" SdlcScope))
(export Published)

(.def Published
  identity: 'job-retirement-contract
  core: (.o scope-contract: ScopeContract
            exports: (make-job-retirement-scope SdlcScope))
  features: (.o))
