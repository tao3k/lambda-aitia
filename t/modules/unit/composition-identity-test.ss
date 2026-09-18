;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-composition-identity-official?
                 poo-flow-composition-identity-qualified-name)
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
      #t))))
