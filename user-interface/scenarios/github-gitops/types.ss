;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Type.)
        (only-in :clan/poo/mop Object)
        (only-in :clan/poo/type Record))
(export ScopeContract)

(def Procedure (.cc Type. identity: 'github-operation .element?: procedure?))

(def ScopeContract
  (.cc (Record scenario: [Object] change: [Procedure] check: [Procedure] evaluate: [Procedure])
       identity: 'github-gitops/scope))
