;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        "types.ss")

(export aitia-formal-method-provider-engines)

(def (aitia-formal-method-provider-engines providers)
  (unless (and (list? providers)
               (andmap aitia-formal-method-provider? providers))
    (error "formal-method engine projection requires provider values"
           providers))
  (map (lambda (provider) (.ref provider 'engine)) providers))
