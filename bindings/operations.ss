;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; JSON projection for the Scheme/Rust transport.
(import (for-syntax
          (only-in :tao3k/yuanxu/module-system/source/admission module-source-read
                   module-source-admit-current!))
        (for-template :agentic-ai-lab/modules/ai-agentic-context/query-provider
                      :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :std/encoding/hex hex-decode)
        (only-in :std/list/list find)
        (only-in :std/encoding/json JSONReadOptions json->string string->json)
        (only-in :clan/poo/object .get .ref .o .cc .all-slots)
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
        (only-in "../init.ss" lambda-aitia.init.exports))

(export +aitia-max-input-bytes+
        aitia-sdlc-flow-graph-payload
        aitia-gitops-evaluate-payload
        aitia-org-contract-evaluate-payload
        aitia-project-config-validate-payload aitia-evidence-lineage-payload
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

(def (aitia-evidence-lineage-payload payload)
  (when (> (u8vector-length (string->utf8 payload)) +aitia-max-input-bytes+)
    (error "AITIA input exceeds 4 MiB"))
  (let* ((request (string->json payload +aitia-json-read-options+))
         (revision (json-required request "revision"))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (graph ((.get gitops review-lineage)
                 revision (json-list request "changes") (json-list request "projectInputs")
                 (json-list request "reports") (json-list request "missingReports")
                 (json-list request "parsedDocuments")
                 (if (hash-key? request "policySources") (json-list request "policySources") '())
                 (let (review (hash-get request "engineeringReview"))
                   (and review (archived-engineering-reference gitops review
                                 (map (lambda (row) (json-required row "path"))
                                      (json-list request "changes")))))))
         (result
          (hash (revision revision)
           (dependencyCoverage "unknown")
           (nodes (list->vector
                   (map (lambda (node)
                          (let (data (yuanxu-graph-node-payload node))
                            (list->hash-table
                             (map (lambda (key)
                                    (let (value (.ref data key))
                                      (cons (if (eq? key 'identity) 'id key)
                                            (if (symbol? value) (symbol->string value) value))))
                                  (.all-slots data)))))
                        (yuanxu-graph-nodes graph))))
           (edges (list->vector
                   (map (lambda (edge)
                          (hash (from (symbol->string (yuanxu-graph-edge-from edge)))
                                (to (symbol->string (yuanxu-graph-edge-to edge)))
                                (relation (symbol->string (yuanxu-graph-edge-kind edge)))))
                        (yuanxu-graph-edges graph)))))))
    (when (eq? (hash-get request "query") #t)
      (hash-put! result 'query
                 (review-query->json
                  ((.get lambda-aitia.init.exports modules gitops review-query) graph revision))))
    (json->string result)))

(def (review-query->json result)
  (let (inventory (review-selection->json (.ref result 'inventory)))
    (hash-put! inventory 'changedFiles (review-selection->json (.ref result 'changed-files)))
    (hash-put! inventory 'verifiedReports (review-selection->json (.ref result 'verified-reports)))
    (hash-put! inventory 'missingReports (review-selection->json (.ref result 'missing-reports)))
    (hash-put! inventory 'projectInputs (review-selection->json (.ref result 'project-inputs)))
    (hash-put! inventory 'policySources (review-selection->json (.ref result 'policy-sources)))
    (hash-put! inventory 'engineeringReference
               (review-selection->json (.ref result 'engineering-reference)))
    (hash-put! inventory 'modelEvidence (review-selection->json (.ref result 'model-evidence)))
    inventory))

(def (review-selection->json selection)
  (hash (status "executed") (gql (.ref selection 'gql)) (revision (.ref selection 'revision))
        (complete (.ref selection 'complete?)) (actionAuthority (.ref selection 'action-authority?))
        (rows (list->vector
               (map (lambda (row)
                      (list->hash-table (map cons (.ref selection 'columns) row)))
                    (.ref selection 'rows))))))

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

;; A build may explicitly package one trusted project declaration expression.
;; Parse and embed the same source bytes used for the runtime comparison.
(defsyntax (compiled-project-declaration stx)
  (syntax-case stx ()
    ((_ context)
     (let (input (getenv "AITIA_PROJECT_DECLARATION" #f))
       (if (not input) #'#f
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
               #'(cons source (lambda () expression)))))))))

(def +compiled-project-declaration+ (compiled-project-declaration .o))

(def (resolve-recorded-project-config scope sources)
  (let ((declaration (hash-get sources "declaration"))
        (manifest (hash-get sources "manifest"))
        (compiled +compiled-project-declaration+))
    (cond
     (compiled
      (unless (and (string? declaration) (string=? declaration (car compiled)))
        (error "recorded project.ss differs from the compiled declaration"))
      ((.get scope extend) ((cdr compiled)) (if (string? manifest) manifest "{}")))
     ((string? declaration) (error "recorded project.ss requires a compiled declaration"))
     ((string? manifest) ((.get scope decode) manifest))
     (else (error "no recorded project configuration")))))

(def (aitia-project-config-validate-payload payload)
  (let* ((scope (.get lambda-aitia.init.exports modules project-config))
         (effective (resolve-recorded-project-config scope
                       (string->json payload +aitia-json-read-options+))))
    (if effective
        (let* ((checks-value ((.get scope checks) effective))
               (selection-value ((.get scope commit) effective))
               (policy-value (and selection-value (select-project-commit-policy selection-value)))
               (review (and policy-value
                            (.o selection: selection-value policy: policy-value
                                model-check?: (and (member "sysml.parse" (vector->list checks-value)) #t))))
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
          (cons review (json->string (hash (manifest effective) (checks checks-value)
                            (replay (or replay (void)))
                            (commit (if policy-value (project-commit-policy-projection selection-value policy-value)
                                        (void)))))))
        (cons #f "false"))))

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

(def (linked-journal-operations)
  (compiled-role-values 'agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
    '(journal-pack journal-unpack journal-open journal-close!)))

;; This export consumes facts produced by the Rust checker. The CLI never
;; accepts execution fields from the model's draft.
(def (aitia-commit-journal-payload payload)
  (let* ((input (string->json payload +aitia-json-read-options+))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (operation (json-required input "operation"))
         (project-id (json-required input "project")))
    (if (equal? operation "intent")
        (json->string ((.get gitops commit-intent) project-id (json-required input "attempt")
                       (json-required input "reviewContext")))
        (let* ((review-id (json-required input "approval"))
               (operations (linked-journal-operations))
               (journal ((.get operations journal-open) (json-required input "journal"))))
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
                       (json-required input "attempt") (json-required input "reviewContext") review-id
                       (json-required input "revision")
                       (lambda () (inexact->exact (floor (time->seconds (current-time))))))
                      #t))
                ((equal? operation "recover")
                 (let (record ((.get gitops commit-admission) journal project-id review-id))
                   (and record (.get record attempt))))
                (else (error "unknown internal commit journal operation")))))
            (lambda () ((.get operations journal-close!) journal)))))))

(def (json-commit-naming input (key values))
  (.o project-key: (hash-ref input (key 'projectKey))
      primary-language: (hash-get input (key 'primaryLanguage))
      language-sources: (json-list input (key 'languageSources))
      types: (json-list input (key 'types))
      scopes: (map (lambda (row)
                     (.o name: (hash-ref row (key 'name)) paths: (json-list row (key 'paths))))
                   (json-list input (key 'scopes)))
      references: (map (lambda (row)
                         (.o identity: (hash-ref row (key 'identity)) source: (hash-ref row (key 'source))
                             element: (hash-ref row (key 'element))))
                       (json-list input (key 'references)))))

(def (recorded-commit-sources input cut-value)
  (map (lambda (row)
         (.o path: (json-required row "path") text: (json-required row "text") cut: cut-value))
       (json-list input "sources")))

(def (archived-engineering-reference gitops review paths)
  (let* ((cut-value (replay-cut (json-required review "project") (json-required review "cut")))
         (proposal (json-commit-proposal (json-required review "proposal")))
         (naming (json-commit-naming (json-required review "naming") symbol->string))
         (semantics-value ((.get gitops commit-semantics) naming cut-value
                           (recorded-commit-sources review cut-value) paths (list proposal))))
    (unless (equal? (.get semantics-value titles)
                    (list (list (.get proposal identity) (json-required review "title"))))
      (error "Archived commit proposal does not reproduce the recorded title"))
    (let (reference (find (lambda (row) (equal? (car row) (.get proposal reference)))
                          (.get semantics-value references)))
      (unless reference (error "Recorded title lacks an admitted engineering reference"))
      (.o engineering-id: (car reference) source: (cadr reference) element: (caddr reference)))))

(def (json-commit-proposal input)
  (.o identity: (json-required input "identity") reference: (json-required input "reference")
      language: (json-required input "language") language-source: (json-required input "languageSource")
      type: (json-required input "type") scope: (json-required input "scope")
      summary: (json-required input "summary") rationale: (json-required input "rationale")))

(def (provider-review-row observation)
  (and (hash-table? observation) (equal? (hash-get observation "status") "observed")
       (let ((number (hash-get observation "number"))
             (fields (map (lambda (key) (hash-get observation key))
                          '("repository" "remote" "source" "target" "targetRevision" "headRevision" "updatedAt"))))
         (and (exact-integer? number) (> number 0)
              (andmap (lambda (value) (and (string? value) (> (string-length value) 0))) fields)
              (append (list (car fields) (cadr fields) number) (cddr fields))))))

(def (provider-absence-row observation)
  (and (hash-table? observation) (equal? (hash-get observation "status") "no-open-pull-request")
       (let (fields (map (lambda (key) (hash-get observation key))
                         '("repository" "remote" "source" "headRevision")))
         (and (andmap (lambda (value) (and (string? value) (> (string-length value) 0))) fields)
              fields))))

(def (provider-check-rows observation review-row)
  (and review-row
       (let (checks (hash-get observation "checks"))
         (and (list? checks)
              (let (rows
                    (filter-map
                     (lambda (check)
                       (and (hash-table? check)
                            (let ((head (hash-get check "headRevision"))
                                  (id (hash-get check "id"))
                                  (state (hash-get check "status"))
                                  (conclusion (hash-get check "conclusion")))
                              (and (equal? head (list-ref review-row 6))
                                   (exact-integer? id) (> id 0) (string? state)
                                   (list head id state
                                         (if (string? conclusion) conclusion ""))))))
                     checks))
                (and (= (length rows) (length checks)) rows))))))

(def (review-absence->json association)
  (if (not association) (void)
      (match (.get association absent)
        ([repository remote source head]
         (hash (repository repository) (remote remote) (source source) (headRevision head)))
        (else (void)))))

(def (review-association->json association)
  (if (not association) (void)
      (match (.get association associated)
        ([repository remote number source target target-revision head updated-at]
         (hash (repository repository) (remote remote) (number number)
               (source source) (target target) (targetRevision target-revision)
               (headRevision head) (updatedAt updated-at)))
        (else (void)))))

(def (github-bookmark? bookmark)
  (string? (hash-get bookmark "githubRepository")))

(def (provider-bookmark-row bookmark)
  (let ((route (map (lambda (key) (hash-get bookmark key))
                    '("githubRepository" "remote" "bookmark")))
        (head (hash-get bookmark "commit")))
    (and (andmap (lambda (value) (and (string? value) (> (string-length value) 0))) route)
         (append route (list (and (string? head) (> (string-length head) 0) head))))))

(def (aitia-nasa-draft-payload request)
  (let ((configuration (car request)) (input (cdr request)))
    (unless configuration (error "No commit policy in the recorded project"))
    (let* ((selection (.get configuration selection))
           (selected-policy (.get configuration policy))
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
           (naming (json-commit-naming (hash-ref selection 'naming)))
           (proposals (if draft (list (json-commit-proposal (json-required draft "proposal"))) '()))
           (sources (recorded-commit-sources input cut-value))
           (semantics-value ((.get gitops commit-semantics) naming cut-value sources
                             (json-list input "paths") proposals))
           (provider-review (hash-get input "providerReview"))
           (provider-row (provider-review-row provider-review))
           (bookmarks (if (hash-get input "providerBookmarks")
                        (filter github-bookmark? (json-list input "providerBookmarks"))
                        '()))
           (association
            (and (pair? bookmarks)
                 ((.get gitops commit-review-association)
                  (and (hash-table? provider-review) (hash-get provider-review "status"))
                  provider-row
                  (provider-absence-row provider-review)
                  (filter-map provider-bookmark-row bookmarks)
                  (.get cut-value commit)
                  (provider-check-rows provider-review provider-row))))
           (model ((.get gitops commit-model-assessment)
                   (.get configuration model-check?)
                   (json-list input "paths") (hash-get input "modelCheck")))
           (policy (.cc selected-policy semantics: semantics-value
                        review-association: association
                        model-assessment: model
                        rule-context: (vector (json-required input "ruleContext")
                                              (json-required input "routeContext"))))
           (title-row (and (pair? (.get semantics-value titles)) (car (.get semantics-value titles))))
           (narration (and draft (json-required draft "narration")))
           (review (cond
                    ((and draft title-row)
                     ((.get gitops nasa-commit-description)
                      policy cut-value candidates (cadr title-row)
                      (.o change: (json-required narration "change")
                          evidence: (map json-narration-row (json-list narration "evidence"))
                          open: (map json-narration-row (json-list narration "open")))
                      (json-required draft "org")
                      (json-required draft "context")
                      preview?: (eq? (hash-get input "preview") #t)))
                    (draft
                     (.cc ((.get gitops nasa-draft-requirements) policy cut-value candidates)
                          draft-valid?: #f preview-description: #f description: #f description-digest: #f))
                    (else ((.get gitops nasa-draft-requirements) policy cut-value candidates))))
           (assessment-value (.get review assessment)))
      (def (rows key)
        (list->vector (map list->vector (.ref assessment-value key))))
      (hash (supported (rows 'supported)) (contradicted (rows 'contradicted))
             (open (rows 'open)) (reopened (rows 'reopened))
             (blockingOpen (rows 'blocking-open))
             (context (.get review context))
             (pullRequest (review-association->json association))
             (pullRequestAbsence (review-absence->json association))
             (auditChecklist (if model
                               (vector (hash (check "sysml.parse")
                                             (status (if (pair? (.get model supported)) "passed" "open"))))
                               (vector)))
             (semantics (hash (eligible (list->vector (map list->vector (.get semantics-value eligible))))
                              (languages (list->vector (map list->vector (.get semantics-value languages))))
                              (open (list->vector (map list->vector (.get semantics-value open))))
                              (references (list->vector (map list->vector (.get semantics-value references))))
                              (affectedScopes (list->vector (map list->vector (.get semantics-value affected-scopes))))
                              (scopePaths (list->vector (map list->vector (.get semantics-value scope-paths))))
                              (unscopedPaths (list->vector (.get semantics-value unscoped-paths)))
                              (conflictingScopes (list->vector (map list->vector (.get semantics-value conflicting-scopes))))
                              (unresolvedReferences (list->vector (map list->vector (.get semantics-value unresolved-references))))
                              (conflictingReferences (list->vector (map list->vector (.get semantics-value conflicting-references))))))
             (clauses (if draft (void)
                          (list->vector
                           (map (lambda (row) (hash (property (car row)) (value (cdr row))))
                                (.get review clauses)))))
             (draftValid (if draft (.get review draft-valid?) (void)))
             (previewDescription (if draft (or (.get review preview-description) (void)) (void)))
             (description (if draft (or (.get review description) (void)) (void)))
             (descriptionDigest (if draft (or (.get review description-digest) (void)) (void)))))))

(def (json-narration-row row)
  (list (json-required row "obligation") (json-required row "text")))

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

(def (linked-context-query-provider)
  ;; The Context provider is part of the linked program. Yuanxu initializes
  ;; its compiled dependency closure when a Context operation needs it.
  (compiled-role-values 'agentic-ai-lab/modules/ai-agentic-context/query-provider
    '(context-query-host context-org-source context-org-query
      context-query-current-source context-query-source!
      context-query-withdraw! context-query-execute
      context-query-export context-query-restore)))

(def (linked-context-owner provider)
  (unless linked-context (set! linked-context ((.get provider context-query-host))))
  linked-context)

(def (linked-context-restore! command)
  (when linked-context (error "Cannot restore over a live Context owner"))
  (let (checkpoint (read-agent-input (json-required command "checkpoint")))
    (unless (equal? (json-required checkpoint "project") linked-context-project)
      (error "Context checkpoint belongs to a different project"))
    (let-values (((owner observation)
                  ((.get (linked-context-query-provider) context-query-restore)
                   ((.get (linked-journal-operations) journal-unpack)
                    (json-required checkpoint "journal")))))
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
           (else
            (let (provider (linked-context-query-provider))
              (linked-context-command provider (linked-context-owner provider) operation command))))))
      (let (assessment ((vector-ref input 1)))
        (if (eq? assessment 'reopened) "null" (json->string (support-fields assessment))))))

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
      (.ref observed 'semantic-digest)))
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
      ((.get operations journal-unpack) packed)
      checkpoint))
   (else (error "Unknown AITIA Context operation" operation))))
