;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/string/misc string-subst)
        (only-in :std/encoding/json JSONReadOptions json->string string->json)
        (only-in :lambda-aitia/bindings/operations
                 aitia-org-contract-evaluate-payload
                 aitia-gitops-evaluate-payload
                 aitia-workflow-reconcile-payload
                 aitia-workflow-protocol-step-payload))
(export aitia-operations-test)

(def +aitia-operations-test-json-read-options+
  (JSONReadOptions key-as-symbol: #f
                   array-as-vector: #f
                   object-as-hash: #t))

(def (read-aitia-json payload)
  (string->json payload +aitia-operations-test-json-read-options+))

(def +accepted-change+
  "{\"event\":\"pull-request\",\"repository\":\"tao3k/agentic-ai-lab\",\"revision\":\"0123456789abcdef\",\"source-ref\":\"feature/aitia\",\"target-ref\":\"develop\",\"pull-request\":42,\"checks\":[{\"name\":\"commit-policy\",\"conclusion\":\"success\"},{\"name\":\"build\",\"conclusion\":\"success\"},{\"name\":\"unit-test\",\"conclusion\":\"success\"},{\"name\":\"nasa/sdlc/npr-7150.2\",\"conclusion\":\"success\",\"standardEdition\":\"D\",\"sourceLockDigest\":\"sha256:68113744771506840ed6d7abb4873f87fc6b490d405b9637d446ba4b2ba39108\"}]}")

(def aitia-operations-test
  (test-suite "Aitia Scheme transport"
    (test-case "Orgize evaluates supplied Element facts through the Scheme transport"
      (let* ((request (string-append
                       "{\"rows\":[{\"id\":0,\"parentId\":-1,\"kind\":\"org-data\",\"fieldName\":\"\",\"fieldValue\":\"\"},"
                       "{\"id\":1,\"parentId\":0,\"kind\":\"headline\",\"fieldName\":\"title\",\"fieldValue\":\"Evidence\"}],"
                       "\"scopeId\":0,\"queryKind\":\"headline\",\"fieldName\":\"title\",\"fieldValue\":\"Evidence\","
                       "\"expectation\":\"exactly\",\"expectedCount\":1}"))
             (result (read-aitia-json (aitia-org-contract-evaluate-payload request))))
        (check (hash-get result "matchedCount") => 1)
        (check (hash-get result "passed") => #t)))
    (test-case "Scheme remains the GitOps decision owner"
      (let (decision
            (read-aitia-json
             (aitia-gitops-evaluate-payload +accepted-change+)))
        (check (hash-get decision "accepted") => #t)
        (check (hash-get decision "profile") => "dev")
        (check (hash-get decision "revision") => "0123456789abcdef")))
    (test-case "the predecessor lock cannot authorize the current source domain"
      (let* ((old-change
               (string-subst +accepted-change+
                 "sha256:68113744771506840ed6d7abb4873f87fc6b490d405b9637d446ba4b2ba39108"
                 "sha256:cfb963b8cd81fd8e22e9b47251c1dc7927b85fcdf9ec9366057cd38cb94f338c" count: 1))
             (decision (read-aitia-json (aitia-gitops-evaluate-payload old-change))))
        (check (hash-get decision "accepted") => #f)
        (check (hash-get decision "staleChecks") => '("nasa/sdlc/npr-7150.2"))
        (check (hash-get decision "releaseAuthorized") => #f)
        (check (hash-get decision "runtimeExecuted") => #f)))
    (test-case "Workflow reconciler runs deterministic FunFlow batch and fails closed on raw tool calls"
      (let* ((request
              (json->string
               (hash (project "lambda-aitia")
                     (cut (hash (workspace "default")
                                (change "kxy")
                                (operation "op1")
                                (commit "abc123")
                                (tree "tree123")
                                (parents (vector "p0"))))
                     (naming (hash (projectKey "AITIA")
                                   (primaryLanguage "en")
                                   (languageSources (vector "README.md"))
                                   (types (vector "feat"))
                                   (scopes (vector (hash (name "gitops")
                                                         (paths (vector "modules/workflow")))))
                                   (references (vector (hash (identity "RFC-0008")
                                                             (source "docs/rfcs/0008.org")
                                                             (element "ascent-obligation-funflow"))))))
                     (sources (vector
                               (hash (path "README.md")
                                     (text "English readme.\n"))
                               (hash (path "docs/rfcs/0008.org")
                                     (text "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"))))
                     (paths (vector "modules/workflow/reconcile.ss"))
                     (proposals (vector (hash (identity "AITIA-RFC-0008")
                                              (reference "RFC-0008")
                                              (language "en")
                                              (languageSource "README.md")
                                              (type "feat")
                                              (scope "gitops")
                                              (summary "Add ASCENT FunFlow workflow")
                                              (rationale "Typed DAG"))))
                     (observations (vector (hash (identity "AITIA-RFC-0008")
                                                 (obligation "test")
                                                 (outcome "passed"))))
                     (proposal (hash (kind "raw-single-step-tool-call")
                                     (toolName "shell")
                                     (args (vector "jj" "commit"))))
                     (approvalLive #f)
                     (reconcile #t))))
             (result (read-aitia-json (aitia-workflow-reconcile-payload request)))
             (admission (hash-get result "proposalAdmission")))
        (check (hash-get result "schema") => "lambda-aitia.workflow-reconcile.v1")
        (check (hash-get result "choiceStatus") => "unique-deduction")
        (check (hash-get result "choiceWorldCount") => 1)
        (let ((w0 (car (hash-get result "choiceWorlds"))))
          (check (hash-get w0 "scopeDecision") => "gitops")
          (check (hash-get w0 "scopeDerivationKind") => "deduction")
          (check (hash-get w0 "dispatchDecision") => "human-audit-gate")
          (check (hash-get w0 "dispatchDerivationKind") => "deduction")
          (check (pair? (hash-get w0 "scopeProvenance")) => #t)
          (check (hash-get w0 "actionAuthorized") => #f))
        (check (hash-get result "actionAuthorized") => #f)
        (check (hash-get result "releaseAuthorized") => #f)
        (check (hash-get result "subagentsSpawned") => 0)
        (check (length (hash-get result "initialParallelBatch")) => 2)
        (check (hash-get result "frontierMode") => "quiescent-fixed-point")
        (check (hash-get result "quiescent") => #t)
        (check (length (hash-get result "dischargedObligations")) => 3)
        (check (length (hash-get result "blockedOnHumanObligations")) => 2)
        (check (hash-get admission "admitted") => #f)
        (check (hash-get admission "reason") => "raw-single-step-tool-call-forbidden")
        (check (hash-get admission "actionAuthorized") => #f)))
    (test-case "Scheme 4-state workflow protocol emits host-read frames then converges cleanly on receipts"
      (let* ((base-naming
              (hash (projectKey "AITIA")
                    (primaryLanguage "en")
                    (languageSources (vector "README.md"))
                    (types (vector "feat"))
                    (references (vector (hash (identity "RFC-0008")
                                              (source "docs/rfcs/0008.org")
                                              (element "ascent-obligation-funflow"))))))
             (req1
              (json->string
               (hash (caseId "aitia/case/gitops-commit")
                     (project "lambda-aitia")
                     (directory ".")
                     (requestedPaths (vector "README.md" "docs/rfcs/0008.org"))
                     (modelCheckEnabled #t)
                     (naming base-naming)
                     (receipts (hash)))))
             (step1 (read-aitia-json (aitia-workflow-protocol-step-payload req1)))
             (frames1 (hash-get step1 "frames"))
             (cap-ids (map (lambda (f) (hash-get f "capability")) frames1))
             (receipts2
              (hash ("gitops.jj.observe-cut"
                     (hash (cut (hash (workspace "default")
                                      (change "kxy")
                                      (operation "op1")
                                      (commit "abc123")
                                      (tree "tree123")
                                      (parents (vector "p0"))))
                           (paths (vector "modules/workflow/reconcile.ss"))
                           (sources (vector
                                     (hash (path "README.md") (text "English readme.\n"))
                                     (hash (path "docs/rfcs/0008.org")
                                           (text "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"))))))
                    ("sysml.project-scopes"
                     (vector (hash (name "gitops") (paths (vector "modules/workflow")))))))
             (req2
              (json->string
               (hash (caseId "aitia/case/gitops-commit")
                     (project "lambda-aitia")
                     (directory ".")
                     (naming base-naming)
                     (receipts receipts2)
                     (proposals (vector (hash (identity "AITIA-RFC-0008")
                                              (reference "RFC-0008")
                                              (language "en")
                                              (languageSource "README.md")
                                              (type "feat")
                                              (scope "gitops")
                                              (summary "Add 4-state protocol")
                                              (rationale "Scheme drives host frames"))))
                     (approvalLive #f)
                     (reconcile #t))))
             (step2 (read-aitia-json (aitia-workflow-protocol-step-payload req2)))
             (rec2 (hash-get step2 "reconciliation"))
             (req3
              (json->string
               (hash (caseId "aitia/case/gitops-commit")
                     (project "lambda-aitia")
                     (directory ".")
                     (naming base-naming)
                     (receipts receipts2)
                     (proposals (vector (hash (identity "AITIA-RFC-0008")
                                              (reference "RFC-0008")
                                              (language "en")
                                              (languageSource "README.md")
                                              (type "feat")
                                              (scope "gitops")
                                              (summary "Add 4-state protocol")
                                              (rationale "Scheme drives host frames"))))
                     (approvalLive #t)
                     (reconcile #t))))
             (step3 (read-aitia-json (aitia-workflow-protocol-step-payload req3))))
        ;; Round 1: Scheme requests missing host-read frames with zero authority
        (check (hash-get step1 "schema") => "lambda-aitia.workflow-protocol-step.v1")
        (check (hash-get step1 "state") => "need-host-frames")
        (check (length frames1) => 2)
        (check (and (member "gitops.jj.observe-cut" cap-ids) #t) => #t)
        (check (and (member "sysml.project-scopes" cap-ids) #t) => #t)
        (check (hash-get step1 "actionAuthorized") => #f)
        ;; Round 2 (no approval): converges to need-synthesis-or-human with unique deduction
        (check (hash-get step2 "state") => "need-synthesis-or-human")
        (check (hash-get step2 "frames") => '())
        (check (hash-get rec2 "choiceStatus") => "unique-deduction")
        (check (hash-get rec2 "choiceWorldCount") => 1)
        (check (hash-get step2 "actionAuthorized") => #f)
        ;; Round 2 (with approval): reaches quiescent fixed point with zero authority
        (check (hash-get step3 "state") => "quiescent")
        (check (hash-get step3 "actionAuthorized") => #f)))
    ))
