;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import "func.ss")
(export QuintProvider LeanProvider CedarProvider)

(def QuintProvider
  (aitia-formal-method-provider 'quint 'state-transition-model-checking
    '(module model-checking-configuration trace receipt)))
(def LeanProvider
  (aitia-formal-method-provider 'lean 'refinement-and-contract-proof
    '(theorem proof certificate receipt)))
(def CedarProvider
  (aitia-formal-method-provider 'cedar 'authorization-policy-validation
    '(schema policy entities request validation-receipt)))
