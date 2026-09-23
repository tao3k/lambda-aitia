;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/graph/types
                 poo-flow-graph? poo-flow-graph-edges poo-flow-graph-nodes)
        :poo-flow/lambda-aitia/modules/sdlc/interface)

(export sdlc-flow-test)

(def sdlc-flow-test
  (test-suite "Aitia production SDLC flow projection"
    (test-case "Aitia semantics project one complete lifecycle onto POO Flow DAG"
      (let (plan (sdlc-flow-plan "release/42"))
        (check-equal?
         (.ref plan 'topological-order)
         '(release/42/change release/42/invalidate release/42/plan
           release/42/verify release/42/admit release/42/decide
           release/42/authorize release/42/effect))))
    (test-case "invalid lifecycle identity fails before graph construction"
      (check-exception (sdlc-flow-plan "") true))))
