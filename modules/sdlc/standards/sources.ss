;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Editable NASA source declarations. Digests and byte counts are generated
;;; from the checked-in bytes into source.lock.ss.

(import (only-in :clan/poo/object .o)
        (only-in :poo-flow/src/feature-system/source-lock-feature
                 SourceReference. SourceLockEntry. SourcesLock.))

(export +nasa-7150-2d-edition-identity+
        +nasa-7150-2d-edition-canonical-uri+
        +nasa-7150-2d-source-ref+
        Nasa7150_2DSources
        Nasa7150_2DSourcesLock)

(def +nasa-7150-2d-edition-identity+ "nasa/npr-7150.2d/2022-03-08")
(def +nasa-7150-2d-edition-canonical-uri+
  "https://nodis3.gsfc.nasa.gov/N_PR_7150_002D_")
(def +nasa-7150-2d-source-ref+
  "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_")

(def (nasa-source identity-value file-value page-value section-value)
  (.o (:: @ SourceReference.)
      identity: identity-value
      path: (string-append "modules/sdlc/standards/sources/" file-value)
      canonical-uri: (string-append +nasa-7150-2d-source-ref+
                                    "&page_name=" page-value)
      exact-version: "2022-03-08"
      representation: 'html
      metadata: (list (cons 'section section-value))))

(def Nasa7150_2DSources
  (list (nasa-source "nasa/npr-7150.2d/chapter2"
                     "chapter2.html" "Chapter2" 'chapter-2)
        (nasa-source "nasa/npr-7150.2d/chapter3"
                     "chapter3.html" "Chapter3" 'chapter-3)
        (nasa-source "nasa/npr-7150.2d/chapter4"
                     "chapter4.html" "Chapter4" 'chapter-4)
        (nasa-source "nasa/npr-7150.2d/chapter5"
                     "chapter5.html" "Chapter5" 'chapter-5)
        (nasa-source "nasa/npr-7150.2d/chapter6"
                     "chapter6.html" "Chapter6" 'chapter-6)
        (nasa-source "nasa/npr-7150.2d/appendix-c"
                     "appendix-c.html" "AppendixC" 'appendix-c)))

(include "source.lock.ss")
