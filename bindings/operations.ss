;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; JSON projection for the Scheme/Rust transport.
(import (only-in :std/list/list filter-map)
        (only-in :agentic-ai-lab/modules/ai-agentic-context/query-provider
                 context-query-host context-org-source context-org-query
                 context-query-current-source context-query-source!
                 context-query-withdraw! context-query-execute
                 context-query-export context-query-restore)
        (only-in :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
                 journal-pack journal-unpack journal-open journal-close!)
        (only-in :std/encoding/hex hex-decode)
        (only-in :std/encoding/json JSONReadOptions json->string string->json)
        (only-in :clan/poo/object .get .ref .o)
        (only-in :orgize/languages/org/modules/org-elements/values
                 make-org-element-graph-view make-org-element-query)
        (only-in :orgize/languages/org/modules/org-contract/values
                 make-org-contract-assertion make-org-contract-expectation
                 org-contract-result-matched-count org-contract-result-passed?)
        (only-in :orgize/languages/org/modules/org-contract/evaluation
                 org-contract-evaluate-assertion)
        (only-in :yuanxu/graph/types
                 yuanxu-graph-nodes yuanxu-graph-edges
                 yuanxu-graph-node-id yuanxu-graph-node-payload
                 yuanxu-graph-edge-from yuanxu-graph-edge-to yuanxu-graph-edge-kind)
        (only-in "../init.ss" lambda-aitia.init.exports))

(export +aitia-max-input-bytes+
        aitia-sdlc-flow-graph-payload
        aitia-gitops-evaluate-payload
        aitia-org-contract-evaluate-payload
        aitia-project-config-validate-payload
        aitia-agent-input-check-payload aitia-agent-input-assess-payload
        aitia-pytest-assess-payload aitia-context-operation aitia-nasa-draft-payload
        aitia-commit-journal-payload)

(def +aitia-decision-schema+ "lambda-aitia.gitops-decision")
(def +aitia-max-input-bytes+ (* 4 1024 1024))
(def +aitia-json-read-options+
  (JSONReadOptions key-as-symbol: #f
                   array-as-vector: #f
                   object-as-hash: #t))

(def (json-required object field)
  (or (hash-get object field)
      (error "missing Aitia input field" field)))

(def (json-symbol object field)
  (string->symbol (json-required object field)))

(def (json-list object field)
  (let (value (json-required object field))
    (cond
     ((list? value) value)
     ((vector? value) (vector->list value))
     (else (error "Aitia input field must be an array" field)))))

(def (json-check make-check object repository revision)
  (make-check
   (json-symbol object "name")
   (hash-ref object "repository" repository)
   (hash-ref object "revision" revision)
   (json-symbol object "conclusion")
   standard-edition: (hash-get object "standardEdition")
   source-lock-digest: (hash-get object "sourceLockDigest")))

(def (symbols->json values)
  (list->vector (map symbol->string values)))

(def (aitia-sdlc-flow-graph-payload payload)
  (when (> (string-length payload) +aitia-max-input-bytes+)
    (error "Aitia input exceeds maximum bytes" (string-length payload)))
  (let* ((request (string->json payload +aitia-json-read-options+))
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
         (repository (.ref decision 'repository))
         (revision (.ref decision 'revision))
         (profile (symbol->string (.ref decision 'profile)))
         (environment (symbol->string (.ref decision 'environment)))
         (accepted (.ref decision 'accepted))
         (nextProfile (symbol->string (.ref decision 'next-profile)))
         (requiredChecks (symbols->json (.ref decision 'required-checks)))
         (standards (symbols->json (.ref decision 'standards)))
         (missingChecks (symbols->json (.ref decision 'missing-checks)))
         (failedChecks (symbols->json (.ref decision 'failed-checks)))
         (checkBlockers
          (list->vector
           (map (lambda (check)
                  (hash (name (symbol->string (.ref check 'name)))
                        (conclusion (symbol->string (.ref check 'conclusion)))))
                (.ref decision 'check-blockers))))
         (staleChecks (symbols->json (.ref decision 'stale-checks)))
         (reasons (symbols->json (.ref decision 'reasons)))
         (semanticOwner "lambda-aitia")
         (runtimeOwner "agentic-ai-lab")
         (authorityStatus "not-evaluated")
         (releaseAuthorized #f)
         (runtimeExecuted #f))))

(def (aitia-gitops-evaluate-payload payload)
  (when (> (string-length payload) +aitia-max-input-bytes+)
    (error "Aitia input exceeds maximum bytes" (string-length payload)))
  (let* ((object (string->json payload +aitia-json-read-options+))
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
  (let* ((row-id (org-contract-integer row "id" 0 #x7fffffffffffffff))
         (row-parent (org-contract-integer row "parentId" -1 #x7fffffffffffffff))
         (row-kind (org-contract-text row "kind" #t))
         (field (org-contract-text row "fieldName" #f))
         (value (org-contract-text row "fieldValue" #f)))
    (.o id: row-id parent: (and (>= row-parent 0) row-parent)
        kind: row-kind field-name: field field-value: value)))

;; Transport for graph facts already projected by the source owner. This
;; result is a Contract observation and carries no provenance or authority.
(def (aitia-org-contract-evaluate-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((input (string->json payload +aitia-json-read-options+))
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
                   (lambda (record) (.ref record 'id))
                   (lambda (record) (.ref record 'parent))
                   (lambda (record) (.ref record 'kind))
                   (lambda (record name)
                     (and (equal? name (.ref record 'field-name))
                          (.ref record 'field-value)))))
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

(def (project-commit-policy effective)
  (let (selection (hash-get (hash-get effective 'services) 'commit))
    (and selection
         (let* ((policy (select-project-commit-policy selection))
                (standard (.get policy standard)))
           (hash (project (hash-ref selection 'project))
                 (profile (hash-ref selection 'profile))
                 (edition (.get standard edition))
                 (sourceLockDigest (.get standard source-lock-digest))
                 (primary (.get policy primary))
                 (governance (or (hash-get selection 'governance) "default"))
                 (checks (hash-ref selection 'checks)))))))

(def (aitia-project-config-validate-payload payload)
  (let* ((scope (.get lambda-aitia.init.exports modules project-config))
         (effective ((.get scope decode) payload)))
    (if effective
        (let* ((checks-value ((.get scope checks) effective))
               (replay
                (and (member "assurance.replay" (vector->list checks-value))
                     (let* ((service (hash-ref (hash-ref effective 'services) 'assurance))
                            (profile (hash-ref service 'profile))
                            (cases ((.get lambda-aitia.init.exports modules assurance replay-cases) profile)))
                       (hash (project (hash-ref service 'project))
                             (profile profile)
                             (paths #("dev/qualification/job-executor/test_unique_effect.py"
                                      "dev/qualification/job-executor/worker.py"))
                             (cases (list->vector
                                     (map (lambda (row)
                                            (hash (obligation (car row))
                                                  (selector (string-append "dev/qualification/job-executor/" (cadr row)))
                                                  (expected (caddr row))))
                                          cases))))))))
          (json->string (hash (manifest effective) (checks checks-value)
                              (replay (or replay (void)))
                              (commit (or (project-commit-policy effective) (void))))))
        "false")))

(def (read-agent-input text)
  (string->json text +aitia-json-read-options+))

(def (read-agent-packet text provider-request?)
  (let (packet (read-agent-input text))
    (if provider-request?
        (and (hash-table? packet) (hash-get packet "input"))
        packet)))

;; This operation checks a selected semantic fragment. The Rust owner supplies
;; the source and retains the exact packet it will deliver to its consumer.
(def (aitia-agent-input-check-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((input (string->json payload +aitia-json-read-options+))
         (source (read-agent-input (json-required input "source")))
         (projected (read-agent-packet (json-required input "projected")
                                       (hash-get input "providerRequest")))
         (check (.get lambda-aitia.init.exports modules assurance agent-input-corresponds?)))
    (if (check source projected) "true" "false")))

(def (aitia-agent-input-assess-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((input (string->json payload +aitia-json-read-options+))
         (assess (.get lambda-aitia.init.exports modules assurance assess-agent-input-delivery))
         (assessment (assess (json-required input "project")
                             (json-required input "operation")
                             (json-required input "revision")
                             (json-required input "historyPath")
                             (json-required input "source")
                             (json-required input "sourceDigest")
                             (json-required input "packet")
                             (json-required input "packetDigest")
                             read-agent-input
                             (lambda (text)
                               (read-agent-packet text (hash-get input "providerRequest"))))))
    (json->string (support-fields assessment))))

(def (support-fields assessment)
  (let (requirements (.ref assessment 'requirements))
    (hash (claim (.ref assessment 'claim))
           (predicate (.ref assessment 'predicate))
           (revision (.ref assessment 'claim-revision))
           (scope (.ref assessment 'scope))
           (subject (.ref assessment 'subject))
           (snapshotDigest (.ref assessment 'semantic-snapshot-digest))
           (complete (.ref assessment 'complete?))
           (assumptions (list->vector (.ref assessment 'assumptions)))
           (assumptionAssessments
            (list->vector
             (map (lambda (row)
                    (hash (assumption (.ref row 'assumption))
                          (owner (.ref row 'owner))
                          (reviewPolicy (.ref row 'review-policy))
                          (obligation (.ref row 'obligation))
                          (admission (.ref row 'admission))
                          (blocker (and (.ref row 'blocker)
                                        (symbol->string (.ref row 'blocker))))))
                  (.ref assessment 'assumption-assessments))))
           (defeaters (list->vector (.ref assessment 'defeaters)))
           (challenges
            (list->vector
             (map (lambda (row)
                    (hash (challenge (.ref row 'challenge))
                          (revision (.ref row 'revision))
                          (kind (symbol->string (.ref row 'kind)))
                          (state (symbol->string (.ref row 'state)))
                          (subject (.ref row 'subject))
                          (evidence (.ref row 'evidence))
                          (evidenceDigest (.ref row 'evidence-digest))
                          (scope (.ref row 'scope))
                          (obligation (.ref row 'obligation))
                          (relation (.ref row 'relation))))
                  (.ref assessment 'challenges))))
           (blockers (symbols->json (.ref assessment 'blockers)))
           (residualDispositions
            (list->vector
             (map (lambda (row)
                    (hash (obligation (.ref row 'obligation))
                          (decision (.ref row 'decision))
                          (authority (.ref row 'authority))
                          (policy (.ref row 'policy))
                          (policyRevision (.ref row 'policy-revision))
                          (admission (.ref row 'admission))
                          (outcomeDigest (.ref row 'outcome-digest))))
                  (.ref assessment 'residual-dispositions))))
           (releaseAuthorized (.ref assessment 'release-authorized?))
           (witnesses
            (list->vector
             (map (lambda (witness)
                    (hash (obligation (.ref witness 'obligation))
                          (evidence (.ref witness 'evidence))
                          (admission (.ref witness 'admission))
                          (relation (.ref witness 'relation))
                          (outcome (.ref witness 'outcome))
                          (outcomeDigest (.ref witness 'outcome-digest))
                          (scope (.ref witness 'scope))
                          (method (symbol->string (.ref witness 'declared-evidence-kind)))
                          (capability (symbol->string (.ref witness 'capability)))
                          (producer (.ref witness 'producer))
                          (tool (.ref witness 'tool))
                          (toolVersion (.ref witness 'tool-version))
                          (expiresAt (.ref witness 'expires-at))
                          (inputs (list->vector (.ref witness 'input-artifacts)))))
                  (.ref assessment 'witnesses))))
           (remaining
            (list->vector
             (filter-map (lambda (row)
                           (and (not (.ref row 'supported?))
                                (hash (obligation (.ref row 'obligation))
                                      (reason (symbol->string (.ref row 'blocker))))))
                         requirements))))))

(def (replay-cut project-id row)
  (.o project: project-id workspace: (json-required row "workspace")
      change: (json-required row "change") operation: (json-required row "operation")
      commit: (json-required row "commit") tree: (json-required row "tree")
      parents: (json-list row "parents")))

;; This export consumes facts produced by the Rust checker. The CLI never
;; accepts execution fields from the model's draft.
(def (aitia-commit-journal-payload payload)
  (let* ((input (string->json payload +aitia-json-read-options+))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (operation (json-required input "operation"))
         (project-id (json-required input "project")))
    (if (equal? operation "intent")
        (json->string ((.get gitops commit-intent) project-id (json-required input "attempt")))
        (let ((journal (journal-open (json-required input "journal")))
              (review-id (json-required input "approval")))
          (dynamic-wind
            void
            (lambda ()
              (json->string
               (cond
                ((equal? operation "approve")
                 ((.get gitops record-commit-approval!) journal
                  (.o identity: review-id project: project-id
                      intent: (json-required input "intent")
                      policy-revision: (json-required input "revision")
                      not-before: (json-required input "notBefore")
                      expires-at: (json-required input "expiresAt"))))
                ((equal? operation "revoke")
                 ((.get gitops revoke-commit-approval!) journal project-id review-id))
                ((equal? operation "consume")
                 (and ((.get gitops consume-commit-admission!) journal project-id
                       (json-required input "attempt") review-id
                       (json-required input "revision")
                       (lambda () (inexact->exact (floor (time->seconds (current-time))))))
                      #t))
                ((equal? operation "recover")
                 (let (record ((.get gitops commit-admission) journal project-id review-id))
                   (and record (.get record attempt))))
                (else (error "unknown internal commit journal operation")))))
            (lambda () (journal-close! journal)))))))

(def (aitia-nasa-draft-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((input (string->json payload +aitia-json-read-options+))
         (config (.get lambda-aitia.init.exports modules project-config))
         (effective ((.get config decode) (json-required input "manifest")))
         (selection (and effective (hash-get (hash-get effective 'services) 'commit))))
    (unless selection (error "No commit policy in the recorded project"))
    (let* ((policy (select-project-commit-policy selection))
           (cut-value (replay-cut (hash-ref selection 'project) (json-required input "cut")))
           (gitops (.get lambda-aitia.init.exports modules gitops))
           (to-receipt (.get gitops commit-check-receipt))
           (candidates
            (map (lambda (row)
                   (let (execution-value
                         (.o observation: (.o cut: cut-value identity: (json-required row "identity")
                                             obligation: (json-required row "requirement")
                                             outcome: 'passed)
                             method: (json-required row "method") producer: "aitia-runtime/jj-lib"
                             input-digest: (json-required row "inputDigest")
                             report-digest: (json-required row "reportDigest")))
                     (.o execution: execution-value source: (to-receipt execution-value))))
                 (json-list input "checks")))
           (draft (hash-get input "draft"))
           (review (if draft
                       ((.get gitops nasa-commit-description)
                        policy cut-value candidates (json-required draft "title")
                        (json-required draft "body") (json-required draft "org")
                        (json-required draft "context"))
                       ((.get gitops nasa-draft-requirements) policy cut-value candidates)))
           (assessment-value (.get review assessment)))
      (def (rows key)
        (list->vector (map list->vector (.ref assessment-value key))))
      (json->string
       (hash (supported (rows 'supported)) (contradicted (rows 'contradicted))
             (open (rows 'open)) (reopened (rows 'reopened))
             (context (.get review context))
             (clauses (if draft (void)
                          (list->vector
                           (map (lambda (row) (hash (property (car row)) (value (cdr row))))
                                (.get review clauses)))))
             (draftValid (if draft (.get review draft-valid?) (void)))
             (description (if draft (or (.get review description) (void)) (void)))
             (descriptionDigest (if draft (or (.get review description-digest) (void)) (void))))))))

(def (aitia-pytest-assess-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((input (string->json payload +aitia-json-read-options+))
         (project-id (json-required input "project"))
         (current (replay-cut project-id (json-required input "current")))
         (recorded (replay-cut project-id (json-required input "recorded")))
         (observation (.o cut: recorded identity: (json-required input "identity")
                          obligation: (json-required input "obligation")
                          outcome: (json-symbol input "outcome")))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (selector (json-required input "selector"))
         (profile (hash-get input "deploymentProfile"))
         (failure-message (hash-get input "failureMessage"))
         (input-digest (json-required input "sourceDigest"))
         (report-digest (json-required input "reportDigest"))
         (generated (and (hash-get input "generateReceipt")
                         ((.get gitops replay-receipt) observation selector input-digest report-digest)))
         (result (and (or (not profile)
                          ((.get lambda-aitia.init.exports modules assurance replay-observation-matches?)
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
                     ((.get lambda-aitia.init.exports modules assurance assess-replay-deployment)
                      profile project-id (.get current operation) (.get current commit) selector)))
               (assessment
                (and frozen (null? (.ref result 'stale))
                     ((.get lambda-aitia.init.exports modules assurance assess-pytest-replay)
                      project-id (.get recorded operation) (.get recorded commit)
                      (.get observation obligation) selector
                      (hex-decode frozen) (json-required input "sourceDigest")
                      (json-required input "reportDigest")
                      (eq? (.get observation outcome) 'passed)))))
          (if (or (and (pair? (.ref result 'supported))
                       (not (and assessment (.ref assessment 'complete?))))
                  (and (pair? (.ref result 'contradicted))
                       (not (and assessment (pair? (.ref assessment 'challenges))))))
              "null"
              (json->string
               (hash (revision (.get current commit))
                     (evidenceRevision (.get recorded commit))
                     (supported (rows 'supported)) (contradicted (rows 'contradicted))
                     (stale (rows 'stale)) (open (rows 'open)) (reopened (rows 'reopened))
                     (releaseAuthorized #f)
                     (observationReceipt (or generated (void)))
                     (failureMessage (if (string? failure-message) failure-message (void)))
                     (assurance (if assessment (support-fields assessment) (void)))
                     (deployment (if deployment (deployment-fields deployment) (void)))))))
        "null")))

(def (deployment-fields deployment)
  (hash (assessment (support-fields (.get deployment assessment)))
        (conditions
         (list->vector
          (map (lambda (row)
                 (hash (obligation (car row))
                       (method (symbol->string (cadr row)))
                       (capability (symbol->string (caddr row)))
                       (condition (cadddr row))))
               (.get deployment conditions))))))

;; The linked application owns one live Lab Query catalog. Opaque prepared
;; vectors remain strong roots and carry no JSON token or serialized callback.
(def linked-context #f)
(def linked-context-project #f)

(def (bind-linked-context-project! project)
  (unless (and (string? project) (> (string-length project) 0))
    (error "Context requires a project identity"))
  (when (and linked-context-project (not (equal? linked-context-project project)))
    (error "Context owner is bound to a different project"))
  (set! linked-context-project project)
  "null")

(def (linked-context-owner)
  (unless linked-context (set! linked-context (context-query-host)))
  linked-context)

(def (linked-context-restore! command)
  (when linked-context (error "Cannot restore over a live Context owner"))
  (let (checkpoint (read-agent-input (json-required command "checkpoint")))
    (unless (equal? (json-required checkpoint "project") linked-context-project)
      (error "Context checkpoint belongs to a different project"))
    (let-values (((owner observation)
                  (context-query-restore (journal-unpack (json-required checkpoint "journal")))))
      (set! linked-context owner)
      "null")))

(def (aitia-context-operation input)
  (if (string? input)
      (begin
        (when (> (u8vector-length (string->utf8 input)) +aitia-max-input-bytes+)
          (error "AITIA input exceeds 4 MiB"))
        (let* ((command (read-agent-input input))
               (operation (json-required command "operation")))
          (cond
           ((equal? operation "bind-project")
            (bind-linked-context-project! (json-required command "project")))
           ((not linked-context-project) (error "Context owner has no project binding"))
           ((equal? operation "project") linked-context-project)
           ((equal? operation "restore") (linked-context-restore! command))
           ((and (equal? operation "recover-delivery") (not linked-context)) #f)
           (else (linked-context-command (linked-context-owner) operation command)))))
      (let (assessment ((vector-ref input 1)))
        (if (eq? assessment 'reopened) "null" (json->string (support-fields assessment))))))

(def (linked-context-command owner operation command)
  (cond
   ((equal? operation "publish")
    (context-query-source!
     owner (context-org-source (json-required command "sourceId")
                               (json-required command "generation")
                               (json-required command "source")))
    "null")
   ((equal? operation "withdraw")
    (context-query-withdraw! owner (json-required command "sourceId")
                             (json-required command "generation"))
    "null")
   ((equal? operation "observe")
    (let* ((source-id (json-required command "sourceId"))
           (source (context-query-current-source owner source-id))
           (query (context-org-query source (json-required command "elementId")))
           (observed (context-query-execute owner source-id query)))
      (.ref observed 'semantic-digest)))
   ((equal? operation "prepare")
    ((.get lambda-aitia.init.exports modules assurance prepare-context-input)
     owner (json-required command "reference") (json-required command "settings")
     (json-required command "input")))
   ((equal? operation "recover-delivery")
    ((.get lambda-aitia.init.exports modules assurance prepare-context-body)
     owner (json-required command "reference") (json-required command "body")))
   ((equal? operation "checkpoint")
    (let* ((packed (journal-pack (context-query-export owner)))
           ;; The checkpoint is hashed as bytes. Keep its envelope stable
           ;; across hash-table iteration order and process restarts.
           (checkpoint (string-append "{\"project\":"
                                      (json->string linked-context-project)
                                      ",\"journal\":" (json->string packed) "}")))
      ;; Check the actual restore envelope, including JSON escaping.
      (when (> (u8vector-length
                (string->utf8 (json->string (hash (operation "restore") (checkpoint checkpoint)))))
               +aitia-max-input-bytes+)
        (error "AITIA Context checkpoint exceeds the restore budget"))
      ;; The reader also enforces its lexical, depth and node bounds.
      (journal-unpack packed)
      checkpoint))
   (else (error "Unknown AITIA Context operation" operation))))
