;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


(import (only-in :clan/poo/object .o)
        (only-in "../../func.ss" gitops-change))
(export enable-github)

(def GitHub
  (.o change: (cut gitops-change 'github <> <> <> <> <> <>)))

(def (enable-github scope)
  (.o (:: self scope) github: GitHub))
