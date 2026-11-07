;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :yuanxu/module-system/schema/relations
                 yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        "objects.ss")
(export make-nasa-profile-scope)

(def (make-nasa-profile-scope sdlc catalog)
  (let (profile (make-nasa-profile sdlc catalog))
    (.o standard: profile
        profile-module:
        (yuanxu-semantic-module
         (yuanxu-semantic-identity 'nasa 'sdlc)
         profiles: (yuanxu-module-profiles
                    (yuanxu-profile-export 'npr-7150.2 profile))))))
