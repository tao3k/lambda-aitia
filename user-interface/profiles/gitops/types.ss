;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Object)
        (only-in :clan/poo/type Record))
(export ScopeContract)

(def ScopeContract
  (.cc (Record dev: [Object] staging: [Object] production: [Object] profile-module: [Object])
       identity: 'delivery/scope))
