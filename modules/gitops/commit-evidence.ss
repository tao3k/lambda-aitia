;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json write-json string->json JSONReadOptions)
        (only-in :gerbil/core list-sort string-contains string-suffix?)
        (only-in :std/list/list append-map delete-duplicates/hash)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :clan/poo/object .get .o .cc .ref .slot?)
        (only-in :clan/poo/mop element?)
        (only-in :gerbil-ascent/program/syntax ascent)
        (only-in :gerbil-ascent/program/api gerbil-ascent-evaluate-program)
        (only-in :orgize/languages/org/modules/org-elements/source-interface
                 org-source-element-graph org-source-element-field)
        (only-in :orgize/languages/org/modules/org-elements/values
                 org-element-graph-kind-of org-element-graph-records
                 make-org-element-query-groups make-org-element-property-clause)
        (only-in :orgize/languages/org/modules/org-contract/values
                 make-org-contract-definition make-org-contract-assertion
                 make-org-contract-expectation org-contract-result-passed?)
        (only-in :orgize/languages/org/modules/org-contract/evaluation
                 org-contract-evaluate-definition)
        (only-in "commit-semantics.ss" gitops-commit-title?)
        "types.ss")
(export gitops-commit-evidence gitops-admit-commit-observation
        gitops-assess-replay-observation gitops-replay-receipt gitops-model-gaps
        gitops-commit-check-receipt gitops-nasa-draft-requirements
        gitops-nasa-commit-description
        gitops-commit-model-assessment)

(def (gitops-commit-model-assessment enabled? paths observation)
  (let* ((affected (filter (lambda (path) (string-suffix? ".sysml" path)) paths))
         (model (and (hash-table? observation) (hash-get observation "report")))
         (identity-value (and (hash-table? model) (hash-get model "modelHash")))
         (matching (and (string? identity-value) (> (string-length identity-value) 0)
                        (equal? (hash-get observation "status") "passed")
                        (equal? (hash-get observation "paths") affected)
                        (equal? (hash-get model "documents") affected)))
         (program
          (ascent
           (relation enabled (name) (if enabled? '(("sysml.parse")) '()))
           (relation changed_model (path) (map list affected))
           (relation report (name model) (if matching (list (list "sysml.parse" identity-value)) '()))
           (relation required (name))
           (relation supported (name model))
           (relation open (name))
           ((required N) <-- (enabled N) (changed_model _))
           ((supported N M) <-- (required N) (report N M))
           ((open N) <-- (required N) (not (supported N _)))))
         (result (gerbil-ascent-evaluate-program program)))
    (unless (.get result finished) (error "incomplete commit model assessment"))
    (let (rows (.get result rows-of))
      (and (pair? (rows 'required))
           (.o open: (rows 'open) supported: (rows 'supported) paths: affected
               context: (vector (list->vector affected) (and matching identity-value)))))))

;; The host supplies admitted observations. This program derives relations
;; for one current cut and does not admit facts or issue a write grant.
(def (commit-relations cuts obligations observations)
  (ascent
  (relation current (project workspace change operation commit tree parents) cuts)
  (relation required (obligation) obligations)
  (relation observation (project workspace change operation commit tree parents id obligation outcome) observations)
  (relation supported (id obligation))
  (relation contradicted (id obligation))
  (relation stale (id obligation))
  (relation stale_support (obligation))
  (relation has_support (obligation))
  (relation has_counter (obligation))
  (relation open (obligation))
  (relation reopened (obligation))
  ((supported I R) <-- (required R) (current P W C O V T A)
    (observation P W C O V T A I R (lit "passed")))
  ((contradicted I R) <-- (required R) (current P W C O V T A)
    (observation P W C O V T A I R (lit "failed")))
  ;; The admitted observation belongs to this project/workspace and
  ;; obligation. Change ID is part of its exact cut, not its scope.
  ((stale I R) <-- (required R) (current P W _ _ _ _ _)
    (observation P W C O V T A I R _)
    (not (current P W C O V T A)))
  ((stale_support R) <-- (stale I R) (current P W _ _ _ _ _)
    (observation P W C O V T A I R (lit "passed"))
    (not (current P W C O V T A)))
  ((has_support R) <-- (supported _ R))
  ((has_counter R) <-- (contradicted _ R))
  ((open R) <-- (required R) (not (has_support R)))
  ((open R) <-- (has_counter R))
  ((reopened R) <-- (stale_support R) (open R))))

(def (cut-row cut)
  (list (.get cut project) (.get cut workspace) (.get cut change)
        (.get cut operation) (.get cut commit) (.get cut tree)
        (call-with-output-string
         (lambda (port) (write-json port (list->vector (.get cut parents)))))))

(def (observation-row observation)
  (append (cut-row (.get observation cut))
          (list (.get observation identity) (.get observation obligation)
                (symbol->string (.get observation outcome)))))

(def (gitops-commit-evidence cut obligations observations)
  (unless (and (element? GitOpsCommitCut cut)
               (element? GitOpsCommitObligations obligations)
               (element? GitOpsCommitObservations observations))
    (error "invalid GitOps commit evidence inputs"))
  (let (result (gerbil-ascent-evaluate-program
                (commit-relations (list (cut-row cut)) (map list obligations)
                                  (map observation-row observations))))
    (unless (.get result finished) (error "incomplete GitOps commit evidence query"))
    (let (rows (.get result rows-of))
      (.o supported: (rows 'supported) contradicted: (rows 'contradicted)
          stale: (rows 'stale) open: (rows 'open) reopened: (rows 'reopened)))))

;; Both inventories are supplied by the caller for the same captured cut.
;; A resolved reference says nothing about the result of executing a check.
(def (gitops-model-gaps mappings design-elements properties)
  (let* ((declared (map (lambda (row)
                         (list (.get row design) (.get row model) (.get row property)))
                       mappings))
         (resolved (map list design-elements))
         (available (map (lambda (row) (list (.get row model) (.get row property)))
                         properties))
         (program
          (ascent
           (relation mapping (design model property) declared)
           (relation design_element (design) resolved)
           (relation model_property (model property) available)
           (relation unresolved_design (design model property))
           (relation missing_property (design model property))
           (relation resolved_mapping (design model property))
           ((unresolved_design D M P) <-- (mapping D M P) (not (design_element D)))
           ((missing_property D M P) <-- (mapping D M P) (not (model_property M P)))
           ((resolved_mapping D M P) <-- (mapping D M P)
             (design_element D) (model_property M P))))
         (result (gerbil-ascent-evaluate-program program)))
    (unless (.get result finished) (error "incomplete GitOps model gap query"))
    (let (rows (.get result rows-of))
      (.o unresolved-design: (rows 'unresolved_design)
          missing-property: (rows 'missing_property)
          resolved-mapping: (rows 'resolved_mapping)))))

(def (observation-fields expected producer)
  (append (map cons '("PROJECT" "WORKSPACE" "CHANGE" "OPERATION" "COMMIT" "TREE" "PARENTS")
               (cut-row (.get expected cut)))
          (list (cons "PRODUCER" producer)
                (cons "ID" (.get expected identity))
                (cons "OBLIGATION" (.get expected obligation))
                (cons "OUTCOME" (symbol->string (.get expected outcome))))))

;; The caller supplies an independently trusted execution observation.
;; Matching the Runtime receipt binds it to that independently supplied input.
(def (gitops-admit-commit-observation source expected expected-producer)
  (admit-observation source expected (observation-fields expected expected-producer)))

(def (admit-observation source expected fields)
  (with-catch
   (lambda (_) #f)
   (lambda ()
     (let (record (string->json source
                    (JSONReadOptions key-as-symbol: #f object-as-hash: #t)))
       (and (hash-table? record)
            (= (hash-length record) (length fields))
            (andmap (lambda (field) (equal? (hash-get record (car field)) (cdr field))) fields)
            expected)))))

;; Source and report digests are from the runtime-owned process observation.
;; The Runtime receipt must match every independently observed field.
(def (gitops-assess-replay-observation current source expected selector input-digest report-digest)
  (let (admitted (admit-observation source expected
                                      (replay-fields expected selector input-digest report-digest)))
    (and admitted
         (gitops-commit-evidence current (list (.get expected obligation)) (list admitted)))))

(def (replay-fields expected selector input-digest report-digest)
  (append (observation-fields expected "aitia-runtime/pytest")
          (list (cons "METHOD" "pytest") (cons "SELECTOR" selector)
                (cons "SOURCE_SHA256" input-digest) (cons "REPORT_SHA256" report-digest))))

(def (gitops-replay-receipt expected selector input-digest report-digest)
  (observation-receipt (replay-fields expected selector input-digest report-digest)))

(def (observation-receipt fields)
  (let (record (make-hash-table))
    (for-each (lambda (field) (hash-put! record (car field) (cdr field))) fields)
    (json-value record)))

;; The Runtime owns these facts and keeps them in its machine receipt.
(def (commit-check-fields execution)
  (append (observation-fields (.get execution observation) (.get execution producer))
          (list (cons "METHOD" (.get execution method))
                (cons "SOURCE_SHA256" (.get execution input-digest))
                (cons "REPORT_SHA256" (.get execution report-digest)))))

(def (gitops-commit-check-receipt execution)
  (observation-receipt (commit-check-fields execution)))

(def (json-value value)
  (call-with-output-string (lambda (port) (write-json port value))))

(def (write-description title body)
  (string-append title "\n\n" body "\n"))

(def (narration-line? text)
  (and (string? text) (<= 1 (string-length text) 8192)
       (not (char-whitespace? (string-ref text 0)))
       (not (char-whitespace? (string-ref text (- (string-length text) 1))))
       (andmap (lambda (ch) (not (control-character? ch))) (string->list text))
       (andmap (lambda (field) (not (string-contains text field)))
               '("AITIA-Draft:" "AITIA-Evidence:" "NASA-Source-Lock:" "JJ-Cut:" "sha256:"))))

(def (narration-section heading expected proposed (label (lambda (id) id)))
  ;; Match the current assessment exactly. The proposal explains the rows;
  ;; it cannot invent, suppress or duplicate a row.
  (and (list? proposed) (= (length expected) (length proposed))
       (andmap (lambda (row)
                 (and (list? row) (= (length row) 2)
                      (member (car row) expected) (narration-line? (cadr row))))
               proposed)
       (andmap (lambda (id) (assoc id proposed)) expected)
       (if (null? expected) ""
           (apply string-append "\n\n" heading
                  (map (lambda (id)
                         (string-append "\n- " (label id) ": " (cadr (assoc id proposed))))
                       (list-sort string<? expected))))))

(def (clause-obligations clauses kind)
  (map cdr (filter (lambda (row) (equal? (car row) kind)) clauses)))

(def (render-narration title narration clauses model)
  (let* ((passed (clause-obligations clauses "AITIA_SUPPORT"))
         (failed (clause-obligations clauses "AITIA_COUNTEREXAMPLE"))
         (evidence (narration-section "Evidence" (delete-duplicates/hash (append passed failed))
                     (.get narration evidence)
                     (lambda (id)
                       (if (member id failed)
                           (string-append id (if (member id passed) " (conflicting)" " (failed)"))
                           id))))
         (open (narration-section "Open"
                 (clause-obligations clauses "AITIA_OPEN_OBLIGATION")
                 (.get narration open)))
         (model-evidence
          (if (and model (pair? (.get model supported)))
            (let (paths (.get model paths))
              (string-append
               (if (equal? evidence "") "\n\nEvidence" "")
               "\n- OpenSysML: "
               (if (null? (cdr paths))
                 (string-append "Parsed " (json-value (car paths)) " at the recorded revision.")
                 (string-append "Parsed all " (number->string (length paths))
                                " affected SysML files at the recorded revision."))))
            ""))
         (change (.get narration change)))
    (and evidence open (narration-line? change)
         (let (body (string-append change evidence model-evidence open))
           (and (<= (string-length body) 8192) (write-description title body))))))

;; The reviewed description carries the narration. Exact cut and execution
;; bindings remain in the Runtime receipt and the JJ operation.
(def (control-character? ch)
  (let (code (char->integer ch))
    (or (< code 32) (<= 127 code 159))))

(def (assess-commit-draft policy cut candidates)
  (let* ((checks (.get policy checks))
         (requirements (map car checks))
         (accepted
          (filter-map
           (lambda (candidate)
             (let* ((execution (.get candidate execution))
                    (observation (.get execution observation))
                    (row (assoc (.get observation obligation) checks)))
               (and row (equal? (cadr row) (.get execution method))
                    (admit-observation (.get candidate source) observation
                                       (commit-check-fields execution))
                    execution)))
           candidates))
         (observations (map (lambda (execution) (.get execution observation)) accepted))
         (identities (map (lambda (observation) (.get observation identity)) observations))
         (evidence (gitops-commit-evidence cut requirements observations))
         (association (and (.slot? policy 'review-association)
                           (.get policy review-association)))
         (model (and (.slot? policy 'model-assessment) (.get policy model-assessment)))
         (blocking-open (append (.get evidence open)
                                (if association (.get association open) '())
                                (if model (.get model open) '())))
         (assessment-value
          (.cc evidence open: (append blocking-open
                                      (if association (.get association disclosed-open) '()))
               blocking-open: blocking-open))
         (rejected (- (length candidates) (length accepted))))
    (values assessment-value rejected
            (= (length identities) (length (delete-duplicates/hash identities))))))

;; Only these clause kinds may constrain a draft. Values come from the current
;; ASCENT result, not from the draft or instructions embedded in its source.
(def draft-relations
  '(("AITIA_SUPPORT" . supported)
    ("AITIA_COUNTEREXAMPLE" . contradicted)
    ("AITIA_OPEN_OBLIGATION" . open)
    ("AITIA_REOPENED" . reopened)))

(def (draft-context policy cut assessment-value)
  (let* ((rows (append-map
                (lambda (relation)
                  (map (lambda (value) (cons (car relation) value))
                       (list-sort string<?
                                  (map (lambda (row) (json-value (list->vector row)))
                                       (.ref assessment-value (cdr relation))))))
                draft-relations))
         (standard (.get policy standard))
         (context-digest
          (source-lock-payload-digest
           (string->utf8
            (json-value (vector (.get standard source-lock-digest) (.get policy primary)
                                (and (.slot? policy 'semantics) (.get policy semantics context))
                                (and (.slot? policy 'rule-context) (.get policy rule-context))
                                (and (.slot? policy 'review-association)
                                     (.get policy review-association)
                                     (.get policy review-association context))
                                (and (.slot? policy 'model-assessment)
                                     (.get policy model-assessment)
                                     (.get policy model-assessment context))
                                (list->vector (map list->vector (.get policy checks)))
                                (list->vector (cut-row cut))
                                (list->vector (map (lambda (row) (vector (car row) (cdr row))) rows))))))))
    context-digest))

(def (draft-clauses assessment-value)
  (append-map
   (lambda (relation)
     (map (lambda (obligation) (cons (car relation) obligation))
          (list-sort string<?
            (delete-duplicates/hash
             (map (lambda (row) (car (reverse row)))
                  (.ref assessment-value (cdr relation)))))))
   draft-relations))

(def (gitops-nasa-draft-requirements policy cut candidates)
  (let-values (((assessment-value rejected unique?) (assess-commit-draft policy cut candidates)))
    (.o context: (draft-context policy cut assessment-value)
        clauses: (draft-clauses assessment-value)
        assessment: assessment-value rejected-count: rejected unique-evidence?: unique?)))

(def (draft-org-matches? source clauses)
  (let* ((graph (org-source-element-graph source))
         (fields (append '("AITIA_CONTEXT" "SOURCE_SHA256" "REPORT_SHA256"
                           "NASA_SOURCE_LOCK" "NASA-SOURCE-LOCK" "JJ_CUT")
                         (map car draft-relations)))
         (kind-of (org-element-graph-kind-of graph))
         (one (make-org-contract-expectation 'exactly 1))
         (definition
          (make-org-contract-definition
           "aitia.commit-draft.v1" 'document
           (map (lambda (clause index)
                  (make-org-contract-assertion
                   (string-append "draft-" (number->string index)) 'error
                   (make-org-element-query-groups
                    "node-property"
                    (list (list (make-org-element-property-clause "key" (car clause) 'exact)
                                (make-org-element-property-clause "value" (cdr clause) 'exact)))
                    'any #f)
                   one))
                clauses (iota (length clauses)))))
         (results (org-contract-evaluate-definition definition graph 0))
         (references
          (append-map (lambda (record)
                        (if (equal? (kind-of record) "headline")
                          (filter-map
                           (lambda (field)
                             (let (value (org-source-element-field record (string-append "property:" field)))
                               (and value (cons field value))))
                           fields)
                          '()))
                      (org-element-graph-records graph))))
    (and (= (length results) (length clauses))
         (andmap org-contract-result-passed? results)
         (= (length references) (length clauses))
         (andmap (lambda (ref) (member ref clauses)) references))))

(def (gitops-nasa-commit-description policy cut candidates title narration draft-org context
                                    preview?: (preview? #f))
  (unless (gitops-commit-title? title)
    (error "Invalid commit narration"))
  (let-values (((assessment-value rejected unique?) (assess-commit-draft policy cut candidates)))
    (let* ((clauses (draft-clauses assessment-value))
           (rendered (and (.slot? policy 'semantics)
                          (member title (map cadr (.get policy semantics titles)))
                          (render-narration title narration clauses
                            (and (.slot? policy 'model-assessment) (.get policy model-assessment)))))
           ;; Discovery identifies the assessment. Preview additionally binds
           ;; the exact text the reviewer saw, including its ORG material.
           (current-context
            (source-lock-payload-digest
             (string->utf8
              (json-value
               (vector "aitia.commit-review.v2" (draft-context policy cut assessment-value)
                       rendered draft-org)))))
           (valid? (and (or preview? (equal? context current-context))
                        (draft-org-matches? draft-org clauses)
                        rendered #t))
           (description-value
            (and valid? (zero? rejected) unique?
                 (null? (.get assessment-value blocking-open))
                 rendered))
           (digest (and description-value (source-lock-payload-digest (string->utf8 description-value)))))
      (.o context: current-context assessment: assessment-value rejected-count: rejected
          preview-description: (and valid? rendered)
          draft-valid?: valid? description: description-value description-digest: digest))))
