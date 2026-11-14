;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Object Function Any)
        (only-in :clan/poo/type Record String))
(export ScopeContract)

(def ScopeContract
  (.cc (Record scenario: [Object] commit-policy: [(Function (list Object) (list String String Any))])
       identity: 'github-gitops/scope))
