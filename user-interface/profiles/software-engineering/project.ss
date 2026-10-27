;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: maintained default Software Engineering Project Profile.
;;; Invariant: the Profile selects Aitia knowledge and obligations only; module
;;; realization and Runtime execution remain separate Agentic AI Lab phases.

(import (only-in :yuanxu/module-system/selection/objects
                 yuanxu-settings
                 yuanxu-user-module-selection)
        (only-in :yuanxu/profile-composition/user-profile
                 yuanxuUserProfile))

(export default-software-engineering-project)

(def default-software-engineering-project
  (yuanxuUserProfile
   'default-software-engineering-project
   (list
    (list
     (yuanxu-user-module-selection
      'software-engineering 'gitops '(+open-gitops))
     (yuanxu-user-module-selection
      'software-engineering 'sdlc '())
     (yuanxu-user-module-selection
      'nasa 'sdlc '(+npr-7150.2))
     (yuanxu-user-module-selection
      'software-engineering 'ADR '(+rfc-relations))
     (yuanxu-user-module-selection
      'software-engineering 'assurance '(+causal-evidence))
     (yuanxu-user-module-selection
      'software-engineering 'formal-methods '(+quint +lean +cedar))))
   (yuanxu-settings
    project-kind: 'software-engineering
    composition: 'aitia
    formal-method-obligations: '(quint lean cedar)
    runtime-executed?: #f)
   '(project-kind
     composition
     formal-method-obligations
     runtime-executed?)))
