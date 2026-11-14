;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Roles and their compiler closure are associated by Yuanxu, not restated here.
(import (only-in :tao3k/yuanxu/module-system/source/declaration .def))
(.def ADR
  identity: 'ADR
  tags: '(software-engineering decisions)
  core: (.o requires: (.o Assurance:
                          (.o module-id: 'assurance))
            scope-contract: ADRScopeContract
            exports: (.o (:: @ Config)
                         assurance-decision:
                         (ADR-assurance-projector (.get Assurance decision) (.get Assurance digest))
                         decision?: (.get Assurance decision?)))
  features: (.o))
