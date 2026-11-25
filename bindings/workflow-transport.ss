;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; JSON/POO transport for Lambda Aitia's RFC 0008 native ASCENT Obligation
;;; Graph + FunFlow CAS DAG reconciler (`modules/workflow`).
;;; Projects admitted POO frontier facts into a single wire envelope for Rust
;;; `AitiaSession`, CLI (`aitia flow`), and Python consumers.

(import (only-in :std/encoding/json json->string)
        (only-in :clan/poo/object .get .o .ref .slot? object?)
        (only-in "../init.ss" lambda-aitia.init.exports)
        "transport-common.ss")

(export aitia-workflow-reconcile-payload)

(def (json-workflow-naming input)
  (.o project-key: (json-required input "projectKey")
      primary-language: (hash-get input "primaryLanguage")
      language-sources: (json-list input "languageSources")
      types: (json-list input "types")
      scopes: (map (lambda (row)
                     (.o name: (json-required row "name")
                         paths: (json-list row "paths")))
                   (json-list input "scopes"))
      references: (map (lambda (row)
                         (.o identity: (json-required row "identity")
                             source: (json-required row "source")
                             element: (json-required row "element")))
                       (json-list input "references"))))

(def (json-workflow-sources input cut)
  (map (lambda (row)
         (.o path: (json-required row "path")
             text: (json-required row "text")
             (cut := cut)))
       (json-list input "sources")))

(def (json-workflow-proposals input)
  (let ((rows (or (hash-get input "proposals") '())))
    (map (lambda (row)
           (.o identity: (json-required row "identity")
               reference: (json-required row "reference")
               language: (json-required row "language")
               language-source: (json-required row "languageSource")
               type: (json-required row "type")
               scope: (json-required row "scope")
               summary: (json-required row "summary")
               rationale: (json-required row "rationale")))
         (if (vector? rows) (vector->list rows) rows))))

(def (json-workflow-observations input cut)
  (let ((rows (or (hash-get input "observations") '())))
    (map (lambda (row)
           (.o (cut := cut)
               identity: (json-required row "identity")
               obligation: (json-required row "obligation")
               outcome: (json-symbol row "outcome")))
         (if (vector? rows) (vector->list rows) rows))))

(def (json-workflow-proposal wf raw)
  (let ((kind (json-required raw "kind")))
    (cond
     ((equal? kind "raw-single-step-tool-call")
      ((.get wf raw-tool-call)
       (string->symbol (json-required raw "toolName"))
       (json-list raw "args")))
     ((equal? kind "bounded-competing-branches")
      ((.get wf competing-branches)
       (map (lambda (row)
              (.o (branch-id := (string->symbol (json-required row "branchId")))
                  (description := (or (hash-get row "description") ""))
                  (supports-hypotheses := (let ((v (or (hash-get row "supportsHypotheses") '())))
                                            (if (vector? v) (vector->list v) v)))
                  (contradicts-hypotheses := (let ((v (or (hash-get row "contradictsHypotheses") '())))
                                               (if (vector? v) (vector->list v) v)))
                  (open-questions := (let ((v (or (hash-get row "openQuestions") '())))
                                       (if (vector? v) (vector->list v) v)))))
            (json-list raw "branches"))))
     (else
      (error "unsupported workflow oracle proposal kind" kind)))))

(def (obligation->json ob)
  (hash (id (.ref ob 'obligation-id))
        (title (.ref ob 'title))
        (requiredEvidence (list->vector (.ref ob 'required-evidence-ids)))
        (dependsOn (list->vector (.ref ob 'depends-on)))
        (activeDefeaters (symbols->json (.ref ob 'active-defeaters)))))

(def (hole->json hole)
  (hash (id (.ref hole 'hole-id))
        (obligation (.ref hole 'obligation-id))
        (description (.ref hole 'description))
        (maxBranches (.ref hole 'max-branches))))

(def (hypothesis->json hyp)
  (hash (id (.ref hyp 'hypothesis-id))
        (claim (.ref hyp 'claim))
        (openQuestions (list->vector
                        (map (lambda (q)
                               (if (string? q) q (call-with-output-string (lambda (p) (write q p)))))
                             (.ref hyp 'open-questions))))))

(def (branch-matrix->json matrix)
  (and matrix
       (hash (kind (symbol->string (.ref matrix 'kind)))
             (branchCount (.ref matrix 'branch-count))
             (hypothesisCount (.ref matrix 'hypothesis-count))
             (actionAuthorized #f)
             (rows
              (list->vector
               (map (lambda (row)
                      (hash (branchId (symbol->string (.ref row 'branch-id)))
                            (description (.ref row 'description))
                            (actionAuthorized #f)
                            (hypothesisAssessments
                             (list->vector
                              (map (lambda (a)
                                     (hash (hypothesisId (.ref a 'hypothesis-id))
                                           (relation (symbol->string (.ref a 'relation)))
                                           (activeDefeaters (symbols->json (.ref a 'active-defeaters)))))
                                   (.ref row 'hypothesis-assessments))))))
                    (.ref matrix 'rows)))))))

(def (aitia-workflow-reconcile-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((input (read-aitia-json payload))
         (wf (.get lambda-aitia.init.exports modules workflow))
         (project (json-required input "project"))
         (cut (replay-cut project (json-required input "cut")))
         (naming (json-workflow-naming (json-required input "naming")))
         (sources (json-workflow-sources input cut))
         (paths (json-list input "paths"))
         (proposals (json-workflow-proposals input))
         (observations (json-workflow-observations input cut))
         (approval-live? (and (hash-get input "approvalLive") #t))
         (raw-reconcile (hash-get input "reconcile"))
         (run-reconcile? (if (boolean? raw-reconcile) raw-reconcile #t))
         (graph ((.get wf gitops-commit-graph)
                 naming cut sources paths proposals
                 observations: observations
                 approval-live?: approval-live?))
         (initial ((.get wf reconcile-frontier) graph))
         (initial-plan (.get initial funflow-plan))
         (initial-batch (if (and initial-plan (.ref initial-plan 'valid?))
                          (map (lambda (t) (.ref t 'task-id)) (.ref initial-plan 'parallel-batch))
                          '()))
         (subagents (if initial-plan (.ref initial-plan 'subagents-spawned) 0))
         (raw-proposal (hash-get input "proposal"))
         (proposal-res (and raw-proposal
                            ((.get wf admit-proposal)
                             graph
                             (json-workflow-proposal wf raw-proposal))))
         (report (if run-reconcile? ((.get wf reconcile) graph) #f))
         (final-frontier (if report (.ref report 'final-frontier) (.get initial frontier)))
         (semantics (.get graph semantics-assessment)))
    (json->string
     (hash (schema "lambda-aitia.workflow-reconcile.v1")
           (project project)
           (commit (.get cut commit))
           (initialFrontierMode (symbol->string (.get initial frontier-mode)))
           (initialParallelBatch (list->vector initial-batch))
           (subagentsSpawned subagents)
           (frontierMode (symbol->string (.ref final-frontier 'frontier-mode)))
           (quiescent (if report (.ref report 'quiescent?) (.get initial quiescent?)))
           (totalLlmCalls (if report (.ref report 'total-llm-calls) 0))
           (totalDetTasks (if report (.ref report 'total-det-tasks) 0))
           (dischargedObligations
            (list->vector (map obligation->json (.ref final-frontier 'discharged-obligations))))
           (unsatisfiedObligations
            (list->vector (map obligation->json (.ref final-frontier 'unsatisfied-obligations))))
           (blockedOnHumanObligations
            (list->vector (map obligation->json (.ref final-frontier 'blocked-on-human-obligations))))
           (readySynthesisHoles
            (list->vector (map hole->json (.ref final-frontier 'ready-synthesis-holes))))
           (unrefutedHypotheses
            (list->vector (map hypothesis->json (.ref final-frontier 'unrefuted-hypotheses))))
           (epistemicCompetitionStatus
            (symbol->string (.ref final-frontier 'epistemic-competition-status)))
           (unscopedPaths (list->vector (.get semantics unscoped-paths)))
           (eligibleTitles
            (list->vector (map (lambda (row) (hash (identity (car row)) (title (cadr row))))
                               (.get semantics titles))))
           (proposalAdmission
            (and proposal-res
                 (hash (admitted (.get proposal-res admitted?))
                       (reason (symbol->string (.get proposal-res reason)))
                       (branchMatrix (branch-matrix->json (.get proposal-res branch-matrix)))
                       (actionAuthorized #f))))
           (actionAuthorized #f)
           (releaseAuthorized #f)))))
