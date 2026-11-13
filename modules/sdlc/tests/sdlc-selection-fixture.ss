;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/source this-source-file)
        (only-in :gerbil/core string-contains)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules))
(export check-unknown-sdlc-feature!)

(def modules-directory
  (path-expand "../../../modules" (path-directory (this-source-file))))

(def (check-unknown-sdlc-feature! feature)
  (let (path (make-temporary-file-name "aitia-sdlc-selection-"))
    (dynamic-wind void
      (lambda ()
        (call-with-output-file path
          (lambda (port)
            (write `(yuanxu! :load-modules ,modules-directory mode: explicit
                             (assurance) (sdlc ,feature)) port)))
        (let (message (with-catch (lambda (exception)
                      (call-with-output-string
                       (lambda (port) (display-exception exception port))))
          (lambda ()
            (.get (yuanxu-load-modules path) selected-graph)
            #f)))
          (unless (and message (string-contains message "unknown init feature"))
            (error "expected unknown SDLC feature refusal" feature message))))
      (lambda () (clear-temporary-file! path)))))
