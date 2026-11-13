;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o)
        (only-in :gerbil-ascent/program/syntax ascent)
        (only-in :gerbil-ascent/program/api gerbil-ascent-evaluate-program))
(export gitops-commit-review-association)

;; JJ supplies the reachable bookmark candidates at the current cut. The
;; provider target belongs to the observed PR, not to the project config.
;; An ancestor establishes association only, never evidence for the candidate.
(def (gitops-commit-review-association status observation absence bookmarks (checks '()))
  (let* ((observed (if observation (list observation) '()))
         (absences (if absence (list absence) '()))
         (unique (match bookmarks
                   ([[repository remote source head]]
                    (if (string? head) (list (list repository remote source head)) '()))
                   (else '())))
         (program
          (ascent
           (relation provider_status (status) (list (list status)))
           (relation unique_bookmark (repository remote source head) unique)
           (relation observed (repository remote number source target target_revision head updated_at) observed)
           (relation absent (repository remote source head) absences)
           (relation check_inventory (available) (list (list (and checks #t))))
           (relation observed_check (head id state conclusion) (or checks '()))
           (relation associated (repository remote number source target target_revision head updated_at))
           (relation verified_absence (repository remote source head))
           (relation successful_check (head id))
           (relation disclosed_open (obligation))
           ((associated P M N S T B H U) <-- (provider_status (lit "observed"))
            (observed P M N S T B H U) (unique_bookmark P M S H))
           ((verified_absence P M S H) <-- (provider_status (lit "no-open-pull-request"))
            (absent P M S H) (unique_bookmark P M S H))
           ((successful_check H I) <-- (observed_check H I (lit "completed") (lit "success")))
           ((disclosed_open (lit "gitops.pull-request-checks")) <--
            (associated _ _ _ _ _ _ H _) (observed_check H I _ _) (not (successful_check H I)))
           ((disclosed_open (lit "gitops.pull-request-checks")) <--
            (associated _ _ _ _ _ _ _ _) (check_inventory (lit #f)))))
         (result (gerbil-ascent-evaluate-program program)))
    (unless (.get result finished) (error "incomplete commit review association query"))
    (match ((.get result rows-of) 'associated)
      ([row] (.o context: (list row checks) associated: row absent: #f open: '()
                 disclosed-open: ((.get result rows-of) 'disclosed_open)))
      (else
       (match ((.get result rows-of) 'verified_absence)
         ([row] (.o context: (list status row) associated: #f absent: row open: '()
                    disclosed-open: '()))
         (else (.o context: (list status bookmarks) associated: #f absent: #f
                   open: '(("gitops.pull-request")) disclosed-open: '())))))))
