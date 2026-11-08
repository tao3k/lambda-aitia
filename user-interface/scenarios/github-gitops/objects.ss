;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Delivery and NASA Profile composition for the GitHub scenario.
(import (only-in :clan/poo/object .get)
        (only-in :clan/poo/mop .new)
        (only-in :yuanxu/modules/funflow/scenario Scenario)
        (only-in :yuanxu/profile-composition/profile-bundle profiles compose)
        (only-in :yuanxu/profile-composition/selection-syntax use-module))
(export make-github-gitops-scenario)

(def (make-github-gitops-scenario delivery nasa)
  (def delivery-module (.get delivery profile-module))
  (def nasa-module (.get nasa profile-module))
  (.new Scenario name: 'github-gitops-sdlc
        config: (compose profiles
                  (use-module delivery-module actions dev staging production)
                  (use-module nasa-module npr-7150.2))))
