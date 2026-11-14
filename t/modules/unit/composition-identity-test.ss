;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/mop element?)
        (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref .get)
        (only-in :tao3k/yuanxu/modules/funflow/scenario Scenario)
        (only-in :tao3k/yuanxu/modules/funflow/control-plane/graph execution-plan?)
        (only-in :tao3k/yuanxu/module-system/selection/objects
                 yuanxu-user-module-selection-flags
                 yuanxu-user-module-selection-key)
        (only-in :tao3k/yuanxu/profile-composition/user-profile
                 yuanxu-user-profile-modules)
        (only-in :agentic-ai-lab/modules/proof/interface
                 agentic-ai-lab-proof-module?)
        (only-in "../../../init.ss" lambda-aitia.init.exports))

(export lambda-aitia-composition-identity-test)

(def AitiaModule
  (.get lambda-aitia.init.exports Profiles software-engineering profile-module))
(def aitia (.get lambda-aitia.init.exports scenarios aitia scenario))

(def lambda-aitia-composition-identity-test
  (test-suite
   "official Aitia native Profile composition"
   (test-case "Aitia owns one qualified semantic Module"
     (check-equal? (.ref (.ref AitiaModule 'identity) 'namespace)
                   'software-engineering)
     (check-equal? (.ref (.ref AitiaModule 'identity) 'name) 'aitia))
   (test-case "root is one closed Agentic AI Lab Case"
     (check-equal? (element? Scenario aitia) #t)
     (check-equal? (.ref aitia 'name) 'aitia)
     (check-equal? (length (.ref aitia 'profiles)) 1)
     (check-equal? (length (.ref aitia 'profile-bindings)) 1)
     (check-equal? (length (.ref aitia 'selection-proofs)) 1)
     (check-equal? (execution-plan? (.ref aitia 'execution-plan)) #t)
     (check-equal? (.ref aitia 'runtime-executed?) #f))
   (test-case "default Project selects the complete software engineering closure"
     (let (modules
           (yuanxu-user-profile-modules (car (.ref aitia 'profiles))))
       (check-equal?
        (map yuanxu-user-module-selection-key modules)
        '((software-engineering . gitops)
          (software-engineering . sdlc)
          (nasa . sdlc)
          (software-engineering . ADR)
          (software-engineering . assurance)
          (software-engineering . formal-methods)))
       (check-equal?
        (yuanxu-user-module-selection-flags (list-ref modules 5))
        '(+quint +lean))))
   (test-case "formal-method declarations reuse the Agentic AI Lab Proof module"
     (let* ((scope (.get (.get lambda-aitia.init.exports modules) formal-methods))
            (providers (.get scope providers)))
       (check-equal? (agentic-ai-lab-proof-module? (.get scope module)) #t)
       (check-equal? (.ref (.get providers quint) 'runtime-executed?) #f)
       (check-equal? (.ref (.get providers lean) 'obligation-only?) #t)
       (check-equal? (.ref (.get providers cedar) 'role)
                     'authorization-policy-validation)))))
