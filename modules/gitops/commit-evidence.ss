;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json write-json string->json JSONReadOptions)
        (only-in :gerbil/core list-sort string-contains string-prefix?)
        (only-in :std/list/list filter filter-map append-map iota delete-duplicates/hash)
        (only-in :yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :clan/poo/object .get .o .ref)
        (only-in :clan/poo/mop element?)
        (only-in :gerbil-ascent/program/syntax ascent)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run)
        (only-in :orgize/languages/org/modules/org-elements/source-interface
                 org-source-element-graph org-source-element-field)
        (only-in :orgize/languages/org/modules/org-elements/query
                 org-element-map make-org-element-query-context)
        (only-in :orgize/languages/org/modules/org-elements/values
                 make-org-element-query-groups make-org-element-property-clause)
        (only-in :orgize/languages/org/modules/org-contract/values
                 make-org-contract-definition make-org-contract-assertion
                 make-org-contract-expectation org-contract-result-passed?)
        (only-in :orgize/languages/org/modules/org-contract/evaluation
                 org-contract-evaluate-definition)
        "types.ss")
(export gitops-commit-evidence gitops-admit-commit-observation
        gitops-assess-replay-observation gitops-replay-receipt gitops-model-gaps
        gitops-commit-check-receipt gitops-nasa-draft-requirements
        gitops-nasa-commit-description)

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
  (let (session (gerbil-ascent-open-session
                 (commit-relations (list (cut-row cut)) (map list obligations)
                                   (map observation-row observations))))
    (let (result (gerbil-ascent-session-run session))
      (unless (.get result finished) (error "incomplete GitOps commit evidence query"))
      (let (rows (.get result rows-of))
        (.o supported: (rows 'supported) contradicted: (rows 'contradicted)
            stale: (rows 'stale) open: (rows 'open) reopened: (rows 'reopened))))))

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
         (result (gerbil-ascent-session-run (gerbil-ascent-open-session program))))
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
         (assessment-value (gitops-commit-evidence cut requirements observations))
         (rejected (- (length candidates) (length accepted)))
         (supported-checks
          (filter (lambda (execution)
                    (let (observation (.get execution observation))
                      (member (list (.get observation identity) (.get observation obligation))
                              (.get assessment-value supported))))
                  accepted)))
    (values assessment-value supported-checks rejected
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
  (let-values (((assessment-value _ rejected unique?) (assess-commit-draft policy cut candidates)))
    (.o context: (draft-context policy cut assessment-value)
        clauses: (draft-clauses assessment-value)
        assessment: assessment-value rejected-count: rejected unique-evidence?: unique?)))

(def (draft-org-matches? source clauses)
  (let* ((graph (org-source-element-graph source))
         (fields (append '("AITIA_CONTEXT" "SOURCE_SHA256" "REPORT_SHA256"
                           "NASA_SOURCE_LOCK" "NASA-SOURCE-LOCK" "JJ_CUT")
                         (map car draft-relations)))
         (records (org-element-map (make-org-element-query-context graph) "headline" (lambda (_) #t)))
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
                        (filter-map (lambda (field)
                                      (let (value (org-source-element-field record (string-append "property:" field)))
                                        (and value (cons field value))))
                                    fields))
                      records)))
    (and (= (length results) (length clauses))
         (andmap org-contract-result-passed? results)
         (= (length references) (length clauses))
         (andmap (lambda (ref) (member ref clauses)) references))))

(def (gitops-nasa-commit-description policy cut candidates title body draft-org context)
  (unless (and (string? title) (<= 1 (string-length title) 72)
               (not (char-whitespace? (string-ref title 0)))
               (not (char-whitespace? (string-ref title (- (string-length title) 1))))
               (not (string-prefix? "SWE-" title))
               (andmap (lambda (ch) (not (control-character? ch))) (string->list title))
               (string? body) (<= 1 (string-length body) 8192)
               (not (string-contains body "AITIA-"))
               (not (string-contains body "NASA-"))
               (not (string-contains body "JJ-Cut:"))
               (andmap (lambda (ch) (or (char=? ch #\newline) (not (control-character? ch))))
                       (string->list body)))
    (error "Invalid commit narration"))
  (let-values (((assessment-value supported-checks rejected unique?) (assess-commit-draft policy cut candidates)))
    (let* ((clauses (draft-clauses assessment-value))
           (current-context (draft-context policy cut assessment-value))
           (valid? (and (equal? context current-context) (draft-org-matches? draft-org clauses)))
           (description-value
            (and valid? (zero? rejected) unique?
                 (null? (.get assessment-value open))
                 (write-description title body)))
           (digest (and description-value (source-lock-payload-digest (string->utf8 description-value)))))
      (.o context: current-context assessment: assessment-value rejected-count: rejected
          draft-valid?: valid? description: description-value description-digest: digest))))
