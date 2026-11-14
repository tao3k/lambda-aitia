;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .o .cc .get)
        (only-in "../../../modules/gitops/features/github/interface.ss" Feature))
(export github-feature-receiver-test)

(def github-feature-receiver-test
  (test-suite "GitHub Feature receiver composition"
    (test-case "refinement uses the supplied receiver without executing its constructor"
      (let* ((calls '())
             (expected (.o provider: 'custom-receiver))
             (scope (.o change: (lambda arguments
                                  (set! calls (cons arguments calls))
                                  expected)))
             (refined ((.get Feature refine) scope)))
        (check-equal? calls '())
        (check-equal?
          (eq? ((.get refined github change)
                'pull-request "owner/repo" "r2" "feature/x" "develop" 7)
               expected)
          #t)
        (check-equal? calls
          '((github pull-request "owner/repo" "r2" "feature/x" "develop" 7)))))
    (test-case "Feature admission and adapter demand leave the owner constructor lazy"
      (let* ((scope (.o change: (error "owner constructor forced before invocation")
                       unrelated: (error "unrelated owner leaf forced")))
             (refined ((.get Feature refine) scope)))
        (check-equal? (procedure? (.get refined github change)) #t)))
    (test-case "a warmed adapter follows the final receiver after override"
      (let* ((original (.o provider: 'original))
             (replacement (.o provider: 'replacement))
             (scope (.o change: (lambda arguments original)))
             (base ((.get Feature refine) scope))
             (before (.get base github change))
             (child (.cc base 'change (lambda arguments replacement)))
             (after (.get child github change)))
        (check-equal?
          (eq? (before 'pull-request "owner/repo" "r2" "feature/x" "develop" 7) original)
          #t)
        (check-equal?
          (eq? (after 'pull-request "owner/repo" "r2" "feature/x" "develop" 7) replacement)
          #t)
        (check-equal?
          (eq? (before 'pull-request "owner/repo" "r2" "feature/x" "develop" 7) original)
          #t)))))
