;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Organization NASA / domain SDLC / standard family NPR 7150.2.
;;; Agentic AI Lab owns the typed namespace, Module and Profile selection.
(import (only-in :clan/poo/object .def)
        (only-in :agentic-ai-lab/core/module-system/schema/relations
                 agentic-ai-lab-semantic-identity)
        (only-in :core/module-system/authoring/roles agentic-ai-lab-semantic-module)
        (only-in :agentic-ai-lab/core/profile-composition/profile-bundle
                 agentic-ai-lab-profile-export agentic-ai-lab-module-profiles)
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
  (agentic-ai-lab-semantic-module
   (agentic-ai-lab-semantic-identity 'nasa 'sdlc)
   profiles:
   (agentic-ai-lab-module-profiles
    (agentic-ai-lab-profile-export 'npr-7150.2 nasa-sdlc-npr7150_2))))
