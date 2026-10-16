;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :clan/poo/object .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface
        :poo-flow/lambda-aitia/modules/sdlc/interface)

(export design-implementation-test)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def guarantee
  (sdlc-design-guarantee "unique-effect" "g1" "At most one external commit"))
(def cancellation
  (sdlc-design-guarantee "cancel-before-commit" "g1" "No new commit after cancellation"))
(def (contract revision guarantees)
  (sdlc-design-contract "job-executor" revision "ADR/job-executor"
                        '("execute-job") '("job-ledger")
                        '("external-operation") '() guarantees '()))
(def baseline (contract "r1" (list guarantee)))
(def source
  (assurance-artifact "artifact/job-executor" "s1" 'supported digest-a
                      owner: "lambda-aitia" media-kind: 'scheme-source
                      provenance: '("repository")))
(def (snapshot source-value
               source-revisions: (revisions (list (cons "artifact/job-executor" "s1")))
               unresolved: (unresolved '()))
  (assurance-snapshot "snapshot/job-executor" "cut-1" "graph/job-executor"
                      revisions '() "fact-cut-1" "policy/design" "p1"
                      (list source-value) '() unresolved: unresolved))
(def current-snapshot (snapshot source))
(def current-link
  (sdlc-design-implementation-link baseline guarantee source current-snapshot))

(def design-implementation-test
  (test-suite "SDLC design to source mapping"
    (test-case "exact assurance snapshot binding is current but not conformance"
      (let (review
            (sdlc-design-implementation-review baseline current-snapshot
                                               (list current-link)))
        (check-equal? (.ref review 'mapping-current?) #t)
        (check-equal? (.ref review 'mapped-guarantees) '("unique-effect"))
        (check-equal? (.ref review 'unmapped-guarantees) '())
        (check-equal? (.ref review 'implementation-conforms?) #f)
        (check-equal? (.ref review 'evidence-admitted?) #f)
        (check-equal? (.ref review 'release-authorized?) #f)))
    (test-case "new contract revision or unmapped guarantee reopens coverage"
      (let* ((next (contract "r2" (list guarantee cancellation)))
             (review (sdlc-design-implementation-review
                      next current-snapshot (list current-link))))
        (check-equal? (.ref review 'mapping-current?) #f)
        (check-equal? (.ref review 'unmapped-guarantees)
                      '("cancel-before-commit" "unique-effect"))
        (check-equal? (.ref (car (.ref review 'blocked-links)) 'blocker)
                      'contract-changed)))
    (test-case "same-revision contract mutation cannot reuse an old link"
      (let* ((changed-guarantee
              (sdlc-design-guarantee "unique-effect" "g1" "At most two commits"))
             (changed-contract (contract "r1" (list changed-guarantee)))
             (review (sdlc-design-implementation-review
                      changed-contract current-snapshot (list current-link))))
        (check-equal? (.ref review 'mapping-current?) #f)
        (check-equal? (.ref (car (.ref review 'blocked-links)) 'blocker)
                      'contract-changed)))
    (test-case "source change invalidates exact snapshot binding"
      (let* ((new-source
              (assurance-artifact "artifact/job-executor" "s1" 'supported digest-b
                                  owner: "lambda-aitia" media-kind: 'scheme-source
                                  provenance: '("repository")))
             (changed (snapshot new-source))
             (review (sdlc-design-implementation-review
                      baseline changed (list current-link))))
        (check-equal? (.ref review 'mapping-current?) #f)
        (check-equal? (.ref review 'unmapped-guarantees) '("unique-effect"))
        (check-equal? (.ref (car (.ref review 'blocked-links)) 'blocker)
                      'snapshot-changed)))
    (test-case "unbound source and unresolved snapshot cannot qualify"
      (let* ((unbound (snapshot source source-revisions: '()))
             (link (sdlc-design-implementation-link
                    baseline guarantee source unbound))
             (review (sdlc-design-implementation-review baseline unbound
                                                        (list link)))
             (frontier (snapshot source unresolved: '("artifact/missing")))
             (frontier-link
              (sdlc-design-implementation-link baseline guarantee source frontier))
             (frontier-review
              (sdlc-design-implementation-review baseline frontier
                                                 (list frontier-link))))
        (check-equal? (.ref (car (.ref review 'blocked-links)) 'blocker)
                      'source-unbound)
        (check-equal? (.ref frontier-review 'mapping-current?) #f)
        (check-equal? (.ref frontier-review 'snapshot-frontier?) #t)))
    (test-case "a different source presentation cannot match a canonical cut"
      (let* ((different
              (assurance-artifact "artifact/job-executor" "s1" 'supported digest-b
                                  owner: "lambda-aitia" media-kind: 'scheme-source
                                  provenance: '("repository")))
             (link (sdlc-design-implementation-link
                    baseline guarantee different current-snapshot))
             (review (sdlc-design-implementation-review baseline current-snapshot
                                                        (list link))))
        (check-equal? (.ref (car (.ref review 'blocked-links)) 'blocker)
                      'source-changed)))))
