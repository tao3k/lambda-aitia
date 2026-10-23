;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :agentic-ai-lab/modules/workflow/scenario/case
                 agentic-ai-lab-scenario-case?)
        (only-in :core/module-system/selection/objects
                 agentic-ai-lab-user-module-selection-flags
                 agentic-ai-lab-user-module-selection-key)
        (only-in :core/profile-composition/user-profile
                 agentic-ai-lab-user-profile-modules)
        (only-in :agentic-ai-lab/modules/proof/interface
                 agentic-ai-lab-proof-module?)
        :agentic-ai-lab/lambda-aitia/modules/formal-methods/interface
        :agentic-ai-lab/lambda-aitia/user-interface/compositions/aitia)

(export lambda-aitia-composition-identity-test)

(def lambda-aitia-composition-identity-test
  (test-suite
   "official Aitia native Profile composition"
   (test-case "Aitia owns one qualified semantic Module"
     (check-equal? (.ref (.ref AitiaModule 'identity) 'namespace)
                   'software-engineering)
     (check-equal? (.ref (.ref AitiaModule 'identity) 'name) 'aitia))
   (test-case "root is one closed Agentic AI Lab Case"
     (check-equal? (agentic-ai-lab-scenario-case? aitia) #t)
     (check-equal? (.ref aitia 'name) 'aitia)
     (check-equal? (length (.ref aitia 'profiles)) 1)
     (check-equal? (length (.ref aitia 'profile-bindings)) 1)
     (check-equal? (length (.ref aitia 'selection-proofs)) 1)
     (check-equal? (.ref (.ref aitia 'admission) 'accepted?) #t)
     (check-equal? (.ref aitia 'runtime-executed?) #f))
   (test-case "default Project selects the complete software engineering closure"
     (let (modules
           (agentic-ai-lab-user-profile-modules (car (.ref aitia 'profiles))))
       (check-equal?
        (map agentic-ai-lab-user-module-selection-key modules)
        '((software-engineering . gitops)
          (software-engineering . sdlc)
          (nasa . sdlc)
          (software-engineering . ADR)
          (software-engineering . assurance)
          (software-engineering . formal-methods)))
       (check-equal?
        (agentic-ai-lab-user-module-selection-flags (list-ref modules 5))
        '(+quint +lean +cedar))))
   (test-case "formal-method declarations reuse the Agentic AI Lab Proof module"
     (check-equal? (agentic-ai-lab-proof-module? aitia-formal-methods-module) #t)
     (check-equal? (.ref aitia-quint-provider 'runtime-executed?) #f)
     (check-equal? (.ref aitia-lean-provider 'obligation-only?) #t)
     (check-equal? (.ref aitia-cedar-provider 'role)
                   'authorization-policy-validation))))
