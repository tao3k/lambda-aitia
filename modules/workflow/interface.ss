;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" WorkflowScopeContract)
        (only-in "./config.ss" Config))
(export Workflow)

(.def Workflow
  identity: 'workflow
  tags: '(software-engineering workflow funflow ascent)
  core: (.o scope-contract: WorkflowScopeContract
            exports: Config)
  features: (.o))
