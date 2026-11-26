;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get)
        (only-in :std/list/list every find delete-duplicates/hash)
        "objects.ss")
(export make-github-gitops-scope github-gitops-commit-policy)

(def (github-gitops-commit-policy standards profile-name primary-id checks-value)
  (let* ((standard-list (if (list? standards) standards (list standards)))
         (standard-value
          (find (lambda (std) (equal? profile-name (.get std identity)))
                standard-list))
         (ids (map car checks-value))
         (methods (map cadr checks-value)))
    (unless standard-value
      (error "Unknown project commit standard profile" profile-name))
    (let ((catalog (map (lambda (requirement) (.get requirement identity))
                        (.get standard-value requirements))))
      (unless (and (member primary-id ids)
                   (= (length ids) (length (delete-duplicates/hash ids)))
                   (every (lambda (id) (member id catalog)) ids))
        (error "Project commit requirements do not match the selected standard profile catalog"))
      (unless (= (length methods) (length (delete-duplicates/hash methods)))
        (error "Project commit checks must use distinct methods"))
      (.o standard: standard-value primary: primary-id checks: checks-value))))

(def (make-github-gitops-scope delivery nasa (sdlc #f))
  (let ((standards (append (if sdlc (list (.get sdlc core-standard)) '())
                           (list (car (.get nasa standard standards))))))
    (.o scenario: (make-github-gitops-scenario delivery nasa)
        commit-policy:
        (lambda (profile-name primary-id checks-value)
          (github-gitops-commit-policy standards profile-name primary-id checks-value)))))
