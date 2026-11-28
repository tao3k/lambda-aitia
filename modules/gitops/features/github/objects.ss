;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref))
(export enable-github)

(def (enable-github scope)
  (.o self: gitops inherit: (list scope)
      github: (.o change: (cut (.ref gitops 'change) 'github <> <> <> <> <> <>))))
