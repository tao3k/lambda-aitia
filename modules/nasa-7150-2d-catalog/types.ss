;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Object)
        (only-in :clan/poo/type Record String List))
(export NasaCatalogScopeContract)

(def NasaCatalogScopeContract
  (.cc (Record requirements: [(List Object)]
               source-digests: [(Record chapter2: [String] chapter3: [String]
                                       chapter4: [String] chapter5: [String]
                                       chapter6: [String] appendix-c: [String])])
       identity: 'nasa-7150-2d-catalog/scope))
