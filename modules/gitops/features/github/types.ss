;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Function)
        (only-in :clan/poo/type False Or Record)
        (only-in :clan/poo/number UInt)
        (only-in "../../types.ss" GitOpsChange GitOpsEvent NonEmptyString))
(export GitHubFeatureContract)

(def GitHubFeatureContract
  (.cc (Record github:
          [(Record change: [(Function (list GitOpsChange)
                              (list GitOpsEvent NonEmptyString NonEmptyString
                                    NonEmptyString NonEmptyString (Or False UInt)))])])
       identity: 'gitops/github-scope))
