;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: maintained default Software Engineering Project Profile.
;;; Invariant: the Profile selects Aitia knowledge and obligations only; module
;;; realization and Runtime execution remain separate Agentic AI Lab phases.

(import (only-in :clan/poo/object .o)
        (only-in :yuanxu/module-system/schema/relations yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        (only-in :yuanxu/module-system/selection/objects
                 yuanxu-settings
                 yuanxu-user-module-selection)
        (only-in :yuanxu/profile-composition/user-profile
                 yuanxuUserProfile))

(export AitiaModule)

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

(def AitiaModule
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'software-engineering 'aitia)
   profiles:
   (yuanxu-module-profiles
    (yuanxu-profile-export
     'default
     (.o (:: @ default-software-engineering-project)
         stages: (.o software-engineering-project: (.o)))))))
