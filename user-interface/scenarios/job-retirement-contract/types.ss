;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Object)
        (only-in :clan/poo/type Record List String))
(export ScopeContract)

(def ScopeContract
  (.cc (Record contract: [Object] guarantee: [Object]
               quint-sources: [(List String)] lean-sources: [(List String)]
               scheme-sources: [(List String)])
       identity: 'job-retirement-contract/scope))
