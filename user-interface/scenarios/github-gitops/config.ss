;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get)
        (only-in :std/list/list every delete-duplicates/hash)
        "objects.ss")
(export make-github-gitops-scope github-gitops-commit-policy)

(def (github-gitops-commit-policy standard-value profile-name primary-id checks-value)
  (let ((ids (map car checks-value))
        (catalog (map (lambda (requirement) (.get requirement identity))
                      (.get standard-value requirements))))
    (unless (and (equal? profile-name (.get standard-value identity))
                 (member primary-id ids)
                 (= (length ids) (length (delete-duplicates/hash ids)))
                 (every (lambda (id) (member id catalog)) ids))
      (error "Project commit requirements do not match the selected NASA catalog"))
    (.o standard: standard-value primary: primary-id checks: checks-value)))

(def (make-github-gitops-scope delivery nasa)
  (let (standard-value (car (.get nasa standard standards)))
    (.o scenario: (make-github-gitops-scenario delivery nasa)
        commit-policy:
        (lambda (profile-name primary-id checks-value)
          (github-gitops-commit-policy standard-value profile-name primary-id checks-value)))))
