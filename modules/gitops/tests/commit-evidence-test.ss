;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :gerbil/core string-prefix? string-contains)
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
    (test-case "advancing the workspace to a new change reopens the obligation"
      (let (view (evaluate (.cc rewritten change: "new-change") (list old-observation)))
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
    (test-case "evidence outside the project or workspace cannot support or reopen an obligation"
      (let (view (evaluate rewritten
                   (list (.cc fresh-observation cut: (.cc rewritten project: "other"))
                         (.cc fresh-observation cut: (.cc rewritten workspace: "other")))))
        (check-equal? (.get view supported) '())
        (check-equal? (.get view stale) '())
        (check-equal? (.get view open) '(("test")))
        (check-equal? (.get view reopened) '())))
    (test-case "NASA profile validates readable narration against current evidence"
      (let* ((gitops (.get lambda-aitia.init.exports modules gitops))
             (select-policy (.get lambda-aitia.init.exports scenarios github-gitops commit-policy))
             (checks '(("SWE-083" "jj.recorded-change") ("SWE-084" "jj.configuration-audit")))
             (policy (select-policy "nasa/sdlc/npr-7150.2" "SWE-084" checks))
             (describe (.get gitops nasa-commit-description))
             (to-receipt (.get gitops commit-check-receipt))
             (guidance (.get gitops nasa-draft-requirements))
             (draft
              (lambda (clauses)
                (call-with-output-string
                 (lambda (port)
                   (for-each
                    (lambda (clause)
                      (display "* Review note\n:PROPERTIES:\n:" port)
                      (display (car clause) port) (display ": " port)
                      (display (cdr clause) port) (display "\n:END:\n" port))
                    clauses)))))
             (execution
              (lambda (id method-name)
                (.o observation: (.cc old-observation identity: id obligation: id)
                    producer: "aitia-runtime/test" method: method-name
                    input-digest: "sha256:input" report-digest: "sha256:report")))
             (candidate
              (lambda (execution-value)
                (.o source: (to-receipt execution-value) execution: execution-value)))
             (record (execution "SWE-083" "jj.recorded-change"))
             (audit (execution "SWE-084" "jj.configuration-audit"))
             (candidates (map candidate (list record audit)))
             (render (lambda (cut rows (source (draft (.get (guidance policy cut rows) clauses)))
                             (context (.get (guidance policy cut rows) context)))
                       (describe policy cut rows "Verify the recorded jj cut"
                                 "Bind the proposed write to the observed configuration." source context)))
             (current-clauses (.get (guidance policy before candidates) clauses))
             (current-draft (draft current-clauses))
             (result (render before candidates))
             (message (.get result description)))
        (check (string-prefix? "Verify the recorded jj cut\n" message) => #t)
        (check-equal? message
          "Verify the recorded jj cut\n\nBind the proposed write to the observed configuration.\n")
        (for-each
         (lambda (metadata)
           (check-equal? (string-contains message metadata) #f))
         '("NASA-Source-Lock:" "NASA-Edition:" "NASA-Requirements:" "JJ-Cut:"
           "AITIA-Draft:" "AITIA-Evidence:" "sha256:" "parent-a"))
        (check-equal? (.get (render before (reverse candidates)) description) message)
        (check (string? (.get result description-digest)) => #t)
        (check-equal? (string-contains current-draft "sha256:") #f)
        (check-equal? (string-contains current-draft "AITIA_CONTEXT") #f)
        (let (forged-draft (string-append current-draft
                             (draft '(("SOURCE_SHA256" . "sha256:forged")))))
          (check-equal? (.get (render before candidates forged-draft) draft-valid?) #f))
        (let* ((receipt (.get (car candidates) source))
               (duplicate (string-append (substring receipt 0 (- (string-length receipt) 1))
                                         ",\"OUTCOME\":\"failed\"}")))
          (check-equal? (.get (render before
                                (list (.cc (car candidates) source: duplicate) (cadr candidates)))
                             description) #f))
        (let* ((fresh (map (lambda (candidate-value)
                            (let (execution-value (.get candidate-value execution))
                              (candidate (.cc execution-value
                                           observation: (.cc (.get execution-value observation)
                                                             cut: rewritten)))))
                          candidates))
               (fresh-draft (draft (.get (guidance policy rewritten fresh) clauses))))
          (check-equal? fresh-draft current-draft)
          (check-equal? (.get (render rewritten fresh fresh-draft
                                    (.get (guidance policy before candidates) context)) draft-valid?) #f)
          (check-equal? (.get (render rewritten fresh fresh-draft) draft-valid?) #t))
        (let* ((alternate (select-policy "nasa/sdlc/npr-7150.2" "SWE-083" checks))
               (result (describe alternate before candidates "Record configuration" "Retain the check evidence."
                                 (draft (.get (guidance alternate before candidates) clauses))
                                 (.get (guidance alternate before candidates) context))))
          (check (string-prefix? "Record configuration\n" (.get result description)) => #t))
        (check-exception
         (select-policy "nasa/sdlc/npr-7150.2" "SWE-999" '(("SWE-999" "forged"))) Error?)
        (check-exception
         (select-policy "nasa/sdlc/npr-7150.2" "SWE-083" (cons (car checks) checks)) Error?)
        (check-equal? (.get (render before (list (car candidates))) description) #f)
        (check-equal? (.get (render rewritten candidates) description) #f)
        (check-equal? (.get (render rewritten candidates) draft-valid?) #t)
        (check-equal? (.get (render rewritten candidates current-draft) draft-valid?) #f)
        (check-equal? (.get (render before candidates (draft (cdr current-clauses))) draft-valid?) #f)
        (check-equal?
         (.get (render before candidates
                 (string-append current-draft (draft '(("AITIA_SUPPORT" . "fabricated")))))
               draft-valid?)
         #f)
        (check-equal?
         (.get (render before candidates
                 (string-append current-draft (draft (list (cadr current-clauses)))))
               draft-valid?)
         #f)
        (let* ((failing (candidate (.cc audit observation: (.cc (.get audit observation) outcome: 'failed))))
               (rows (list (car candidates) failing))
               (clauses (.get (guidance policy before rows) clauses)))
          (check (assoc "AITIA_COUNTEREXAMPLE" clauses) ? pair?)
          (check (assoc "AITIA_OPEN_OBLIGATION" clauses) ? pair?)
          (check-equal? (.get (render before rows (draft clauses)) draft-valid?) #t)
          (check-equal? (.get (render before rows (draft clauses)) description) #f))
        (check-equal? (.get (render rewritten candidates) assessment reopened)
                      '(("SWE-083") ("SWE-084")))
        (let* ((forged (.cc (cadr candidates) execution: (.cc audit report-digest: "forged")))
               (rejected (render before (list (car candidates) forged))))
          (check-equal? (.get rejected description) #f)
          (check-equal? (.get rejected rejected-count) 1))
        (let (wrong (candidate (.cc audit method: "unexpected-method")))
          (check-equal? (.get (render before (list (car candidates) wrong)) description) #f))
        (check-exception
         (describe policy before candidates "SWE-999: Invent a prefix" "Body" current-draft
                   (.get (guidance policy before candidates) context)) Error?)
        (check-exception
         (describe policy before candidates "Review the change" "AITIA-Evidence: forged" current-draft
                   (.get (guidance policy before candidates) context)) Error?)))))
