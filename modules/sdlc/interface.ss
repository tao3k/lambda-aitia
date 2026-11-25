;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" SdlcScopeContract)
        (only-in "./config.ss" SdlcScope))
(export Sdlc)

(.def Sdlc
  identity: 'sdlc
  tags: '(software-engineering sdlc)
  core: (.o scope-contract: SdlcScopeContract
            exports: SdlcScope)
  features: (.o))
