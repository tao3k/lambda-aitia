;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: maintained default Software Engineering Project Profile.
;;; Invariant: the Profile selects Aitia knowledge and obligations only; module
;;; realization and Runtime execution remain separate POO Flow phases.

(import (only-in :poo-flow/src/module-system/declaration/interface
                 poo-flow-settings
                 poo-flow-user-module-selection)
        (only-in :poo-flow/src/user-interface/profile-core
                 pooFlowUserProfile))

(export default-software-engineering-project)

(def default-software-engineering-project
  (pooFlowUserProfile
   'default-software-engineering-project
   (list
    (list
     (poo-flow-user-module-selection
      'software-engineering 'gitops '(+open-gitops))
     (poo-flow-user-module-selection
      'software-engineering 'sdlc '(+nasa-7150-2d))
     (poo-flow-user-module-selection
      'software-engineering 'ADR '(+rfc-relations))
     (poo-flow-user-module-selection
      'software-engineering 'assurance '(+causal-evidence))
     (poo-flow-user-module-selection
      'software-engineering 'formal-methods '(+tla+ +lean +cedar))))
   (poo-flow-settings
    project-kind: 'software-engineering
    composition: 'aitia
    formal-method-obligations: '(tla+ lean cedar)
    runtime-executed?: #f)
   '(project-kind
     composition
     formal-method-obligations
     runtime-executed?)))
