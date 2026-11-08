;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; JSON projection for the Scheme/Rust transport.
(import (only-in :std/encoding/json JSONReadOptions json->string string->json)
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
        aitia-project-config-validate-payload)

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

(def (aitia-project-config-validate-payload payload)
  (let* ((scope (.get lambda-aitia.init.exports modules project-config))
         (effective ((.get scope decode) payload)))
    (if effective
        (json->string (hash (manifest effective)
                            (checks ((.get scope checks) effective))))
        "false")))
