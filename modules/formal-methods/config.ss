;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get)
        (only-in :agentic-ai-lab/modules/proof/interface agentic-ai-lab-proof-module)
        "types.ss" "func.ss" "objects.ss")
(export Config)

;;; Engine declarations are available capabilities, never execution or admission.
(def Config
  (.o (:: scope)
      providers: (.o quint: QuintProvider lean: LeanProvider cedar: CedarProvider)
      module: (agentic-ai-lab-proof-module "lambda-aitia/modules/formal-methods"
                (.get scope providers))
      provider: aitia-formal-method-provider
      provider?: aitia-formal-method-provider?
      engines: aitia-formal-method-provider-engines))
