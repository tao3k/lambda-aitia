;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/misc/ports read-file-string)
        (only-in :clan/poo/object .get .o .cc)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export commit-evidence-test)

(def (evaluate cut observations)
  ((.get lambda-aitia.init.exports modules gitops commit-evidence)
   cut '("test") observations))

(def before
  (.o project: "project" workspace: "default" change: "same-change"
      operation: "op-a" commit: "commit-a" tree: "tree-a" parents: '("parent-a" "parent-b")))
(def rewritten (.cc before operation: "op-b" commit: "commit-b" tree: "tree-b"))
(def old-observation
  (.o identity: "check-a" cut: before obligation: "test" outcome: 'passed))
(def fresh-observation (.cc old-observation identity: "check-b" cut: rewritten))

(def commit-evidence-test
  (test-suite "Commit evidence over a recorded GitOps cut"
    (test-case "non-success checks retain their conclusions while blocking promotion"
      (let* ((gitops (.get lambda-aitia.init.exports modules gitops))
             (test-dev (.o (:: @ (.get gitops profile))
                         name: 'test-dev environment: 'dev event: 'pull-request
                         target-ref: "develop" required-checks: '(build test)
                         reconciliation: 'automatic next-profile: 'staging
                         .matches?: ((.get gitops match-change) 'pull-request "develop")))
             (gitops-change (.get gitops change))
             (composition (.o profiles: (list test-dev)))
             (change (gitops-change 'github 'pull-request "owner/repo" "r2" "feature/x" "develop" 7))
             (check-for (.get gitops check))
             (evaluate (.get gitops evaluate)))
        (for-each
         (lambda (conclusion)
           (let* ((build-check (check-for 'build "owner/repo" "r2" conclusion))
                  (decision (evaluate composition change
                              (list build-check (check-for 'test "owner/repo" "r2" 'success)))))
             (check-equal? (.ref decision 'accepted) #f)
             (check-equal? (.ref decision 'failed-checks) '(build))
             (check-equal? (map (lambda (row) (.ref row 'conclusion))
                                (.ref decision 'check-blockers))
                           (list conclusion))))
         '(failure cancelled pending skipped))))
    (test-case "Scheme and JSON use the same project configuration Contract"
      (let* ((scope (.get lambda-aitia.init.exports modules gitops))
             (configure (.get scope project-config))
             (decode (.get scope project-config-json))
             (manifest (read-file-string ".agents/aita/project.json"))
             (effective (decode manifest))
             (scheme (configure (.o schemaVersion: 1 scenario: "custom")))
             (minimal (decode "{\"schemaVersion\":1}")))
        (check-equal? (hash-get effective 'scenario) "aitia")
        (check-equal? (hash-get scheme 'scenario) "custom")
        (check-equal? (hash-get minimal 'scenario) "aitia")
        (check-equal? (hash-get minimal 'ascent) #())
        (check-equal? (decode "{}") #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"models\":{}}") #f)))
    (test-case "model gap query resolves only declared and indexed references"
      (let* ((query (.get lambda-aitia.init.exports modules gitops model-gaps))
             (model-id "CommitEvidence")
             (design-id "AitiaCommit::exactCut")
             (property-id "currentSupportRequired")
             (mapping (.o design: design-id model: model-id property: property-id))
             (present (.o model: model-id property: property-id))
             (valid (query (list mapping) (list design-id) (list present)))
             (missing (query (list mapping) (list design-id)
                             (list (.cc present model: "OtherModel"))))
             (unresolved (query (list mapping) '() (list present))))
        (check-equal? (.get valid resolved-mapping) (list (list design-id model-id property-id)))
        (check-equal? (.get valid missing-property) '())
        (check-equal? (.get missing missing-property) (list (list design-id model-id property-id)))
        (check-equal? (.get missing resolved-mapping) '())
        (check-equal? (.get unresolved unresolved-design) (list (list design-id model-id property-id)))
        (check-equal? (.get unresolved resolved-mapping) '())))
    (test-case "current evidence supports its obligation"
      (let (view (evaluate before (list old-observation)))
        (check-equal? (.get view supported) '(("check-a" "test")))
        (check-equal? (.get view open) '())))
    (test-case "same change after rewrite preserves stale evidence and reopens the obligation"
      (let (view (evaluate rewritten (list old-observation)))
        (check-equal? (.get view stale) '(("check-a" "test")))
        (check-equal? (.get view supported) '())
        (check-equal? (.get view reopened) '(("test")))))
    (test-case "ordered parents participate in exact evidence identity"
      (let (view (evaluate (.cc before parents: '("parent-b" "parent-a"))
                            (list old-observation)))
        (check-equal? (.get view supported) '())
        (check-equal? (.get view stale) '(("check-a" "test")))
        (check-equal? (.get view reopened) '(("test")))))
    (test-case "fresh evidence satisfies the obligation while retaining stale history"
      (let (view (evaluate rewritten (list old-observation fresh-observation)))
        (check-equal? (.get view stale) '(("check-a" "test")))
        (check-equal? (.get view supported) '(("check-b" "test")))
        (check-equal? (.get view reopened) '())))
    (test-case "a stale failure does not count as lost support"
      (let (view (evaluate rewritten (list (.cc old-observation outcome: 'failed))))
        (check-equal? (.get view stale) '(("check-a" "test")))
        (check-equal? (.get view open) '(("test")))
        (check-equal? (.get view reopened) '())))
    (test-case "a current contradiction keeps the obligation open"
      (let (view (evaluate rewritten
                   (list fresh-observation
                         (.cc fresh-observation identity: "check-failed" outcome: 'failed))))
        (check-equal? (.get view supported) '(("check-b" "test")))
        (check-equal? (.get view contradicted) '(("check-failed" "test")))
        (check-equal? (.get view open) '(("test")))))
    (test-case "other project evidence cannot support or reopen this obligation"
      (let (view (evaluate rewritten
                   (list (.cc fresh-observation cut: (.cc rewritten project: "other")))))
        (check-equal? (.get view supported) '())
        (check-equal? (.get view stale) '())
        (check-equal? (.get view open) '(("test")))
        (check-equal? (.get view reopened) '())))))
