;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :poo-flow/src/module-system/declaration/interface
        :poo-flow/lambda-aitia/modules/ADR/funs)

(export ADR-config)

(def (ADR-config selection)
  (unless (and (poo-flow-user-module-selection? selection)
               (equal? (poo-flow-user-module-selection-key selection)
                       '(custom . ADR))
               (null? (poo-flow-user-module-selection-flags selection)))
    (error "invalid ADR module selection"))
  ADR-module)
