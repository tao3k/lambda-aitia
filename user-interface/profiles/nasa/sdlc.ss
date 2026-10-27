;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Organization NASA / domain SDLC / standard family NPR 7150.2.
;;; Agentic AI Lab owns the typed namespace, Module and Profile selection.
(import (only-in :clan/poo/object .def)
        (only-in :yuanxu/module-system/schema/relations
                 yuanxu-semantic-identity)
        (only-in :yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        :agentic-ai-lab/lambda-aitia/modules/sdlc/config)
(export NasaSdlcModule nasa-sdlc-npr7150_2)

(.def (nasa-sdlc-npr7150_2 @ sdlc-nasa-7150-profile)
  (name 'nasa/sdlc/npr-7150.2)
  (role 'standard)
  (standard "nasa/sdlc/npr-7150.2")
  (owner 'lambda-aitia)
  (extends sdlc-nasa-7150-profile)
  (runtime-executed #f))

(def NasaSdlcModule
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'nasa 'sdlc)
   profiles:
   (yuanxu-module-profiles
    (yuanxu-profile-export 'npr-7150.2 nasa-sdlc-npr7150_2))))
