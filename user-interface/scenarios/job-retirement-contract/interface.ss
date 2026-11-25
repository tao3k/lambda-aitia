;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def)
        (rename-in (only-in "../../../modules/assurance/config.ss" Config) (Config Assurance))
        (only-in "../../../modules/sdlc/config.ss" make-sdlc-scope))
(.def Published
  identity: 'job-retirement-contract
  core: (.o scope-contract: ScopeContract
            exports: (make-job-retirement-scope (make-sdlc-scope Assurance)))
  features: (.o))
