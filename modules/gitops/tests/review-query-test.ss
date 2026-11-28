;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :clan/poo/object .get .ref .o)
        (only-in :clan/poo/type validate)
        (only-in :gerbil/core list-sort string-contains)
        (only-in "../review-lineage.ss" gitops-review-lineage)
        (only-in "../review-query.ss" gitops-review-query)
        (only-in "../types.ss" GitOpsScopeContract)
        (only-in "../config.ss" Config))
(export review-query-test)

(def review-query-test
  (test-suite "Revision queries over verified commit observations"
    (test-case "selects changed files, readback reports and unchanged policy sources"
      (let* ((entry (hash ("kind" "file") ("id" "recorded") ("executable" #f)))
             (changed (hash ("path" "architecture.sysml") ("before" #f) ("after" entry)))
             (config (hash ("path" "project.ss") ("entry" entry)))
             (source (hash ("path" "work.org") ("entry" entry)))
             (scope (validate GitOpsScopeContract Config))
             (graph ((.get scope review-lineage) "revision" (list changed) (list config)
                      '("jj.recorded-change" "jj.configuration-audit" "sysml.parse")
                      '() '("architecture.sysml") (list source)
                      (.o engineering-id: "RFC-7" source: "work.org" element: "work")))
             (result ((.get scope review-query) graph "revision")))
        (check-equal? (.ref (.ref result 'inventory) 'rows)
                      '(("architecture.sysml" "jj.recorded-change")))
        (let (reports (.ref (.ref result 'verified-reports) 'rows))
          (check-equal? (length reports) 3)
          (for-each (lambda (method) (check (and (member (list method) reports) #t) => #t))
                    '("jj.recorded-change" "jj.configuration-audit" "sysml.parse")))
        (check-equal? (.ref (.ref result 'missing-reports) 'rows) '())
        (check-equal? (.ref (.ref result 'model-evidence) 'rows)
                      '(("architecture.sysml" "sysml.parse")))
        (check-equal? (.ref (.ref result 'project-inputs) 'rows) '(("project.ss" #f)))
        (check-equal? (.ref (.ref result 'policy-sources) 'rows) '(("work.org" #f)))
        (let (reference (.ref result 'engineering-reference))
          (check-equal? (.ref reference 'rows) '(("RFC-7" "work" "work.org")))
          (check (number? (string-contains (.ref reference 'gql) "RETURN e.engineeringId")) => #t)
          (check-equal? (.ref reference 'action-authority?) #f))
        (check-exception
         (gitops-review-lineage "revision" '() '() '() '() '() (list source)
           (.o engineering-id: "RFC-7" source: "unobserved.org" element: "work"))
         Error?)
        (check-equal? (.ref (.ref result 'inventory) 'complete?) #f)
        (check-equal? (.ref (.ref result 'inventory) 'action-authority?) #f)
        (check (number? (string-contains (.ref (.ref result 'inventory) 'gql) "enumerated_by")) => #t)
        (check (number? (string-contains (.ref (.ref result 'inventory) 'gql) "revision")) => #t)
        (check-exception (gitops-review-query graph "other-revision") Error?)))
    (test-case "missing reports yield empty partial results"
      (let* ((entry (hash ("kind" "file")))
             (changed (hash ("path" "architecture.sysml") ("before" #f) ("after" entry)))
             (graph (gitops-review-lineage "revision" (list changed) '() '()
                      '("jj.recorded-change" "jj.configuration-audit" "sysml.parse") '()))
             (result (gitops-review-query graph "revision")))
        (let (files (.ref result 'changed-files))
          (check-equal? (.ref files 'rows) '(("architecture.sysml")))
          (check-equal? (.ref files 'revision) "revision")
          (check-equal? (.ref files 'action-authority?) #f))
        (check-equal? (.ref (.ref result 'inventory) 'rows) '())
        (check-equal? (.ref (.ref result 'verified-reports) 'rows) '())
        (check-equal? (.ref (.ref result 'engineering-reference) 'rows) '())
        (let (missing (.ref result 'missing-reports))
          (check-equal? (.ref missing 'revision) "revision")
          (check-equal? (list-sort string<? (map car (.ref missing 'rows)))
                        '("jj.configuration-audit" "jj.recorded-change" "sysml.parse"))
          (check-equal? (.ref missing 'action-authority?) #f)
          (check (number? (string-contains (.ref missing 'gql) "missing_report")) => #t))
        (check-equal? (.ref (.ref result 'model-evidence) 'rows) '())
        (check-equal? (.ref (.ref result 'model-evidence) 'complete?) #f)))
    (test-case "projects related ADRs including superseded decisions and affected domains into GQL"
      (let* ((entry (hash ("kind" "file") ("id" "recorded") ("executable" #f)))
             (changed (hash ("path" "modules/gitops/review-lineage.ss") ("before" #f) ("after" entry)))
             (rfc-source (hash ("path" "docs/rfcs/0007.org") ("entry" entry)))
             (adr-accepted (hash ("path" "docs/adrs/0009.org") ("entry" entry)))
             (adr-old (hash ("path" "docs/adrs/0006.org") ("entry" entry)))
             (scope (validate GitOpsScopeContract Config))
             (graph ((.get scope review-lineage)
                     "rev-adr" (list changed) '() '("jj.recorded-change") '() '()
                     (list rfc-source adr-accepted adr-old)
                     (.o engineering-id: "RFC-0007" source: "docs/rfcs/0007.org" element: "commit-eng")
                     adr-references:
                     (list (.o identity: "ADR-0009" revision: "r2" status: 'accepted
                               relation: 'implements-rfc source: "docs/adrs/0009.org")
                           (.o identity: "ADR-0006" revision: "r1" status: 'superseded
                               relation: 'refines-rfc source: "docs/adrs/0006.org"))
                     affected-domains:
                     (list (.o domain: "gitops" owner-module: "lambda-aitia/modules/gitops"
                               paths: '("modules/gitops/review-lineage.ss")))))
             (result ((.get scope review-query) graph "rev-adr"))
             (decisions (.get result related-decisions))
             (domains (.get result affected-domains)))
        (check-equal? (.get decisions action-authority?) #f)
        (check-equal? (length (.get decisions rows)) 2)
        (check (and (member '("ADR-0009" "r2" "accepted" "implements-rfc" "docs/adrs/0009.org")
                            (.get decisions rows)) #t) => #t)
        (check (and (member '("ADR-0006" "r1" "superseded" "refines-rfc" "docs/adrs/0006.org")
                            (.get decisions rows)) #t) => #t)
        (check (number? (string-contains (.get decisions gql) "relates_decision")) => #t)
        (check-equal? (.get domains action-authority?) #f)
        (check-equal? (.get domains rows)
                      '(("gitops" "lambda-aitia/modules/gitops" "modules/gitops/review-lineage.ss")))
        (check (number? (string-contains (.get domains gql) "owned_by_domain")) => #t)
        (check-exception
         ((.get scope review-lineage)
          "rev-adr" (list changed) '() '() '() '() (list rfc-source) #f
          adr-references:
          (list (.o identity: "ADR-9999" revision: "r1" status: 'accepted
                    relation: 'implements-rfc source: "docs/adrs/unobserved.org")))
         Error?)
        (check-exception
         ((.get scope review-lineage)
          "rev-adr" (list changed) '() '() '() '() '() #f
          affected-domains:
          (list (.o domain: "gitops" owner-module: "lambda-aitia/modules/gitops"
                    paths: '("modules/unrelated.ss"))))
         Error?)))))
