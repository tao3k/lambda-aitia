#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/core path-expand)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :poo-flow/src/feature-system/source-lock-feature
                 sources-lock-freeze
                 write-sources-lock-module)
        :poo-flow/lambda-aitia/modules/sdlc/standards/sources)

(def arguments (cddr (command-line)))
(def root (if (pair? arguments) (car arguments) "."))

(def (read-source path)
  (call-with-input-file (path-expand path root) read-all-as-string))

(def lock
  (sources-lock-freeze
   "lambda-aitia/nasa-npr-7150.2d/sources"
   "2022-03-08"
   Nasa7150_2DSources
   read-source
   '((authority . nasa-nodis)
     (standard . "NPR 7150.2D")
     (effective . "2022-03-08"))))

(call-with-output-file
 (path-expand "modules/sdlc/standards/source.lock.ss" root)
 (lambda (port)
   (write-sources-lock-module port 'Nasa7150_2DSourcesLock lock)))
