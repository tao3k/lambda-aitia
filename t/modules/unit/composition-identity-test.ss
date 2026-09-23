;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-composition-catalog-ref
                 poo-flow-composition-identity-official?
                 poo-flow-composition-identity-qualified-name
                 poo-flow-load-composition-value
                 poo-flow-scenario-case?)
        (only-in :poo-flow/src/module-system/declaration/interface
                 poo-flow-user-module-selection-flags
                 poo-flow-user-module-selection-key)
        (only-in :poo-flow/src/modules/proof/interface
                 poo-flow-proof-module?)
        (only-in :poo-flow/src/user-interface/profile-core
                 poo-flow-user-profile-modules)
        :poo-flow/lambda-aitia/modules/formal-methods/interface
        :poo-flow/lambda-aitia/user-interface/compositions/aitia)

(export lambda-aitia-composition-identity-test)

(def lambda-aitia-composition-identity-test
  (test-suite
   "official Aitia Composition identity"
   (test-case "publishes Aitia through the reserved unqualified selector"
     (check-equal?
      (poo-flow-composition-identity-qualified-name
       aitia-composition-identity)
      'aitia)
     (check-equal?
     (poo-flow-composition-identity-official?
       aitia-composition-identity)
      #t))
   (test-case "registers the official Aitia value without namespace fallback"
     (check-equal?
      (eq? (poo-flow-composition-catalog-ref
            aitia-composition-catalog 'aitia)
           aitia-composition)
      #t)
     (check-equal?
      (.ref aitia-composition-catalog 'module-names)
      '(gitops sdlc ADR assurance formal-methods)))
   (test-case "default Profile selects the complete software engineering closure"
     (let (modules
           (poo-flow-user-profile-modules
            (.ref aitia-composition 'default-profile)))
       (check-equal?
        (map poo-flow-user-module-selection-key modules)
        '((software-engineering . gitops)
          (software-engineering . sdlc)
          (software-engineering . ADR)
          (software-engineering . assurance)
          (software-engineering . formal-methods)))
       (check-equal?
        (poo-flow-user-module-selection-flags (list-ref modules 4))
        '(+tla+ +lean +cedar))))
   (test-case "formal-method declarations reuse the POO Flow Proof module"
     (check-equal? (poo-flow-proof-module? aitia-formal-methods-module) #t)
     (check-equal? (.ref aitia-tla-plus-provider 'runtime-executed?) #f)
     (check-equal? (.ref aitia-lean-provider 'obligation-only?) #t)
     (check-equal? (.ref aitia-cedar-provider 'role)
                   'authorization-policy-validation))
   (test-case "loads the downstream file as one closed Case"
     (let (case-value
           (poo-flow-load-composition-value
            "t/fixtures/composition-value/aitia.ss"
            aitia-composition-catalog))
       (check-equal? (poo-flow-scenario-case? case-value) #t)
       (check-equal? (.ref case-value 'name) 'aitia)
       (check-equal? (length (.ref case-value 'profiles)) 1)
       (check-equal? (length (.ref case-value 'stages)) 1)
       (check-equal?
        (.ref (.ref (car (.ref case-value 'profiles)) 'project) 'repository)
        "tao3k/lambda-aitia")
       (check-equal?
        (.ref (.ref (car (.ref case-value 'profiles)) 'delivery) 'provider)
        'github)
       (check-equal? (.ref (.ref case-value 'admission) 'accepted?) #t)))))
