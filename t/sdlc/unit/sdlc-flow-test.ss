;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in "../../../init.ss" lambda-aitia.init.exports)
        :std/test
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/graph/algorithms yuanxu-graph-topological-order))

(def sdlc (.get lambda-aitia.init.exports modules sdlc))
(def sdlc-flow-graph (.get sdlc flow-graph))


(export sdlc-flow-test)

(def sdlc-flow-test
  (test-suite "Aitia production SDLC flow projection"
    (test-case "Aitia semantics project one complete lifecycle onto Agentic AI Lab DAG"
      (let (graph (sdlc-flow-graph "release/42"))
        (check-equal?
         (yuanxu-graph-topological-order graph)
         '(release/42/change release/42/invalidate release/42/plan
           release/42/verify release/42/admit release/42/decide
           release/42/authorize release/42/effect))))
    (test-case "invalid lifecycle identity fails before graph construction"
      (check-exception (sdlc-flow-graph "") true))))
