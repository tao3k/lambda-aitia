;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o) "func.ss" "objects.ss")
(export Config)

(def Config
  (.o resolve: (cut resolve-project-config ProjectConfigDefaults <>)
      decode: (cut decode-project-config ProjectConfigDefaults <>)
      checks: project-checks))
