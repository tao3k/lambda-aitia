;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Organization NASA / domain SDLC / standard family NPR 7150.2.
;;; Agentic AI Lab owns the typed namespace, Module and Profile selection.
(import (only-in :clan/poo/object .get .o)
        (only-in "../../../modules/sdlc/standards/nasa-7150-2d-standard.ss" make-nasa-7150-2d-standard))
(export make-nasa-profile)

(def (make-nasa-profile sdlc catalog)
  (def sdlc-nasa-7150-profile
    ((.get sdlc with-standards) (.get sdlc profile) (list (make-nasa-7150-2d-standard (.get sdlc standard-profile) catalog))))

  (.o (:: @ sdlc-nasa-7150-profile)
      name: 'nasa/sdlc/npr-7150.2 role: 'standard
      standard: "nasa/sdlc/npr-7150.2" owner: 'lambda-aitia
      extends: sdlc-nasa-7150-profile runtime-executed: #f))
