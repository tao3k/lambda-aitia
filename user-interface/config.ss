;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Maintained GitHub/GitOps/SDLC Case. Selection and Case lowering belong to
;;; Agentic AI Lab; the concrete policy Profiles remain owned by Aitia.
(import (only-in :yuanxu/profile-composition/profile-bundle
                 profiles compose
                 yuanxu-profile-export yuanxu-module-profiles)
        (only-in :yuanxu/profile-composition/selection-syntax use-module)
        (only-in :agentic-ai-lab/modules/workflow/scenario/composition-syntax user-composition)
        (only-in :yuanxu/module-system/schema/relations
                 yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/github/actions
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/dev
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/staging
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/gitops/production
        :agentic-ai-lab/lambda-aitia/user-interface/profiles/nasa/sdlc)
(export AitiaDeliveryModule github-gitops-sdlc)

(def AitiaDeliveryModule
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'software-engineering 'delivery)
   profiles:
   (yuanxu-module-profiles
    (yuanxu-profile-export 'actions actions)
    (yuanxu-profile-export 'dev dev)
    (yuanxu-profile-export 'staging staging)
    (yuanxu-profile-export 'production production))))

(user-composition github-gitops-sdlc
  (compose profiles
    (use-module AitiaDeliveryModule actions dev staging production)
    (use-module NasaSdlcModule npr-7150.2)))
