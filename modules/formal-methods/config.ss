;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Aitia-owned formal-method providers over the POO Flow Proof core.
;;; Invariant: provider declarations create obligations; they never claim that
;;; an engine ran or that a proof/model/policy was admitted.

(import (only-in :clan/poo/object .o)
        (only-in :poo-flow/src/modules/proof/interface
                 poo-flow-proof-module)
        "types.ss"
        "objects.ss"
        "funs.ss")

(export aitia-tla-plus-provider
        aitia-lean-provider
        aitia-cedar-provider
        aitia-formal-methods-module)

(def aitia-tla-plus-provider
  (aitia-formal-method-provider
   'tla+
   'state-transition-model-checking
   '(module model-checking-configuration trace receipt)))

(def aitia-lean-provider
  (aitia-formal-method-provider
   'lean
   'refinement-and-contract-proof
   '(theorem proof certificate receipt)))

(def aitia-cedar-provider
  (aitia-formal-method-provider
   'cedar
   'authorization-policy-validation
   '(schema policy entities request validation-receipt)))

(def aitia-formal-methods-module
  (poo-flow-proof-module
   "lambda-aitia/modules/formal-methods"
   (.o (tla+ aitia-tla-plus-provider)
       (lean aitia-lean-provider)
       (cedar aitia-cedar-provider))))
