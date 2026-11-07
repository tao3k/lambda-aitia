;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Organization NASA / domain SDLC / standard family NPR 7150.2.
;;; Agentic AI Lab owns the typed namespace, Module and Profile selection.
(import (only-in :clan/poo/object .get .o)
        (only-in :yuanxu/module-system/schema/relations yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        (only-in "../../../modules/sdlc/standards/nasa-7150-2d-standard.ss" make-nasa-7150-2d-standard))
(export make-nasa-profile nasa-profile-module)

(def (make-nasa-profile sdlc catalog)
  (let* ((standard (make-nasa-7150-2d-standard (.get sdlc standard-profile) catalog))
         (profile ((.get sdlc with-standards) (.get sdlc profile) (list standard))))
    (.o (:: @ profile)
        name: 'nasa/sdlc/npr-7150.2
        role: 'standard
        standard: "nasa/sdlc/npr-7150.2"
        owner: 'lambda-aitia
        extends: profile
        runtime-executed: #f)))

(def (nasa-profile-module profile)
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'nasa 'sdlc)
   profiles: (yuanxu-module-profiles (yuanxu-profile-export 'npr-7150.2 profile))))
