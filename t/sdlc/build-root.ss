;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Atomic fixture root for t/sdlc/...
(import :poo-flow/lambda-aitia/modules/sdlc/standards/interface)
(include "support/inventories.ss")
(export sdlc-test-fixtures-loaded?)
(def sdlc-test-fixtures-loaded? #t)
