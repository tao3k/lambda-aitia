;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import :poo-flow/src/module-system/declaration/interface
        :poo-flow/lambda-aitia/modules/gitops/objects)
(export gitops-config)
(def (gitops-config selection)
  (unless (and (poo-flow-user-module-selection? selection)
               (equal? (poo-flow-user-module-selection-key selection)
                       '(custom . gitops)))
    (error "expected a custom/gitops selection"))
  (let (flags (poo-flow-user-module-selection-flags selection))
    (unless (or (null? flags) (equal? flags '(+open-gitops)))
      (error "unsupported GitOps feature" flags))
    GitOpsModule))
