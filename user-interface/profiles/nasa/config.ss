;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        "objects.ss")
(export make-nasa-profile-scope)

(def (make-nasa-profile-scope sdlc catalog)
  (let (profile (make-nasa-profile sdlc catalog))
    (.o standard: profile
        profile-module: (nasa-profile-module profile))))
