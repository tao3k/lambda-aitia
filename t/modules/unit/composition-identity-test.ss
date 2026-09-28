;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-scenario-case?)
        (only-in :poo-flow/src/module-system/declaration/interface
                 poo-flow-user-module-selection-flags
                 poo-flow-user-module-selection-key)
        (only-in :poo-flow/src/user-interface/profile-core
                 poo-flow-user-profile-modules)
        (only-in :poo-flow/src/modules/proof/interface
                 poo-flow-proof-module?)
        :poo-flow/lambda-aitia/modules/formal-methods/interface
        :poo-flow/lambda-aitia/user-interface/compositions/aitia)

(export lambda-aitia-composition-identity-test)

(def lambda-aitia-composition-identity-test
  (test-suite
   "official Aitia native Profile composition"
   (test-case "Aitia owns one qualified semantic Module"
     (check-equal? (.ref (.ref AitiaModule 'identity) 'namespace)
                   'software-engineering)
     (check-equal? (.ref (.ref AitiaModule 'identity) 'name) 'aitia))
   (test-case "root is one closed POO Flow Case"
     (check-equal? (poo-flow-scenario-case? aitia) #t)
     (check-equal? (.ref aitia 'name) 'aitia)
     (check-equal? (length (.ref aitia 'profiles)) 1)
     (check-equal? (length (.ref aitia 'profile-bindings)) 1)
     (check-equal? (length (.ref aitia 'selection-proofs)) 1)
     (check-equal? (.ref (.ref aitia 'admission) 'accepted?) #t)
     (check-equal? (.ref aitia 'runtime-executed?) #f))
   (test-case "default Project selects the complete software engineering closure"
     (let (modules
           (poo-flow-user-profile-modules (car (.ref aitia 'profiles))))
       (check-equal?
        (map poo-flow-user-module-selection-key modules)
        '((software-engineering . gitops)
          (software-engineering . sdlc)
          (nasa . sdlc)
          (software-engineering . ADR)
          (software-engineering . assurance)
          (software-engineering . formal-methods)))
       (check-equal?
        (poo-flow-user-module-selection-flags (list-ref modules 5))
        '(+tla+ +lean +cedar))))
   (test-case "formal-method declarations reuse the POO Flow Proof module"
     (check-equal? (poo-flow-proof-module? aitia-formal-methods-module) #t)
     (check-equal? (.ref aitia-tla-plus-provider 'runtime-executed?) #f)
     (check-equal? (.ref aitia-lean-provider 'obligation-only?) #t)
     (check-equal? (.ref aitia-cedar-provider 'role)
                   'authorization-policy-validation))))
