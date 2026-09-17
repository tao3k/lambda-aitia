;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        :poo-flow/lambda-aitia/modules/assurance/types)

(export AssurancePolicy)

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
