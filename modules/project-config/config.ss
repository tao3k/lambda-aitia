;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o) "func.ss" "objects.ss")
(export Config)

(def Config
  (let (defaults (project-config-defaults))
    (.o resolve: (lambda (declaration) (resolve-project-config defaults declaration))
        decode: (lambda (source) (decode-project-config defaults source))
        checks: project-checks)))
