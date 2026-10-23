;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Maintained GitHub/GitOps/SDLC Case. Selection and Case lowering belong to
;;; Agentic AI Lab; the concrete policy Profiles remain owned by Aitia.
(import (only-in :agentic-ai-lab/core/profile-composition/profile-bundle
                 profiles compose
                 agentic-ai-lab-profile-export agentic-ai-lab-module-profiles)
        (only-in :agentic-ai-lab/core/profile-composition/selection-syntax use-module)
        (only-in :agentic-ai-lab/modules/workflow/scenario/composition-syntax user-composition)
        (only-in :agentic-ai-lab/core/module-system/schema/relations
                 agentic-ai-lab-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles agentic-ai-lab-semantic-module)
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/github/actions
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/dev
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/staging
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/production
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/nasa/sdlc)
(export AitiaDeliveryModule github-gitops-sdlc)

(def AitiaDeliveryModule
  (agentic-ai-lab-semantic-module
   (agentic-ai-lab-semantic-identity 'software-engineering 'delivery)
   profiles:
   (agentic-ai-lab-module-profiles
    (agentic-ai-lab-profile-export 'actions actions)
    (agentic-ai-lab-profile-export 'dev dev)
    (agentic-ai-lab-profile-export 'staging staging)
    (agentic-ai-lab-profile-export 'production production))))

(user-composition github-gitops-sdlc
  (compose profiles
    (use-module AitiaDeliveryModule actions dev staging production)
    (use-module NasaSdlcModule npr-7150.2)))
