;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Maintained GitHub/GitOps/SDLC Case. Selection and Case lowering belong to
;;; POO Flow; the concrete policy Profiles remain owned by Aitia.
(import (only-in :poo-flow/src/module-system/profile-composition/interface
                 profiles compose use-module user-composition
                 poo-flow-profile-export poo-flow-module-profiles)
        (only-in :poo-flow/src/module-system/semantic-module/objects
                 poo-flow-semantic-identity poo-flow-semantic-module)
        :poo-flow/lambda-aitia/user-interface/profiles/github/actions
        :poo-flow/lambda-aitia/user-interface/profiles/gitops/dev
        :poo-flow/lambda-aitia/user-interface/profiles/gitops/staging
        :poo-flow/lambda-aitia/user-interface/profiles/gitops/production
        :poo-flow/lambda-aitia/user-interface/profiles/nasa/sdlc)
(export AitiaDeliveryModule github-gitops-sdlc)

(def AitiaDeliveryModule
  (poo-flow-semantic-module
   (poo-flow-semantic-identity 'software-engineering 'delivery)
   profiles:
   (poo-flow-module-profiles
    (poo-flow-profile-export 'actions actions)
    (poo-flow-profile-export 'dev dev)
    (poo-flow-profile-export 'staging staging)
    (poo-flow-profile-export 'production production))))

(user-composition github-gitops-sdlc
  (compose profiles
    (use-module AitiaDeliveryModule actions dev staging production)
    (use-module NasaSdlcModule npr-7150.2)))
