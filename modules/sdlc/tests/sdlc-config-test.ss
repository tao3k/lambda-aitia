;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/contribution/objects admit-contributions)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export sdlc-config-test)

(def modules-directory
  (path-expand "../../../modules" (path-directory (this-source-file))))

(def (refused-selection declaration)
  (let (path (make-temporary-file-name "aitia-sdlc-selection-"))
    (dynamic-wind void
      (lambda ()
        (call-with-output-file path
          (lambda (port)
            (write `(yuanxu! source: ,modules-directory mode: explicit
                             (assurance) ,declaration) port)))
        (with-catch error-message
          (lambda ()
            (.get (yuanxu-load-modules path) selected-graph)
            #f)))
      (lambda () (clear-temporary-file! path)))))

(def sdlc-config-test
  (test-suite "SDLC init selection projection"
    (test-case "the selected SDLC scope is standard-free"
      (let* ((sdlc (.get lambda-aitia.init.exports modules sdlc))
             (contribution (.get sdlc default-contribution)))
        (check-equal? (.get sdlc profile standards) '())
        (check-equal? (.get contribution profile standards) '())
        (check-equal? (.get (admit-contributions (list contribution) '()) accepted?) #t)))
    (test-case "NASA standards cannot be selected as SDLC features"
      (for-each (lambda (feature)
                  (let (message (refused-selection (list 'sdlc feature)))
                    (check-equal? message "unknown init feature")))
                '(+nasa +npr-7150.2)))))
