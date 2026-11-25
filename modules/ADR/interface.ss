;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .get .o)
        (only-in "./types.ss" ADRScopeContract)
        (only-in "./func.ss" ADR-assurance-projector)
        (only-in "./config.ss" Config)
        (rename-in (only-in "../assurance/config.ss" Config) (Config Assurance)))
(export ADR)

(.def ADR
  identity: 'ADR
  tags: '(software-engineering decisions)
  core: (.o scope-contract: ADRScopeContract
            exports: (.o (:: @ Config)
                         assurance-decision:
                         (ADR-assurance-projector (.get Assurance decision) (.get Assurance digest))
                         decision?: (.get Assurance decision?)))
  features: (.o))
