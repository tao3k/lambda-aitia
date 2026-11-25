;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public Scheme/Rust JSON transport facade plus SDLC, ProjectConfig, and Assurance endpoints.
(import (for-syntax
          (only-in :tao3k/yuanxu/module-system/source/admission module-source-read
                   module-source-admit-current!))
        (for-template :tao3k/agentic-ai-lab/modules/ai-agentic-context/query-provider)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :std/encoding/hex hex-decode)
        (only-in :std/encoding/json json->string)
        (only-in :clan/poo/object .get .o .ref)
        (only-in :orgize/languages/org/modules/org-elements/values
                 make-org-element-graph-view make-org-element-query)
        (only-in :orgize/languages/org/modules/org-contract/values
                 make-org-contract-assertion make-org-contract-expectation
                 org-contract-result-matched-count org-contract-result-passed?)
        (only-in :orgize/languages/org/modules/org-contract/evaluation
                 org-contract-evaluate-assertion)
        (only-in :tao3k/yuanxu/graph/types
                 yuanxu-graph-nodes yuanxu-graph-edges
                 yuanxu-graph-node-id yuanxu-graph-node-payload
                 yuanxu-graph-edge-from yuanxu-graph-edge-to yuanxu-graph-edge-kind)
        (only-in "../init.ss" lambda-aitia.init.exports)
        "transport-common.ss"
        "commit-transport.ss"
        "workflow-transport.ss")

(export +aitia-max-input-bytes+
        aitia-sdlc-flow-graph-payload
        aitia-gitops-evaluate-payload
        aitia-org-contract-evaluate-payload
        aitia-project-config-validate-payload
        aitia-evidence-lineage-payload
        aitia-agent-input-check-payload
        aitia-agent-input-assess-payload
        aitia-pytest-assess-payload
        aitia-context-operation
        aitia-nasa-draft-payload
        aitia-commit-journal-payload
        aitia-workflow-reconcile-payload
        aitia-workflow-protocol-step-payload)

(def +aitia-decision-schema+ "lambda-aitia.gitops-decision")

(def (json-check make-check object repository revision)
  (make-check
   (json-symbol object "name")
   (hash-ref object "repository" repository)
   (hash-ref object "revision" revision)
   (json-symbol object "conclusion")
   standard-edition: (hash-get object "standardEdition")
   source-lock-digest: (hash-get object "sourceLockDigest")))

(def (aitia-sdlc-flow-graph-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((request (read-aitia-json payload))
         (lifecycle-id (json-required request "lifecycle-id"))
         (graph ((.get lambda-aitia.init.exports modules sdlc flow-graph) lifecycle-id)))
    (json->string
     (hash (schema "lambda-aitia.sdlc-flow-graph")
           (lifecycleId lifecycle-id)
           (nodes (list->vector
                   (map (lambda (node)
                          (hash (id (symbol->string (yuanxu-graph-node-id node)))
                                (stage (symbol->string (yuanxu-graph-node-payload node)))))
                        (yuanxu-graph-nodes graph))))
           (edges (list->vector
                   (map (lambda (edge)
                          (hash (from (symbol->string (yuanxu-graph-edge-from edge)))
                                (to (symbol->string (yuanxu-graph-edge-to edge)))
                                (relation (symbol->string (yuanxu-graph-edge-kind edge)))))
                        (yuanxu-graph-edges graph))))
           (releaseAuthorized #f)
           (runtimeExecuted #f)))))

(def (decision->json decision)
  (json->string
   (hash (schema +aitia-decision-schema+)
         (repository (.get decision repository))
         (revision (.get decision revision))
         (profile (symbol->string (.get decision profile)))
         (environment (symbol->string (.get decision environment)))
         (accepted (.get decision accepted))
         (nextProfile (symbol->string (.get decision next-profile)))
         (requiredChecks (symbols->json (.get decision required-checks)))
         (standards (symbols->json (.get decision standards)))
         (missingChecks (symbols->json (.get decision missing-checks)))
         (failedChecks (symbols->json (.get decision failed-checks)))
         (checkBlockers
          (list->vector
           (map (lambda (check)
                  (hash (name (symbol->string (.get check name)))
                        (conclusion (symbol->string (.get check conclusion)))))
                (.get decision check-blockers))))
         (staleChecks (symbols->json (.get decision stale-checks)))
         (reasons (symbols->json (.get decision reasons)))
         (semanticOwner "lambda-aitia")
         (runtimeOwner "agentic-ai-lab")
         (authorityStatus "not-evaluated")
         (releaseAuthorized #f)
         (runtimeExecuted #f))))

(def (aitia-gitops-evaluate-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((object (read-aitia-json payload))
         (repository (json-required object "repository"))
         (revision (json-required object "revision"))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (make-check (.get gitops check))
         (change
          ((.get gitops github change)
           (json-symbol object "event") repository revision
           (json-required object "source-ref")
           (json-required object "target-ref")
           (or (hash-get object "pull-request") #f)))
         (checks
          (map (lambda (check) (json-check make-check check repository revision))
               (json-list object "checks"))))
    (decision->json
     ((.get gitops evaluate)
      (.get lambda-aitia.init.exports scenarios github-gitops scenario) change checks))))

(def (org-contract-integer object field minimum maximum)
  (let (value (json-required object field))
    (unless (and (exact-integer? value) (<= minimum value maximum))
      (error "invalid Org contract integer" field))
    value))

(def (org-contract-text object field required?)
  (let (value (json-required object field))
    (unless (and (string? value)
                 (or (not required?) (> (string-length value) 0))
                 (not (string-index value #\nul)))
      (error "invalid Org contract text" field))
    value))

(def (org-contract-operator input)
  (let (operator (org-contract-text input "expectation" #t))
    (cond
     ((string=? operator "exactly") 'exactly)
     ((string=? operator "at-least") 'at-least)
     ((string=? operator "at-most") 'at-most)
     (else (error "invalid Org contract expectation")))))

(def (org-contract-record row)
  (let* ((id (org-contract-integer row "id" 0 #x7fffffffffffffff))
         (parent-id (org-contract-integer row "parentId" -1 #x7fffffffffffffff))
         (kind (org-contract-text row "kind" #t))
         (field-name (org-contract-text row "fieldName" #f))
         (field-value (org-contract-text row "fieldValue" #f)))
    (.o (id := id) parent: (and (>= parent-id 0) parent-id)
        (kind := kind) (field-name := field-name) (field-value := field-value))))

(def (aitia-org-contract-evaluate-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((input (read-aitia-json payload))
         (rows (json-list input "rows"))
         (scope (org-contract-integer input "scopeId" 0 #x7fffffffffffffff))
         (count (org-contract-integer input "expectedCount" 0 10000))
         (kind (org-contract-text input "queryKind" #t))
         (field (org-contract-text input "fieldName" #f))
         (value (org-contract-text input "fieldValue" #f))
         (expectation (org-contract-operator input)))
    (when (> (length rows) 10000) (error "too many Org contract rows"))
    (let* ((graph (make-org-element-graph-view
                   (map org-contract-record rows)
                   (lambda (record) (.get record id))
                   (lambda (record) (.get record parent))
                   (lambda (record) (.get record kind))
                   (lambda (record name)
                     (and (equal? name (.get record field-name))
                          (.get record field-value)))))
           (query (make-org-element-query kind (and (not (equal? field "")) field)
                                          (and (not (equal? field "")) value)))
           (assertion (make-org-contract-assertion
                       "aitia.org-contract-observation" 'error query
                       (make-org-contract-expectation expectation count)))
           (result (org-contract-evaluate-assertion assertion graph scope)))
      (json->string (hash (matchedCount (org-contract-result-matched-count result))
                          (passed (org-contract-result-passed? result)))))))

(def (select-project-commit-policy selection)
  ((.get lambda-aitia.init.exports scenarios github-gitops commit-policy)
   (hash-ref selection 'profile) (hash-ref selection 'primary)
   (map (lambda (row) (list (hash-ref row 'requirement) (hash-ref row 'method)))
        (vector->list (hash-ref selection 'checks)))))

(def (project-commit-policy-projection selection policy)
  (let (standard (.get policy standard))
    (hash (project (hash-ref selection 'project))
          (profile (hash-ref selection 'profile))
          (edition (.get standard edition))
          (sourceLockDigest (.get standard source-lock-digest))
          (primary (.get policy primary))
          (governance (or (hash-get selection 'governance) "default"))
          (checks (hash-ref selection 'checks))
          (naming (hash-ref selection 'naming)))))

(defsyntax (compiled-project-declaration-resolver stx)
  (syntax-case stx ()
    ((_ context)
     (let (input (getenv "AITIA_PROJECT_DECLARATION" #f))
       (if (not input)
           #'(lambda (_scope _declaration _manifest fallback) (fallback))
           (let* ((text (module-source-read input))
                  (value
                   (call-with-input-string text
                     (lambda (port)
                       (let (expression (read port))
                         (when (or (eof-object? expression) (not (eof-object? (read port))))
                           (error "expected one project declaration expression"))
                         expression)))))
             (module-source-admit-current! (list (cons input text)) "project declaration changed")
             (with-syntax ((source (datum->syntax #'context text))
                           (expression (datum->syntax #'context value)))
               #'(lambda (scope declaration manifest _fallback)
                   (unless (and (string? declaration) (string=? declaration source))
                     (error "recorded project.ss differs from the compiled declaration"))
                   ((.get scope extend) expression (if (string? manifest) manifest "{}"))))))))))

(def +compiled-project-declaration-resolver+ (compiled-project-declaration-resolver .o))

(def (resolve-recorded-project-config scope sources)
  (let ((declaration (hash-get sources "declaration"))
        (manifest (hash-get sources "manifest")))
    (+compiled-project-declaration-resolver+
     scope declaration manifest
     (lambda ()
       (cond
        ((string? declaration) (error "recorded project.ss requires a compiled declaration"))
        ((string? manifest) ((.get scope decode) manifest))
        (else (error "no recorded project configuration")))))))

(def (project-replay-plan service)
  (let* ((profile-name (hash-ref service 'profile))
         (profile ((.get lambda-aitia.init.exports modules assurance replay-profile) profile-name))
         (configured-paths (hash-get service 'paths))
         (configured-cases (hash-get service 'cases)))
    (unless (or profile (and configured-paths configured-cases))
      (error "unknown assurance replay profile" profile-name))
    (let ((paths (if configured-paths
                     configured-paths
                     (list->vector (.get profile paths))))
          (cases (if configured-cases
                     configured-cases
                     (let (prefix (.get profile source-prefix))
                       (list->vector
                        (map (lambda (row)
                               (hash (obligation (car row))
                                     (selector (string-append prefix (cadr row)))
                                     (expected (caddr row))))
                             (.get profile cases)))))))
      (hash (project (hash-ref service 'project))
            (profile profile-name)
            (paths paths)
            (cases cases)))))

(def (aitia-project-config-validate-payload payload)
  (let* ((scope (.get lambda-aitia.init.exports modules project-config))
         (effective (resolve-recorded-project-config scope (read-aitia-json payload))))
    (if effective
        (let* ((checks ((.get scope checks) effective))
               (selection ((.get scope commit) effective))
               (policy (and selection (select-project-commit-policy selection)))
               (review (and policy
                            (.o (selection := selection) (policy := policy)
                                model-check?: (and (member "sysml.parse" (vector->list checks)) #t))))
               (replay
                (and (member "assurance.replay" (vector->list checks))
                     (project-replay-plan (hash-ref (hash-ref effective 'services) 'assurance)))))
          (cons review
                (json->string
                 (hash (manifest effective)
                       (checks checks)
                       (replay (or replay (void)))
                       (commit (if policy
                                   (project-commit-policy-projection selection policy)
                                   (void)))))))
        (cons #f "false"))))

(def (read-agent-packet text provider-request?)
  (let (packet (read-aitia-json text))
    (if provider-request?
        (and (hash-table? packet) (hash-get packet "input"))
        packet)))

(def (aitia-agent-input-check-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((input (read-aitia-json payload))
         (source (read-aitia-json (json-required input "source")))
         (projected (read-agent-packet (json-required input "projected")
                                       (hash-get input "providerRequest")))
         (check (.get lambda-aitia.init.exports modules assurance agent-input-corresponds?)))
    (if (check source projected) "true" "false")))

(def (aitia-agent-input-assess-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((input (read-aitia-json payload))
         (assess (.get lambda-aitia.init.exports modules assurance assess-agent-input-delivery))
         (assessment (assess (json-required input "project")
                             (json-required input "operation")
                             (json-required input "revision")
                             (json-required input "historyPath")
                             (json-required input "source")
                             (json-required input "sourceDigest")
                             (json-required input "packet")
                             (json-required input "packetDigest")
                             read-aitia-json
                             (lambda (text)
                               (read-agent-packet text (hash-get input "providerRequest"))))))
    (json->string (support-fields assessment))))

(def (aitia-pytest-assess-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((input (read-aitia-json payload))
         (project-id (json-required input "project"))
         (current (replay-cut project-id (json-required input "current")))
         (recorded (replay-cut project-id (json-required input "recorded")))
         (observation (.o cut: recorded
                          identity: (json-required input "identity")
                          obligation: (json-required input "obligation")
                          outcome: (json-symbol input "outcome")))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (assurance (.get lambda-aitia.init.exports modules assurance))
         (selector (json-required input "selector"))
         (profile (hash-get input "deploymentProfile"))
         (failure-message (hash-get input "failureMessage"))
         (input-digest (json-required input "sourceDigest"))
         (report-digest (json-required input "reportDigest"))
         (generated (and (hash-get input "generateReceipt")
                         ((.get gitops replay-receipt) observation selector input-digest report-digest)))
         (result (and (or (not profile)
                          ((.get assurance replay-observation-matches?)
                           profile selector (.get observation obligation)
                           (.get observation outcome) failure-message))
                      ((.get gitops assess-replay-observation)
                       current (or generated (json-required input "source")) observation
                       selector input-digest report-digest))))
    (def (rows key)
      (list->vector (map list->vector (.ref result key))))
    (if result
        (let* ((frozen (hash-get input "frozenSource"))
               (deployment
                (and profile
                     ((.get assurance assess-replay-deployment)
                      profile project-id (.get current operation) (.get current commit) selector)))
               (assessment
                (and frozen (null? (.get result stale))
                     ((.get assurance assess-pytest-replay)
                      project-id (.get recorded operation) (.get recorded commit)
                      (.get observation obligation) selector
                      (hex-decode frozen) (json-required input "sourceDigest")
                      (json-required input "reportDigest")
                      (eq? (.get observation outcome) 'passed)))))
          (if (or (and (pair? (.get result supported))
                       (not (and assessment (.get assessment complete?))))
                  (and (pair? (.get result contradicted))
                       (not (and assessment (pair? (.get assessment challenges))))))
              "null"
              (json->string
               (hash (revision (.get current commit))
                     (evidenceRevision (.get recorded commit))
                     (supported (rows 'supported))
                     (contradicted (rows 'contradicted))
                     (stale (rows 'stale))
                     (open (rows 'open))
                     (reopened (rows 'reopened))
                     (releaseAuthorized #f)
                     (observationReceipt (or generated (void)))
                     (failureMessage (if (string? failure-message) failure-message (void)))
                     (assurance (if assessment (support-fields assessment) (void)))
                     (deployment (if deployment (deployment-fields deployment) (void)))))))
        "null")))

(def (make-linked-context-state)
  (let ((owner-cell (box #f)) (project-cell (box #f)))
    (.o (owner := (lambda () (unbox owner-cell)))
        (set-owner! := (lambda (next) (set-box! owner-cell next)))
        (project := (lambda () (unbox project-cell)))
        (set-project! := (lambda (next) (set-box! project-cell next))))))

(def +linked-context-state+ (make-linked-context-state))

(def (bind-linked-context-project! project)
  (unless (and (string? project) (> (string-length project) 0))
    (error "Context requires a project identity"))
  (let (current ((.get +linked-context-state+ project)))
    (when (and current (not (equal? current project)))
      (error "Context owner is bound to a different project")))
  ((.get +linked-context-state+ set-project!) project)
  "null")

(def (linked-context-query-provider)
  (compiled-role-values 'tao3k/agentic-ai-lab/modules/ai-agentic-context/query-provider
    '(context-query-host context-org-source context-org-query
      context-query-current-source context-query-source!
      context-query-withdraw! context-query-execute
      context-query-export context-query-restore)))

(def (linked-context-owner provider)
  (or ((.get +linked-context-state+ owner))
      (let (created ((.get provider context-query-host)))
        ((.get +linked-context-state+ set-owner!) created)
        created)))

(def (linked-context-restore! command)
  (when ((.get +linked-context-state+ owner))
    (error "Cannot restore over a live Context owner"))
  (let ((checkpoint (read-aitia-json (json-required command "checkpoint")))
        (project ((.get +linked-context-state+ project))))
    (unless (equal? (json-required checkpoint "project") project)
      (error "Context checkpoint belongs to a different project"))
    (let-values (((owner _observation)
                  ((.get (linked-context-query-provider) context-query-restore)
                   ((.get (linked-journal-operations) journal-unpack)
                    (json-required checkpoint "journal")))))
      ((.get +linked-context-state+ set-owner!) owner)
      "null")))

(def (linked-context-command provider owner operation command)
  (cond
   ((equal? operation "publish")
    ((.get provider context-query-source!)
     owner ((.get provider context-org-source) (json-required command "sourceId")
                                               (json-required command "generation")
                                               (json-required command "source")))
    "null")
   ((equal? operation "withdraw")
    ((.get provider context-query-withdraw!)
     owner (json-required command "sourceId") (json-required command "generation"))
    "null")
   ((equal? operation "observe")
    (let* ((source-id (json-required command "sourceId"))
           (source ((.get provider context-query-current-source) owner source-id))
           (query ((.get provider context-org-query) source (json-required command "elementId")))
           (observed ((.get provider context-query-execute) owner source-id query)))
      (.get observed semantic-digest)))
   ((equal? operation "prepare")
    ((.get lambda-aitia.init.exports modules assurance prepare-context-input)
     owner (json-required command "reference") (json-required command "settings")
     (json-required command "input")))
   ((equal? operation "recover-delivery")
    ((.get lambda-aitia.init.exports modules assurance prepare-context-body)
     owner (json-required command "reference") (json-required command "body")))
   ((equal? operation "checkpoint")
    (let* ((operations (linked-journal-operations))
           (packed ((.get operations journal-pack) ((.get provider context-query-export) owner)))
           (project ((.get +linked-context-state+ project)))
           (checkpoint (string-append "{\"project\":"
                                      (json->string project)
                                      ",\"journal\":" (json->string packed) "}")))
      (when (> (u8vector-length
                (string->utf8 (json->string (hash (operation "restore") (checkpoint checkpoint)))))
               +aitia-max-input-bytes+)
        (error "AITIA Context checkpoint exceeds the restore budget"))
      ((.get operations journal-unpack) packed)
      checkpoint))
   (else (error "Unknown AITIA Context operation" operation))))

(def (aitia-context-operation input)
  (if (string? input)
      (begin
        (assert-aitia-input-budget! input)
        (let* ((command (read-aitia-json input))
               (operation (json-required command "operation"))
               (project ((.get +linked-context-state+ project))))
          (cond
           ((equal? operation "bind-project")
            (bind-linked-context-project! (json-required command "project")))
           ((not project) (error "Context owner has no project binding"))
           ((equal? operation "project") project)
           ((equal? operation "restore") (linked-context-restore! command))
           ((and (equal? operation "recover-delivery") (not ((.get +linked-context-state+ owner)))) #f)
           (else
            (let (provider (linked-context-query-provider))
              (linked-context-command provider (linked-context-owner provider) operation command))))))
      (let (assessment ((vector-ref input 1)))
        (if (eq? assessment 'reopened) "null" (json->string (support-fields assessment))))))
