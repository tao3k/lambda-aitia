;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Object)
        (only-in :clan/poo/type Record List Symbol)
        (only-in :tao3k/yuanxu/graph/types YuanxuGraphContract))
(export ScopeContract)

(def ScopeContract
  (.cc (Record relations: [(List Symbol)]
               before: [YuanxuGraphContract] candidate: [YuanxuGraphContract]
               event-graph: [Object] incomplete-event-graph: [Object])
       identity: 'job-executor-retirement/scope))
