;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Official Aitia composition over Agentic AI Lab's current Profile algebra.
;;; Domain selection stays in the maintained Project Profile; Agentic AI Lab owns
;;; module selection, composition, Case lowering and runtime admission.
(import (only-in :clan/poo/object .o)
        (only-in :yuanxu/module-system/schema/relations
                 yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles
                 profiles compose)
        (only-in :yuanxu/profile-composition/selection-syntax use-module)
        (only-in :agentic-ai-lab/modules/workflow/scenario/composition-syntax user-composition)
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/software-engineering/project)

(export AitiaModule aitia)

(def AitiaModule
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'software-engineering 'aitia)
   profiles:
   (yuanxu-module-profiles
    (yuanxu-profile-export
     'default
     (.o (:: @ default-software-engineering-project)
         stages: (.o software-engineering-project: (.o)))))))

(user-composition aitia
  (compose profiles
    (use-module AitiaModule default)))
