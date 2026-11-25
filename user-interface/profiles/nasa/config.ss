;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in "../../../modules/sdlc/config.ss" SdlcScope)
        (rename-in (only-in "../../../modules/nasa-7150-2d-catalog/config.ss" Config) (Config Catalog))
        "objects.ss")
(export make-nasa-profile-scope NasaProfileScope)

(def (make-nasa-profile-scope sdlc catalog)
  (let (profile (make-nasa-profile sdlc catalog))
    (.o standard: profile
        profile-module: (nasa-profile-module profile))))

(def NasaProfileScope (make-nasa-profile-scope SdlcScope Catalog))
