;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json write-json)
        (only-in :clan/poo/object .get .o)
        (only-in :clan/poo/mop element?)
        (only-in :gerbil-ascent/program/syntax ascent)
        (only-in :gerbil-ascent/program/session gerbil-ascent-open-session
                 gerbil-ascent-session-run)
        (only-in :orgize/languages/org/modules/org-elements/source-interface
                 org-source-element-graph org-source-element-field)
        (only-in :orgize/languages/org/modules/org-elements/query
                 org-element-map make-org-element-query-context)
        (only-in :orgize/languages/org/modules/org-elements/syntax org-elements)
        (only-in :orgize/languages/org/modules/org-contract/values
                 make-org-contract-definition org-contract-result-passed?)
        (only-in :orgize/languages/org/modules/org-contract/syntax
                 org-contract-block assert-org-element)
        (only-in :orgize/languages/org/modules/org-contract/evaluation
                 org-contract-evaluate-definition)
        "types.ss")
(export gitops-commit-evidence gitops-admit-commit-observation gitops-model-gaps)

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
  ((stale I R) <-- (required R) (current P W C _ _ _ _)
    (observation P W C O V T A I R _)
    (not (current P W C O V T A)))
  ((stale_support R) <-- (stale I R) (current P W C _ _ _ _)
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

(def observation-contract
  (make-org-contract-definition
   "aitia.commit-evidence.v1" 'document
   (org-contract-block
    (assert-org-element "one-observation" error
      (bindings) (org-elements headline) (expect exactly 1)))))

(def (observation-fields expected producer)
  (append (map cons '("PROJECT" "WORKSPACE" "CHANGE" "OPERATION" "COMMIT" "TREE" "PARENTS")
               (cut-row (.get expected cut)))
          (list (cons "PRODUCER" producer)
                (cons "ID" (.get expected identity))
                (cons "OBLIGATION" (.get expected obligation))
                (cons "OUTCOME" (symbol->string (.get expected outcome))))))

;; The caller supplies an independently trusted execution observation.
;; Matching the source binds the document to that input.
(def (gitops-admit-commit-observation source expected expected-producer)
  (let* ((graph (org-source-element-graph source))
         (results (org-contract-evaluate-definition observation-contract graph 0)))
    (and (pair? results)
         (null? (cdr results))
         (org-contract-result-passed? (car results))
         (let* ((context (make-org-element-query-context graph))
                (record (car (org-element-map context "headline" (lambda (_) #t)))))
           (and (andmap (lambda (field)
                          (equal? (cdr field)
                                  (org-source-element-field
                                   record (string-append "property:" (car field)))))
                        (observation-fields expected expected-producer))
                expected)))))
