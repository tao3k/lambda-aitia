;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get)
        (only-in "../../../init.ss" lambda-aitia.init.exports)
        "nasa-7150-2d-standard.ss")
(export Nasa7150_2D)

(def Nasa7150_2D
  (make-nasa-7150-2d-standard
   (.get lambda-aitia.init.exports modules sdlc standard-profile)
   (.get lambda-aitia.init.exports modules nasa-7150-2d-catalog)))
