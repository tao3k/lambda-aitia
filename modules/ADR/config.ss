;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :yuanxu/module-system/selection/objects
        :agentic-ai-lab/lambda-aitia/modules/ADR/funs)

(export ADR-config)

(def (ADR-config selection)
  (unless (and (yuanxu-user-module-selection? selection)
               (equal? (yuanxu-user-module-selection-key selection)
                       '(custom . ADR))
               (null? (yuanxu-user-module-selection-flags selection)))
    (error "invalid ADR module selection"))
  ADR-module)
