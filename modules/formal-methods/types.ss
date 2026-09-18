;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot? object?))

(export +aitia-formal-method-provider-kind+
        aitia-formal-method-provider?)

(def +aitia-formal-method-provider-kind+
  'lambda-aitia.formal-method-provider)

(def (aitia-formal-method-provider? value)
  (and (object? value)
       (.slot? value 'kind)
       (eq? (.ref value 'kind) +aitia-formal-method-provider-kind+)
       (.slot? value 'engine)
       (symbol? (.ref value 'engine))
       (.slot? value 'role)
       (symbol? (.ref value 'role))
       (.slot? value 'artifact-kinds)
       (list? (.ref value 'artifact-kinds))
       (.slot? value 'obligation-only?)
       (.ref value 'obligation-only?)
       (.slot? value 'runtime-executed?)
       (eq? (.ref value 'runtime-executed?) #f)))
