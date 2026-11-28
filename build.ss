#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/build-script defbuild-script)
        (only-in :std/source this-source-file)
        (only-in "./init.ss" std-make-spec))

(cond-expand
 (darwin (defbuild-script std-make-spec optimize: #f))
 (else (defbuild-script std-make-spec)))
