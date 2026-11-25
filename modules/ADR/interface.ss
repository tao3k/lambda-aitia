;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Roles and their compiler closure are associated by Yuanxu, not restated here.
(import (only-in :clan/poo/object .def)
        (rename-in (only-in "../assurance/config.ss" Config) (Config Assurance)))
(.def ADR
  identity: 'ADR
  tags: '(software-engineering decisions)
  core: (.o scope-contract: ADRScopeContract
            exports: (.o (:: @ Config)
                         assurance-decision:
                         (ADR-assurance-projector (.get Assurance decision) (.get Assurance digest))
                         decision?: (.get Assurance decision?)))
  features: (.o))
