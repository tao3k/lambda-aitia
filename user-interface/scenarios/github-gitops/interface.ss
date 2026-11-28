;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" ScopeContract)
        (only-in "./config.ss" make-github-gitops-scope)
        (only-in "../../../modules/sdlc/config.ss" SdlcScope)
        (only-in "../../profiles/gitops/config.ss" DeliveryProfileScope)
        (only-in "../../profiles/nasa/config.ss" NasaProfileScope))
(export Published)

(.def Published
  identity: 'github-gitops
  core: (.o scope-contract: ScopeContract
            exports: (make-github-gitops-scope DeliveryProfileScope NasaProfileScope SdlcScope))
  features: (.o))
