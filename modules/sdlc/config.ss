;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Legacy module-selection projection is standard-free. The NASA Standard is
;;; selected through its own typed nasa/sdlc Module Profile, not an SDLC flag.
(import :poo-flow/src/module-system/declaration/interface
        :poo-flow/lambda-aitia/modules/sdlc/types
        :poo-flow/lambda-aitia/modules/sdlc/objects
        :poo-flow/lambda-aitia/modules/sdlc/funs
        :poo-flow/lambda-aitia/modules/sdlc/standards/nasa-7150-2d-profile
        :std/list/list)
(export sdlc-config sdlc-nasa-7150-profile)

;;; Module-owned base Profile for scenarios that explicitly select NASA
;;; NPR 7150.2D. User compositions derive scenario Profiles from this value.
(def sdlc-nasa-7150-profile
  (sdlc-with-standards SdlcProfile (list Nasa7150_2D)))

(def (sdlc-config selection)
  (unless (and (poo-flow-user-module-selection? selection)
               (equal? (poo-flow-user-module-selection-key selection) '(custom . sdlc)))
    (error "expected a custom/sdlc selection"))
  (let ((flags (poo-flow-user-module-selection-flags selection)))
    (unless (null? flags)
      (error "SDLC has no feature flags; select standards as Modules" flags))
    (sdlc-contribution SdlcProfile)))
