;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Commit review, evidence lineage, and durable commit journal transport.
(import (only-in :std/list/list find)
        (only-in :std/encoding/json json->string)
        (only-in :clan/poo/object .all-slots .cc .get .o .ref)
        (only-in :tao3k/yuanxu/graph/types
                 yuanxu-graph-nodes yuanxu-graph-edges
                 yuanxu-graph-node-payload
                 yuanxu-graph-edge-from yuanxu-graph-edge-to yuanxu-graph-edge-kind)
        (only-in "../init.ss" lambda-aitia.init.exports)
        "transport-common.ss")
(export aitia-evidence-lineage-payload
        aitia-commit-journal-payload
        aitia-nasa-draft-payload)

(def (optional-json-list object field)
  (let (value (hash-get object field))
    (cond
     ((not value) '())
     ((list? value) value)
     ((vector? value) (vector->list value))
     (else (error "Aitia input field must be an array" field)))))

(def (json-commit-scope row (key values))
  (.o name: (hash-ref row (key 'name))
      paths: (json-list row (key 'paths))))

(def (json-commit-naming input (key values) (extra-scopes '()))
  (.o project-key: (hash-ref input (key 'projectKey))
      primary-language: (hash-get input (key 'primaryLanguage))
      language-sources: (json-list input (key 'languageSources))
      types: (json-list input (key 'types))
      scopes: (append (map (lambda (row) (json-commit-scope row key))
                           (optional-json-list input (key 'scopes)))
                      extra-scopes)
      references: (map (lambda (row)
                         (.o identity: (hash-ref row (key 'identity))
                             source: (hash-ref row (key 'source))
                             element: (hash-ref row (key 'element))))
                       (json-list input (key 'references)))))

(def (recorded-commit-sources input cut)
  (map (lambda (row)
         (.o path: (json-required row "path") text: (json-required row "text") (cut := cut)))
       (json-list input "sources")))

(def (json-commit-proposal input)
  (.o identity: (json-required input "identity")
      reference: (json-required input "reference")
      language: (json-required input "language")
      language-source: (json-required input "languageSource")
      type: (json-required input "type")
      scope: (json-required input "scope")
      summary: (json-required input "summary")
      rationale: (json-required input "rationale")))

(def (archived-engineering-reference gitops review paths)
  (let* ((cut (replay-cut (json-required review "project") (json-required review "cut")))
         (proposal (json-commit-proposal (json-required review "proposal")))
         (sysml-scopes
          (map (lambda (row) (json-commit-scope row symbol->string))
               (optional-json-list review "sysmlScopes")))
         (naming (json-commit-naming (json-required review "naming") symbol->string sysml-scopes))
         (semantics ((.get gitops commit-semantics) naming cut
                     (recorded-commit-sources review cut) paths (list proposal))))
    (unless (equal? (.get semantics titles)
                    (list (list (.get proposal identity) (json-required review "title"))))
      (error "Archived commit proposal does not reproduce the recorded title"))
    (let (reference (find (lambda (row) (equal? (car row) (.get proposal reference)))
                          (.get semantics references)))
      (unless reference (error "Recorded title lacks an admitted engineering reference"))
      (.o engineering-id: (car reference) source: (cadr reference) element: (caddr reference)))))

(def (review-selection->json selection)
  (hash (status "executed")
        (gql (.get selection gql))
        (revision (.get selection revision))
        (complete (.get selection complete?))
        (actionAuthority (.get selection action-authority?))
        (rows (list->vector
               (map (lambda (row)
                      (list->hash-table (map cons (.get selection columns) row)))
                    (.get selection rows))))))

(def (review-query->json result)
  (let (inventory (review-selection->json (.get result inventory)))
    (hash-put! inventory 'changedFiles (review-selection->json (.get result changed-files)))
    (hash-put! inventory 'verifiedReports (review-selection->json (.get result verified-reports)))
    (hash-put! inventory 'missingReports (review-selection->json (.get result missing-reports)))
    (hash-put! inventory 'projectInputs (review-selection->json (.get result project-inputs)))
    (hash-put! inventory 'policySources (review-selection->json (.get result policy-sources)))
    (hash-put! inventory 'engineeringReference
               (review-selection->json (.get result engineering-reference)))
    (hash-put! inventory 'relatedDecisions
               (review-selection->json (.get result related-decisions)))
    (hash-put! inventory 'affectedDomains
               (review-selection->json (.get result affected-domains)))
    (hash-put! inventory 'modelEvidence (review-selection->json (.get result model-evidence)))
    inventory))

(def (json-adr-reference row)
  (.o identity: (json-required row "identity")
      revision: (json-required row "revision")
      status: (json-symbol row "status")
      relation: (json-symbol row "relation")
      source: (json-required row "source")))

(def (json-affected-domain row)
  (.o domain: (json-required row "domain")
      owner-module: (json-required row "ownerModule")
      paths: (json-list row "paths")))

(def (aitia-evidence-lineage-payload payload)
  (assert-aitia-input-budget! payload)
  (let* ((request (read-aitia-json payload))
         (revision (json-required request "revision"))
         (gitops (.get lambda-aitia.init.exports modules gitops))
         (adr-references
          (if (hash-key? request "adrReferences")
              (map json-adr-reference (json-list request "adrReferences"))
              '()))
         (affected-domains
          (if (hash-key? request "affectedDomains")
              (map json-affected-domain (json-list request "affectedDomains"))
              '()))
         (graph ((.get gitops review-lineage)
                 revision (json-list request "changes") (json-list request "projectInputs")
                 (json-list request "reports") (json-list request "missingReports")
                 (json-list request "parsedDocuments")
                 (if (hash-key? request "policySources") (json-list request "policySources") '())
                 (let (review (hash-get request "engineeringReview"))
                   (and review (archived-engineering-reference gitops review
                                 (map (lambda (row) (json-required row "path"))
                                      (json-list request "changes")))))
                 adr-references: adr-references
                 affected-domains: affected-domains))
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

;; This export consumes facts produced by the Rust checker. The CLI never
;; accepts execution fields from the model's draft.
(def (aitia-commit-journal-payload payload)
  (let* ((input (read-aitia-json payload))
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

(def (json-narration-row row)
  (list (json-required row "obligation") (json-required row "text")))

(def (aitia-nasa-draft-payload request)
  (let ((configuration (car request)) (input (cdr request)))
    (unless configuration (error "No commit policy in the recorded project"))
    (let* ((selection (.get configuration selection))
           (selected-policy (.get configuration policy))
           (cut (replay-cut (hash-ref selection 'project) (json-required input "cut")))
           (gitops (.get lambda-aitia.init.exports modules gitops))
           (to-receipt (.get gitops commit-check-receipt))
           (candidates
            (map (lambda (row)
                   (let (execution
                         (.o observation: (.o (cut := cut)
                                              identity: (json-required row "identity")
                                              obligation: (json-required row "requirement")
                                              outcome: 'passed)
                             method: (json-required row "method")
                             producer: "aitia-runtime/jj-lib"
                             input-digest: (json-required row "inputDigest")
                             report-digest: (json-required row "reportDigest")))
                     (.o (execution := execution) source: (to-receipt execution))))
                 (json-list input "checks")))
           (draft (hash-get input "draft"))
           (sysml-scopes
            (map (lambda (row) (json-commit-scope row symbol->string))
                 (optional-json-list input "sysmlScopes")))
           (naming (json-commit-naming (hash-ref selection 'naming) values sysml-scopes))
           (proposals (if draft (list (json-commit-proposal (json-required draft "proposal"))) '()))
           (sources (recorded-commit-sources input cut))
           (semantics ((.get gitops commit-semantics) naming cut sources
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
                  (.get cut commit)
                  (provider-check-rows provider-review provider-row))))
           (model ((.get gitops commit-model-assessment)
                   (.get configuration model-check?)
                   (json-list input "paths") (hash-get input "modelCheck")))
           (policy (.o (:: @ selected-policy)
                       (semantics := semantics)
                       review-association: association
                       model-assessment: model
                       rule-context: (vector (json-required input "ruleContext")
                                             (json-required input "routeContext"))))
           (title-row (and (pair? (.get semantics titles)) (car (.get semantics titles))))
           (narration (and draft (json-required draft "narration")))
           (review (cond
                    ((and draft title-row)
                     ((.get gitops nasa-commit-description)
                      policy cut candidates (cadr title-row)
                      (.o change: (json-required narration "change")
                          evidence: (map json-narration-row (json-list narration "evidence"))
                          open: (map json-narration-row (json-list narration "open")))
                      (json-required draft "org")
                      (json-required draft "context")
                      preview?: (eq? (hash-get input "preview") #t)))
                    (draft
                     (.cc ((.get gitops nasa-draft-requirements) policy cut candidates)
                          draft-valid?: #f preview-description: #f description: #f description-digest: #f))
                    (else ((.get gitops nasa-draft-requirements) policy cut candidates))))
           (assessment (.get review assessment)))
      (def (rows key)
        (list->vector (map list->vector (.ref assessment key))))
      (hash (supported (rows 'supported))
            (contradicted (rows 'contradicted))
            (open (rows 'open))
            (reopened (rows 'reopened))
            (blockingOpen (rows 'blocking-open))
            (context (.get review context))
            (pullRequest (review-association->json association))
            (pullRequestAbsence (review-absence->json association))
            (auditChecklist (if model
                              (vector (hash (check "sysml.parse")
                                            (status (if (pair? (.get model supported)) "passed" "open"))))
                              (vector)))
            (semantics (hash (eligible (list->vector (map list->vector (.get semantics eligible))))
                             (languages (list->vector (map list->vector (.get semantics languages))))
                             (open (list->vector (map list->vector (.get semantics open))))
                             (references (list->vector (map list->vector (.get semantics references))))
                             (affectedScopes (list->vector (map list->vector (.get semantics affected-scopes))))
                             (scopePaths (list->vector (map list->vector (.get semantics scope-paths))))
                             (unscopedPaths (list->vector (.get semantics unscoped-paths)))
                             (conflictingScopes (list->vector (map list->vector (.get semantics conflicting-scopes))))
                             (unresolvedReferences (list->vector (map list->vector (.get semantics unresolved-references))))
                             (conflictingReferences (list->vector (map list->vector (.get semantics conflicting-references))))))
            (clauses (if draft (void)
                         (list->vector
                          (map (lambda (row) (hash (property (car row)) (value (cdr row))))
                               (.get review clauses)))))
            (draftValid (if draft (.get review draft-valid?) (void)))
            (previewDescription (if draft (or (.get review preview-description) (void)) (void)))
            (description (if draft (or (.get review description) (void)) (void)))
            (descriptionDigest (if draft (or (.get review description-digest) (void)) (void)))))))
