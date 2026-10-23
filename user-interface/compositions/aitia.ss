;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Official Aitia composition over Agentic AI Lab's current Profile algebra.
;;; Domain selection stays in the maintained Project Profile; Agentic AI Lab owns
;;; module selection, composition, Case lowering and runtime admission.
(import (only-in :clan/poo/object .o)
        (only-in :agentic-ai-lab/core/module-system/schema/relations
                 agentic-ai-lab-semantic-identity)
        (only-in :core/module-system/authoring/roles agentic-ai-lab-semantic-module)
        (only-in :agentic-ai-lab/core/profile-composition/profile-bundle
                 agentic-ai-lab-profile-export agentic-ai-lab-module-profiles
                 profiles compose)
        (only-in :agentic-ai-lab/core/profile-composition/selection-syntax use-module)
        (only-in :agentic-ai-lab/modules/workflow/scenario/composition-syntax user-composition)
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/software-engineering/project)

(export AitiaModule aitia)

(def AitiaModule
  (agentic-ai-lab-semantic-module
   (agentic-ai-lab-semantic-identity 'software-engineering 'aitia)
   profiles:
   (agentic-ai-lab-module-profiles
    (agentic-ai-lab-profile-export
     'default
     (.o (:: @ default-software-engineering-project)
         stages: (.o software-engineering-project: (.o)))))))

(user-composition aitia
  (compose profiles
    (use-module AitiaModule default)))
