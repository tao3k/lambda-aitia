;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/error Error?)
        (only-in :clan/poo/object .ref)
        :poo-flow/src/module-system/declaration/interface
        (only-in :poo-flow/lambda-aitia/modules/assurance/interface
                 assurance-decision?)
        :poo-flow/lambda-aitia/modules/ADR/interface)

(export ADR-module-test)

(def chosen
  (ADR-option "option/aitia" "Aitia owns ADR"
              "Keep software decisions with the software assurance owner."
              'chosen
              '("One owner for decision rationale and invalidation.")
              '("Requires migration from Episteme.")))
(def rejected
  (ADR-option "option/episteme" "Episteme owns ADR"
              "Keep the historical module in the knowledge contribution."
              'rejected '() '("Crosses the Software/SDLC ownership boundary.")))
(def consequences
  (list (ADR-consequence 'positive "ADR and RFC have a typed relationship.")
        (ADR-consequence 'negative "Existing ADR imports must migrate.")))
(def accepted
  (ADR-record
   "0002" "Standardize ADR and connect it to RFC" 'accepted "2026-09-17" "r1"
   "Aitia needs decision rationale that remains distinct from authority."
   "Use a MADR-compatible record and project it into assurance."
   '("Machine-readable lifecycle" "Explicit rationale")
   (list chosen rejected) consequences
   '("Unit tests validate transition and projection rules.")
   '("tao3k maintainers") '("POO Flow maintainers") '("Aitia consumers")
   (list (ADR-link 'refines-rfc "RFC-0001"))))

(def ADR-module-test
  (test-suite "Aitia-owned ADR module"
    (test-case "ADR keeps its acronym and Aitia ownership"
      (check-equal? (ADR-profile? ADRProfile) #t)
      (check-equal? (.ref ADRProfile 'identity) "lambda-aitia/ADR")
      (check-equal? (.ref ADRProfile 'owner) "lambda-aitia")
      (check-equal? (.ref ADRProfile 'module-family) 'ADR))
    (test-case "only the public ADR selection resolves"
      (check-equal?
       (ADR-config (poo-flow-user-module-selection 'custom 'ADR '()))
       ADR-module))

    (test-case "standard record retains drivers, options and consequences"
      (check-equal? (ADR-record-valid? accepted) #t)
      (check-equal? (.ref accepted 'status) 'accepted)
      (check-equal? (length (.ref accepted 'considered-options)) 2)
      (check-exception
       (ADR-record
        "broken" "Incomplete accepted ADR" 'accepted "2026-09-17" "r1"
        "Context" "Decision" '("Driver")
        (list (ADR-option "only" "Only" "No chosen option" 'undecided '() '()))
        '() '() '() '() '() '())
       Error?))

    (test-case "status transitions are forward-only and revisioned"
      (let ((deprecated
             (ADR-transition accepted 'deprecated "2026-09-18" "r2"
                             (.ref accepted 'links))))
        (check-equal? (.ref deprecated 'status) 'deprecated)
        (check-equal? (.ref accepted 'status) 'accepted)
        (check-exception
         (ADR-transition deprecated 'accepted "2026-09-19" "r3"
                         (.ref deprecated 'links))
         Error?)
        (check-exception
         (ADR-transition accepted 'deprecated "2026-09-18" "r1"
                         (.ref accepted 'links))
         Error?)))

    (test-case "supersession creates reciprocal immutable links"
      (let ((replacement
             (ADR-record
              "0003" "Replacement" 'accepted "2026-09-18" "r1"
              "A replacement is required." "Adopt the replacement."
              '("Current architecture")
              (list (ADR-option "new" "New" "Replacement" 'chosen '() '()))
              (list (ADR-consequence 'positive "Old ADR becomes stale."))
              '() '("tao3k maintainers") '() '()
              (list (ADR-link 'refines-rfc "RFC-0001")))))
        (let-values (((old new)
                      (ADR-supersede accepted replacement "2026-09-19"
                                     "r2" "r2")))
          (check-equal? (.ref old 'status) 'superseded)
          (check-equal? (.ref accepted 'status) 'accepted)
          (check-equal? (.ref (car (reverse (.ref old 'links))) 'relation)
                        'superseded-by)
          (check-equal? (.ref (car (reverse (.ref new 'links))) 'relation)
                        'supersedes))
        (check-exception
         (ADR-supersede accepted replacement "2026-09-19" "r2" "r1")
         Error?)))

    (test-case "accepted ADR projects to unknown assurance, never authority"
      (let ((decision (ADR->assurance-decision accepted)))
        (check-equal? (assurance-decision? decision) #t)
        (check-equal? (.ref decision 'state) 'unknown)
        (check-equal? (.ref decision 'kind) 'decision)))))
