;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Official Aitia composition over POO Flow's current Profile algebra.
;;; Domain selection stays in the maintained Project Profile; POO Flow owns
;;; module selection, composition, Case lowering and runtime admission.
(import (only-in :clan/poo/object .o)
        (only-in :poo-flow/src/module-system/semantic-module/objects
                 poo-flow-semantic-identity poo-flow-semantic-module)
        (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-profile-export poo-flow-module-profiles
                 profiles compose use-module user-composition)
        :poo-flow/lambda-aitia/user-interface/profiles/software-engineering/project)

(export AitiaModule aitia)

(def AitiaModule
  (poo-flow-semantic-module
   (poo-flow-semantic-identity 'software-engineering 'aitia)
   profiles:
   (poo-flow-module-profiles
    (poo-flow-profile-export
     'default
     (.o (:: @ default-software-engineering-project)
         stages: (.o software-engineering-project: (.o)))))))

(user-composition aitia
  (compose profiles
    (use-module AitiaModule default)))
