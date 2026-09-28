;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Organization NASA / domain SDLC / standard family NPR 7150.2.
;;; POO Flow owns the typed namespace, Module and Profile selection.
(import (only-in :clan/poo/object .def)
        (only-in :poo-flow/src/module-system/semantic-module/objects
                 poo-flow-semantic-identity poo-flow-semantic-module)
        (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-profile-export poo-flow-module-profiles)
        :poo-flow/lambda-aitia/modules/sdlc/config)
(export NasaSdlcModule nasa-sdlc-npr7150_2)

(.def (nasa-sdlc-npr7150_2 @ sdlc-nasa-7150-profile)
  (name 'nasa/sdlc/npr-7150.2)
  (role 'standard)
  (standard "nasa/sdlc/npr-7150.2")
  (owner 'lambda-aitia)
  (extends sdlc-nasa-7150-profile)
  (runtime-executed #f))

(def NasaSdlcModule
  (poo-flow-semantic-module
   (poo-flow-semantic-identity 'nasa 'sdlc)
   profiles:
   (poo-flow-module-profiles
    (poo-flow-profile-export 'npr-7150.2 nasa-sdlc-npr7150_2))))
