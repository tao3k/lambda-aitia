;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :gerbil/core list-sort)
        :std/list/list
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types)

(export AssurancePolicy assurance-verification-policy)

;;; Pure declared defaults.  This value invokes no verifier and grants no
;;; authority.
(def AssurancePolicy
  (.o identity: "lambda-aitia/assurance-policy"
      revision: "1"
      relation-planes: +assurance-relation-planes+
      unresolved-frontier: 'block
      conflict-resolution: 'explicit
      planner-executes?: #f
      grants-authority?: #f))

(def (capability<? left right)
  (string<? (symbol->string left) (symbol->string right)))

;;; Capabilities describe available adapters; this value cannot invoke one.
(def (assurance-verification-policy identity-value revision-value capability-values)
  (unless (and (list? capability-values) (every symbol? capability-values))
    (error "verification policy capabilities must be symbols" capability-values))
  (poo-flow-check-model
   AssuranceVerificationPolicy
   (.o (:: @ (poo-flow-model-prototype AssuranceVerificationPolicy))
       identity: identity-value revision: revision-value
       capabilities:
       (list-sort capability<? (delete-duplicates/hash capability-values))
       planner-executes?: #f grants-authority?: #f)))
