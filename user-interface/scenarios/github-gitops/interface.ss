;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def)
        (rename-in (only-in "../../../modules/assurance/config.ss" Config) (Config Assurance))
        (only-in "../../../modules/sdlc/config.ss" make-sdlc-scope)
        (rename-in (only-in "../../../modules/gitops/config.ss" Config) (Config GitOps))
        (rename-in (only-in "../../../modules/nasa-7150-2d-catalog/config.ss" Config) (Config Catalog))
        (only-in "../../profiles/gitops/config.ss" make-delivery-profile-scope)
        (only-in "../../profiles/nasa/config.ss" make-nasa-profile-scope))
(.def Published
  identity: 'github-gitops
  core: (.o scope-contract: ScopeContract
            exports: (make-github-gitops-scope
                      (make-delivery-profile-scope GitOps)
                      (make-nasa-profile-scope (make-sdlc-scope Assurance) Catalog)))
  features: (.o))
