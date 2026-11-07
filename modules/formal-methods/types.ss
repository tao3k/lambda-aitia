;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Any Bool Function element?)
        (only-in :clan/poo/type Record Symbol List Exactly True False)
        (only-in :agentic-ai-lab/modules/proof/interface AgenticAILabProofModule))

(export FormalMethodProvider FormalMethodsScopeContract aitia-formal-method-provider?)

(def FormalMethodProvider
  (.cc (Record kind: [(Exactly 'lambda-aitia.formal-method-provider)
                      constant: 'lambda-aitia.formal-method-provider]
               engine: [Symbol] role: [Symbol] artifact-kinds: [(List Symbol)]
               obligation-only?: [True constant: #t]
               runtime-executed?: [False constant: #f])
       identity: 'formal-methods/provider))

(def (aitia-formal-method-provider? value)
  (element? FormalMethodProvider value))

(def Providers
  (Record quint: [FormalMethodProvider]
          lean: [FormalMethodProvider]
          cedar: [FormalMethodProvider]))

(def FormalMethodsScopeContract
  (.cc (Record providers: [Providers]
               module: [AgenticAILabProofModule]
               provider: [(Function (list FormalMethodProvider)
                                    (list Symbol Symbol (List Symbol)))]
               provider?: [(Function (list Bool) (list Any))]
               engines: [(Function (list (List Symbol))
                                   (list (List FormalMethodProvider)))])
       identity: 'formal-methods/scope))
