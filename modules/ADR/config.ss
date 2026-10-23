;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :core/module-system/selection/objects
        :agentic-ai-lab/lambda-aitia/modules/ADR/funs)

(export ADR-config)

(def (ADR-config selection)
  (unless (and (agentic-ai-lab-user-module-selection? selection)
               (equal? (agentic-ai-lab-user-module-selection-key selection)
                       '(custom . ADR))
               (null? (agentic-ai-lab-user-module-selection-flags selection)))
    (error "invalid ADR module selection"))
  ADR-module)
