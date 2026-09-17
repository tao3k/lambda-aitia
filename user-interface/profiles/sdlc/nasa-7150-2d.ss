;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .def)
        :poo-flow/lambda-aitia/modules/sdlc/config)
(export nasa-7150-2d)
(.def (nasa-7150-2d @ sdlc-nasa-7150-profile)
  (name 'nasa-7150-2d)
  (role 'standard)
  (standard "nasa/npr-7150.2d")
  (owner 'lambda-aitia)
  (extends sdlc-nasa-7150-profile)
  (runtime-executed #f))
