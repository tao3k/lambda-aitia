;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :gerbil/core string-prefix? string-contains)
        (only-in :clan/poo/object .get .o .cc)
        (only-in "../commit-evidence.ss"
                 gitops-commit-evidence gitops-commit-model-assessment
                 gitops-nasa-draft-requirements
                 gitops-nasa-commit-description gitops-commit-check-receipt gitops-model-gaps)
        (only-in "../commit-semantics.ss" gitops-commit-semantics)
        (only-in "../review-association.ss" gitops-commit-review-association)
        (only-in "../objects.ss" OpenGitOpsProfile)
        (only-in "../func.ss" gitops-change gitops-check gitops-match-change gitops-evaluate-default)
        (only-in "../../sdlc/objects.ss" StandardProfile.)
        (only-in "../../sdlc/standards/nasa-7150-2d-standard.ss" make-nasa-7150-2d-standard)
        (rename-in (only-in "../../nasa-7150-2d-catalog/config.ss" Config)
                   (Config NasaCatalog))
        (only-in "../../../user-interface/scenarios/github-gitops/config.ss"
                 github-gitops-commit-policy))
(export commit-evidence-test)

(def (evaluate cut observations)
  (gitops-commit-evidence cut '("test") observations))

(def before
  (.o project: "project" workspace: "default" change: "same-change"
      operation: "op-a" commit: "commit-a" tree: "tree-a" parents: '("parent-a" "parent-b")))
(def rewritten (.cc before operation: "op-b" commit: "commit-b" tree: "tree-b"))
(def old-observation
  (.o identity: "check-a" cut: before obligation: "test" outcome: 'passed))
(def fresh-observation (.cc old-observation identity: "check-b" cut: rewritten))

(def (with-commit-semantics policy summary-text)
  (let* ((naming (.o project-key: "AITIA" primary-language: #f language-sources: '("design.org") types: '("test")
                    scopes: (list (.o name: "gitops" paths: '("modules/gitops")))
                    references: (list (.o identity: "RFC-7" source: "design.org" element: "work"))))
         (sources (list (.o path: "design.org" cut: before
                            text: "* Work\n:PROPERTIES:\n:ID: work\n:ENGINEERING_ID: RFC-7\n:END:\n")))
         (proposals (list (.o identity: "candidate" reference: "RFC-7" type: "test" scope: "gitops"
                              language: "en" language-source: "design.org"
                              summary: summary-text rationale: "Checks recorded cut admission")))
         (semantic-view (gitops-commit-semantics
                         naming before sources '("modules/gitops/config.ss") proposals)))
    (.cc policy semantics: semantic-view)))

(def commit-evidence-test
  (test-suite "Commit evidence over a recorded GitOps cut"
    (test-case "model checks require an enabled affected path and its exact report"
      (let* ((assess gitops-commit-model-assessment)
             (paths '("design/model.sysml"))
             (report (hash ("documents" paths) ("modelHash" "parsed-model")))
             (observed (hash ("paths" paths) ("status" "passed") ("report" report)))
             (verified (assess #t paths observed)))
        (check-equal? (.get verified open) '())
        (check-equal? (.get verified supported) '(("sysml.parse" "parsed-model")))
        (check-equal? (assess #t '("module.ss") observed) #f)
        (check-equal? (assess #f paths observed) #f)
        (check-equal? (.get (assess #t paths #f) open) '(("sysml.parse")))
        (check-equal? (.get (assess #t '("design/other.sysml") observed) open)
                      '(("sysml.parse")))))
    (test-case "PR association is a distinct current review obligation"
      (let* ((associate gitops-commit-review-association)
             (guidance gitops-nasa-draft-requirements)
             (policy (.o standard: (.o source-lock-digest: "fixture") primary: "SWE-084"
                         checks: '(("SWE-084" "jj.configuration-audit"))))
             (row '("owner/project" "origin" 2 "feature" "main" "base-a" "parent-a" "observed-a"))
             (bookmarks '(("owner/project" "origin" "feature" "parent-a")))
             (bind (lambda (observation (status "observed"))
                     (associate status observation #f bookmarks "parent-a"
                                '(("parent-a" 10 "completed" "success")))))
             (review (lambda (observation)
                       (guidance (.cc policy review-association: (bind observation)) before '())))
             (current (review row)))
        (check-equal? (.get (bind row) associated) row)
        (check-equal? (.get current assessment open) '(("SWE-084")))
        (check-equal? (.get current assessment supported) '())
        (for-each
         (lambda (observation)
           (let (result (review observation))
             (check-equal? (.get (bind observation) associated) #f)
             (check-equal? (.get result assessment open)
                           '(("SWE-084") ("gitops.pull-request")))
             (check (equal? (.get current context) (.get result context)) => #f)))
         '(#f ("owner/project" "origin" 2 "wrong-branch" "main" "base-a" "parent-a" "observed-a")
              ("owner/project" "origin" 2 "feature" "main" "base-a" "retired-head" "observed-a")
              ("impostor/project" "origin" 2 "feature" "main" "base-a" "parent-a" "observed-a")))
        (let* ((route (car bookmarks))
               (absence (associate "no-open-pull-request" #f route bookmarks "parent-a"))
               (stale (associate "no-open-pull-request" #f
                                 '("owner/project" "origin" "feature" "retired-head") bookmarks "parent-a")))
          (check-equal? (.get absence open) '())
          (check-equal? (.get absence absent) route)
          (check-equal? (.get stale open) '(("gitops.pull-request")))
          (check-equal? (.get (bind #f "no-open-pull-request") open) '(("gitops.pull-request"))))
        (check-equal? (.get (bind #f "unavailable") open) '(("gitops.pull-request")))
        (let ((older '("owner/project" "origin" 2 "feature" "main" "base-a" "earlier-head" "observed-a"))
              (reachable '(("owner/project" "origin" "feature" "earlier-head")))
              (conflicted '(("owner/project" "origin" "other" #f))))
          (let* ((checks '(("earlier-head" 10 "completed" "success")))
                 (ancestor (associate "observed" older #f reachable "commit-a" checks))
                 (exact (associate "observed" older #f reachable "earlier-head" checks)))
            (check-equal? (.get ancestor associated) older)
            (check-equal? (.get ancestor open) '())
            (check-equal? (.get ancestor disclosed-open) '(("gitops.pull-request-checks")))
            (check-equal? (.get exact disclosed-open) '()))
          (check-equal? (.get (associate "observed" row #f reachable "commit-a") open) '(("gitops.pull-request")))
          (check-equal? (.get (associate "observed" older #f (append reachable conflicted) "commit-a") open)
                        '(("gitops.pull-request")))
          (check-equal? (.get (associate "no-open-pull-request" #f (car reachable) conflicted "commit-a") open)
                        '(("gitops.pull-request"))))
        (for-each
         (lambda (updated)
           (check-equal? (.get (bind updated) associated) updated)
           (check (equal? (.get current context) (.get (review updated) context)) => #f))
         '(("owner/project" "origin" 2 "feature" "release" "base-a" "parent-a" "observed-a")
           ("owner/project" "origin" 2 "feature" "main" "base-b" "parent-a" "observed-a")
           ("owner/project" "origin" 3 "feature" "main" "base-a" "parent-a" "observed-a")
           ("owner/project" "origin" 2 "feature" "main" "base-a" "parent-a" "observed-b")))))
    (test-case "non-success checks retain their conclusions while blocking promotion"
      (let* ((test-dev (.o (:: @ OpenGitOpsProfile)
                         name: 'test-dev environment: 'dev event: 'pull-request
                         target-ref: "develop" required-checks: '(build test)
                         reconciliation: 'automatic next-profile: 'staging
                         .matches?: (gitops-match-change 'pull-request "develop")))
             (composition (.o profiles: (list test-dev)))
             (change (gitops-change 'github 'pull-request "owner/repo" "r2" "feature/x" "develop" 7))
             (check-for gitops-check)
             (evaluate gitops-evaluate-default))
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
      (let* ((query gitops-model-gaps)
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
      (let* ((standard (make-nasa-7150-2d-standard StandardProfile. NasaCatalog))
             (select-policy (cut github-gitops-commit-policy standard <> <> <>))
             (checks '(("SWE-083" "jj.recorded-change") ("SWE-084" "jj.configuration-audit")))
             (policy (with-commit-semantics
                      (select-policy "nasa/sdlc/npr-7150.2" "SWE-084" checks)
                      "Verify the recorded jj cut"))
             (describe gitops-nasa-commit-description)
             (to-receipt gitops-commit-check-receipt)
             (guidance gitops-nasa-draft-requirements)
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
             (narrate
              (lambda (clauses)
                (.o change: "Bind the proposed write to the observed configuration."
                    evidence: (filter-map
                               (lambda (row)
                                 (cond
                                  ((equal? (car row) "AITIA_SUPPORT")
                                   (list (cdr row) "The recorded check passed."))
                                  ((equal? (car row) "AITIA_COUNTEREXAMPLE")
                                   (list (cdr row) "The recorded check failed."))
                                  (else #f)))
                               clauses)
                    open: (filter-map (lambda (row)
                            (and (equal? (car row) "AITIA_OPEN_OBLIGATION")
                                 (list (cdr row) "Run the missing check on the current cut."))) clauses))))
             (render (lambda (cut rows clauses (source #f) (context #f))
                       (describe policy cut rows
                         "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                         (narrate clauses) (or source (draft clauses)) (or context "")
                         preview?: (not context))))
             (current-clauses (.get (guidance policy before candidates) clauses))
             (current-draft (draft current-clauses))
             (result (render before candidates current-clauses))
             (message (.get result description)))
        (check (string-prefix? "AITIA-RFC-7 test(gitops): Verify the recorded jj cut\n" message) => #t)
        (check-equal? message
          (string-append "AITIA-RFC-7 test(gitops): Verify the recorded jj cut\n\n"
                         "Bind the proposed write to the observed configuration.\n\nEvidence\n"
                         "- SWE-083: The recorded check passed.\n"
                         "- SWE-084: The recorded check passed.\n"))
        (for-each
         (lambda (metadata)
           (check-equal? (string-contains message metadata) #f))
         '("NASA-Source-Lock:" "NASA-Edition:" "NASA-Requirements:" "JJ-Cut:"
           "AITIA-Draft:" "AITIA-Evidence:" "sha256:" "parent-a"))
        (check-equal? (.get (render before (reverse candidates) current-clauses) description) message)
        (let (annotated-draft
              (string-append ":PROPERTIES:\n:OWNER: reviewers\n:END:\n\n"
                             "* Notes\nBackground for the reviewer.\n" current-draft))
          (check-equal? (.get (render before candidates current-clauses annotated-draft) description) message))
        (let* ((edited-org (string-append current-draft "\nMaterial that was not reviewed.\n"))
               (old-context (.get result context))
               (refused (render before candidates current-clauses edited-org old-context))
               (preview (render before candidates current-clauses edited-org))
               (refreshed (render before candidates current-clauses edited-org (.get preview context))))
          (check-equal? (.get refused draft-valid?) #f)
          (check-equal? (.get refused description) #f)
          (check-equal? (.get refreshed description) message))
        (let* ((assess gitops-commit-model-assessment)
               (paths '("design/model.sysml"))
               (report (hash ("documents" paths) ("modelHash" "parsed-model")))
               (observed (hash ("paths" paths) ("status" "passed") ("report" report)))
               (model-policy (.cc policy model-assessment: (assess #t paths observed)))
               (preview (describe model-policy before candidates
                         "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                         (narrate current-clauses) current-draft "" preview?: #t)))
          (check (and (string-contains (.get preview preview-description)
                                       "\n- OpenSysML: Parsed \"design/model.sysml\" at the recorded revision.") #t) => #t)
          (check-equal? (string-contains (.get preview preview-description) "Audit checklist") #f)
          (let (refused (describe model-policy before candidates
                          "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                          (.cc (narrate current-clauses) evidence: '())
                          current-draft "" preview?: #t))
            (check-equal? (.get refused draft-valid?) #f)
            (check-equal? (.get refused preview-description) #f)
            (check-equal? (.get refused description) #f))
          (check-equal? (.get (describe model-policy before candidates
                              "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                              (narrate current-clauses) current-draft (.get result context))
                             description) #f))
        (let* ((associate gitops-commit-review-association)
               (bookmarks '(("owner/project" "origin" "feature" "parent-a")))
               (reviewed-policy
                (lambda (target-revision-value (check-rows '(("parent-a" 10 "completed" "success"))))
                  (.cc policy review-association:
                    (associate "observed"
                      (list "owner/project" "origin" 2 "feature" "main"
                            target-revision-value "parent-a" "observed-a")
                      #f bookmarks "parent-a" check-rows))))
               (assess-draft
                (lambda (policy-value context-value preview-value)
                  (describe policy-value before candidates
                    "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                    (narrate current-clauses) current-draft context-value
                    preview?: preview-value)))
               (original (reviewed-policy "base-a"))
               (advanced (reviewed-policy "base-b"))
               (old-preview (assess-draft original "" #t))
               (new-preview (assess-draft advanced "" #t))
               (stale (assess-draft advanced (.get old-preview context) #f)))
          (check-equal? (.get old-preview preview-description) message)
          (check-equal? (.get new-preview preview-description) message)
          (check-equal? (.get stale draft-valid?) #f)
          (check-equal? (.get stale description) #f)
          (check-equal? (.get (assess-draft advanced (.get new-preview context) #f) description)
                        message)
          (let* ((failing (reviewed-policy "base-a" '(("parent-a" 10 "completed" "failure"))))
                 (passed (reviewed-policy "base-a" '(("parent-a" 10 "completed" "success"))))
                 (unavailable (reviewed-policy "base-a" #f))
                 (clauses (.get (guidance failing before candidates) clauses))
                 (source (draft clauses))
                 (body (narrate clauses))
                 (title "AITIA-RFC-7 test(gitops): Verify the recorded jj cut")
                 (preview (describe failing before candidates title body source "" preview?: #t)))
            (check-equal? (.get preview assessment open) '(("gitops.pull-request-checks")))
            (check-equal? (.get preview assessment blocking-open) '())
            (check (and (string-contains (.get preview description)
                                         "\n\nOpen\n- gitops.pull-request-checks:") #t) => #t)
            (check-equal? (.get (assess-draft failing "" #t) draft-valid?) #f)
            (check-equal? (.get (describe passed before candidates title (narrate current-clauses) current-draft
                                          (.get preview context)) draft-valid?) #f)
            (check-equal? (.get unavailable review-association disclosed-open)
                          '(("gitops.pull-request-checks")))
            (check-equal? (.get passed review-association disclosed-open) '())
            (let* ((empty (reviewed-policy "base-a" '()))
                   (empty-clauses (.get (guidance empty before candidates) clauses))
                   (empty-preview (describe empty before candidates title
                                    (narrate empty-clauses) (draft empty-clauses) "" preview?: #t)))
              (check-equal? (.get empty-preview assessment open) '(("gitops.pull-request-checks")))
              (check-equal? (.get empty-preview assessment blocking-open) '())
              (check-equal? (.get (assess-draft empty "" #t) draft-valid?) #f)
              (check-equal? (.get (assess-draft passed (.get empty-preview context) #f)
                                  draft-valid?) #f))
            (for-each
             (lambda (untrusted)
               (let (review (.get (reviewed-policy "base-a" untrusted) review-association))
                 (check-equal? (.get review disclosed-open) '(("gitops.pull-request-checks")))
                 (check-equal? (.get review context) (.get unavailable review-association context))))
             '((("retired-head" 10 "completed" "success"))
               (("parent-a" 10 "completed" "success") ("parent-a" 10 "completed" "failure"))
               (("parent-a" 10 "completed" "success") ("parent-a" 10 "completed" "success"))
               (("parent-a" 10 "completed"))))))
        (check (string? (.get result description-digest)) => #t)
        (check-equal? (string-contains current-draft "sha256:") #f)
        (check-equal? (string-contains current-draft "AITIA_CONTEXT") #f)
        (let (forged-draft (string-append current-draft
                             (draft '(("SOURCE_SHA256" . "sha256:forged")))))
          (check-equal? (.get (render before candidates current-clauses forged-draft) draft-valid?) #f))
        (let (forged-draft
              (string-append ":PROPERTIES:\n:SOURCE_SHA256: sha256:forged\n:END:\n\n"
                             current-draft))
          (check-equal? (.get (render before candidates current-clauses forged-draft) draft-valid?) #f))
        (let (extra-clause
              (string-append ":PROPERTIES:\n:AITIA_SUPPORT: SWE-999\n:END:\n\n"
                             current-draft))
          (check-equal? (.get (render before candidates current-clauses extra-clause) draft-valid?) #f))
        (let* ((receipt (.get (car candidates) source))
               (duplicate (string-append (substring receipt 0 (- (string-length receipt) 1))
                                         ",\"OUTCOME\":\"failed\"}")))
          (let* ((rows (list (.cc (car candidates) source: duplicate) (cadr candidates)))
                 (clauses (.get (guidance policy before rows) clauses)))
            (check-equal? (.get (render before rows clauses) description) #f)))
        (let* ((fresh (map (lambda (candidate-value)
                            (let (execution-value (.get candidate-value execution))
                              (candidate (.cc execution-value
                                           observation: (.cc (.get execution-value observation)
                                                             cut: rewritten)))))
                          candidates))
               (fresh-clauses (.get (guidance policy rewritten fresh) clauses))
               (fresh-draft (draft fresh-clauses)))
          (check-equal? fresh-draft current-draft)
          (check-equal? (.get (render rewritten fresh fresh-clauses fresh-draft
                                    (.get result context)) draft-valid?) #f)
          (check-equal? (.get (render rewritten fresh fresh-clauses fresh-draft) draft-valid?) #t))
        (let* ((alternate (with-commit-semantics
                           (select-policy "nasa/sdlc/npr-7150.2" "SWE-083" checks) "Record configuration"))
               (result (describe alternate before candidates "AITIA-RFC-7 test(gitops): Record configuration" (narrate current-clauses)
                                 current-draft
                                 "" preview?: #t)))
          (check (string-prefix? "AITIA-RFC-7 test(gitops): Record configuration\n" (.get result description)) => #t))
        (check-exception
         (select-policy "nasa/sdlc/npr-7150.2" "SWE-999" '(("SWE-999" "forged"))) Error?)
        (check-exception
         (select-policy "nasa/sdlc/npr-7150.2" "SWE-083" (cons (car checks) checks)) Error?)
        (check-exception
         (select-policy "nasa/sdlc/npr-7150.2" "SWE-083"
           '(("SWE-083" "jj.recorded-change") ("SWE-084" "jj.recorded-change"))) Error?)
        (let* ((partial (list (car candidates)))
               (clauses (.get (guidance policy before partial) clauses)))
          (check-equal? (.get (render before partial clauses) description) #f))
        (let* ((clauses (.get (guidance policy rewritten candidates) clauses))
               (stale (render rewritten candidates clauses)))
          (check-equal? (.get stale description) #f)
          (check-equal? (.get stale draft-valid?) #t)
          (check-equal? (.get (.get stale assessment) reopened) '(("SWE-083") ("SWE-084")))
          (check-equal? (.get (render rewritten candidates clauses current-draft) draft-valid?) #f))
        (check-equal? (.get (render before candidates current-clauses (draft (cdr current-clauses))) draft-valid?) #f)
        (check-equal?
         (.get (render before candidates current-clauses
                 (string-append current-draft (draft '(("AITIA_SUPPORT" . "fabricated")))))
               draft-valid?)
         #f)
        (check-equal?
         (.get (render before candidates current-clauses
                 (string-append current-draft (draft (list (cadr current-clauses)))))
               draft-valid?)
         #f)
        (let* ((failing (candidate (.cc audit observation: (.cc (.get audit observation) outcome: 'failed))))
               (rows (list (car candidates) failing))
               (clauses (.get (guidance policy before rows) clauses))
               (report (render before rows clauses))
               (preview (.get report preview-description)))
          (check (assoc "AITIA_COUNTEREXAMPLE" clauses) ? pair?)
          (check (assoc "AITIA_OPEN_OBLIGATION" clauses) ? pair?)
          (check-equal? (.get report draft-valid?) #t)
          (check-equal? (.get report description) #f)
          (check (and (string-contains preview
                                       "- SWE-084 (failed): The recorded check failed.") #t) => #t)
          (check (and (string-contains preview
                                       "\n\nOpen\n- SWE-084: Run the missing check on the current cut.") #t) => #t)
          (let (missing (.cc (narrate clauses) open: '()))
            (check-equal? (.get (describe policy before rows
                                  "AITIA-RFC-7 test(gitops): Verify the recorded jj cut" missing
                                  (draft clauses) "" preview?: #t) preview-description) #f)))
        (let* ((failure (candidate (.cc audit observation:
                                      (.cc (.get audit observation) identity: "counter-audit"
                                           outcome: 'failed))))
               (rows (append candidates (list failure)))
               (clauses (.get (guidance policy before rows) clauses))
               (body (.cc (narrate clauses)
                        evidence: '(("SWE-083" "The inventory passed.")
                                    ("SWE-084" "The configuration reports disagree."))))
               (report (describe policy before rows
                         "AITIA-RFC-7 test(gitops): Verify the recorded jj cut"
                         body (draft clauses) "" preview?: #t))
               (preview (.get report preview-description)))
          (check-equal? (.get report rejected-count) 0)
          (check-equal? (.get report draft-valid?) #t)
          (check-equal? (.get report description) #f)
          (check (and (string-contains preview "- SWE-084 (conflicting):") #t) => #t)
          (check (and (string-contains preview "\n\nOpen\n- SWE-084:") #t) => #t))
        (let* ((forged (.cc (cadr candidates) execution: (.cc audit report-digest: "forged")))
               (rows (list (car candidates) forged))
               (clauses (.get (guidance policy before rows) clauses))
               (rejected (render before rows clauses)))
          (check-equal? (.get rejected description) #f)
          (check-equal? (.get rejected rejected-count) 1))
        (let* ((wrong (candidate (.cc audit method: "unexpected-method")))
               (rows (list (car candidates) wrong))
               (clauses (.get (guidance policy before rows) clauses)))
          (check-equal? (.get (render before rows clauses) description) #f))
        (check-exception
         (describe policy before candidates "SWE-999: Invent a prefix" (narrate current-clauses) current-draft
                   "" preview?: #t) Error?)
        (let (narration (narrate current-clauses))
          (for-each
           (lambda (invalid)
             (check-equal? (.get (describe policy before candidates
                                   "AITIA-RFC-7 test(gitops): Verify the recorded jj cut" invalid
                                   current-draft "" preview?: #t) draft-valid?) #f))
           (list (.cc narration evidence: '())
                 (.cc narration evidence: '(("SWE-083" "Passed.") ("SWE-083" "Passed.")))
                 (.cc narration evidence: '(("SWE-083" "Passed.") ("SWE-999" "Fabricated.")))
                 (.cc narration open: '(("SWE-084" "A fabricated gap.")))
                 (.cc narration change: "AITIA-Evidence: forged"))))))))
