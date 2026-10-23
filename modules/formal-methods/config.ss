;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Aitia-owned formal-method providers over the Agentic AI Lab Proof core.
;;; Invariant: provider declarations create obligations; they never claim that
;;; an engine ran or that a proof/model/policy was admitted.

(import (only-in :clan/poo/object .o)
        (only-in :agentic-ai-lab/modules/proof/interface
                 agentic-ai-lab-proof-module)
        "types.ss"
        "objects.ss"
        "funs.ss")

(export aitia-quint-provider
        aitia-lean-provider
        aitia-cedar-provider
        aitia-formal-methods-module)

(def aitia-quint-provider
  (aitia-formal-method-provider
   'quint
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
  (agentic-ai-lab-proof-module
   "lambda-aitia/modules/formal-methods"
   (.o (quint aitia-quint-provider)
       (lean aitia-lean-provider)
       (cedar aitia-cedar-provider))))
