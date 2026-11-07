;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/mop .new)
        (only-in :yuanxu/modules/funflow/scenario Scenario)
        (only-in :yuanxu/profile-composition/profile-bundle profiles compose)
        (only-in :yuanxu/profile-composition/selection-syntax use-module))
(export make-aitia-scenario)

(def (make-aitia-scenario project-module)
  (.new Scenario name: 'aitia
        config: (compose profiles (use-module project-module default))))
