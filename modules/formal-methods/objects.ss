;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        "types.ss")

(export aitia-formal-method-provider)

(def (aitia-formal-method-provider engine role artifact-kinds)
  (unless (and (symbol? engine)
               (symbol? role)
               (list? artifact-kinds)
               (andmap symbol? artifact-kinds))
    (error "invalid Aitia formal-method provider"
           engine role artifact-kinds))
  (let ((engine-value engine)
        (role-value role)
        (artifact-kind-values artifact-kinds))
    (.o (kind +aitia-formal-method-provider-kind+)
        (engine engine-value)
        (role role-value)
        (artifact-kinds artifact-kind-values)
        (obligation-only? #t)
        (runtime-executed? #f))))
