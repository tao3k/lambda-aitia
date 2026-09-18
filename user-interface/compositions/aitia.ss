;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: official maintained Aitia Composition and its catalog entry.
;;; Invariant: Aitia owns domain assembly only; selection, loading, planning and
;;; identity rules come from POO Flow.

(import (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-composition
                 poo-flow-composition-catalog
                 poo-flow-official-composition-identity
                 poo-flow-scenario-case
                 poo-flow-scenario-clause
                 poo-flow-scenario-profile-binding
                 poo-flow-scenario-stage)
        :poo-flow/lambda-aitia/modules/formal-methods/interface
        :poo-flow/lambda-aitia/user-interface/profiles/software-engineering/project)

(export aitia-composition-identity
        aitia-composition
        aitia-composition-catalog)

(def aitia-composition-identity
  (poo-flow-official-composition-identity 'aitia))

(def (aitia-default-case project-profile)
  (poo-flow-scenario-case
   'aitia
   '()
   (list project-profile)
   (list
    (poo-flow-scenario-stage
     'software-engineering-project
     (list
      (poo-flow-scenario-clause
       'profile
       '(default-software-engineering-project)))))
   (list
    (poo-flow-scenario-profile-binding
     'aitia
     'default-software-engineering-project))))

(def aitia-composition
  (poo-flow-composition
   aitia-composition-identity
   default-software-engineering-project
   aitia-default-case))

(def aitia-composition-catalog
  (poo-flow-composition-catalog
   (list aitia-composition)
   '(gitops sdlc ADR assurance formal-methods)))
