;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o) "objects.ss")
(export make-aitia-scope)

(def (make-aitia-scope project)
  (.o scenario: (make-aitia-scenario (.get project profile-module))))
