;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get .ref)
        (only-in :clan/poo/mop element?)
        (only-in :gerbil/core string-prefix?)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :std/error Error? Error-message)
        (only-in :std/encoding/json json->string)
        (only-in :gerbil-ascent/program/syntax ascent)
        (only-in :gerbil-ascent/program/api gerbil-ascent-evaluate-program)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
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
        "types.ss")
(export gitops-commit-semantics gitops-commit-title?)

;; Host observations and Agent proposals enter through different arguments.
;; A proposal cannot supply a source document, source cut, or affected path.
(def (source-has-element? text identity engineering-id)
  ;; Orgize rejects duplicate properties before constructing a graph. This
  ;; source cannot support a reference; unrelated evaluator errors propagate.
  (let* ((graph (with-catch
                  (lambda (failure)
                    (if (and (Error? failure)
                             (equal? (Error-message failure) "duplicate Org property"))
                        #f
                        (raise failure)))
                  (lambda () (org-source-element-graph text))))
         (contract
          (make-org-contract-definition
           "aitia.engineering-reference" 'document
           (list (make-org-contract-assertion
                  "unique-element" 'error
                  (make-org-element-query-groups
                   "node-property"
                   (list (list (make-org-element-property-clause "key" "ID" 'exact)
                               (make-org-element-property-clause "value" identity 'exact)))
                   'any #f)
                  (make-org-contract-expectation 'exactly 1)))))
         (results (and graph (org-contract-evaluate-definition contract graph 0))))
    ;; The Contract already established that only one ID property matches.
    ;; Inspect its owning headline without constructing a second graph index.
    (and results (= 1 (length results)) (andmap org-contract-result-passed? results)
         (let (kind-of (org-element-graph-kind-of graph))
           (ormap (lambda (row)
                    (and (equal? (kind-of row) "headline")
                         (equal? identity (org-source-element-field row "property:ID"))
                         (equal? engineering-id
                                 (org-source-element-field row "property:ENGINEERING_ID"))))
                  (org-element-graph-records graph))))))

(def (identifier? value)
  (and (string? value) (<= 1 (string-length value) 48)
       (let (first (string-ref value 0))
         (or (char-alphabetic? first) (char-numeric? first)))
       (andmap (lambda (ch) (or (char-alphabetic? ch) (char-numeric? ch)
                               (memv ch '(#\- #\_ #\.))))
               (string->list value))))

(def (gitops-commit-title? value)
  (and (string? value) (<= 1 (string-length value) 72)
       (not (char-whitespace? (string-ref value 0)))
       (not (char-whitespace? (string-ref value (- (string-length value) 1))))
       (not (string-prefix? "SWE-" value))
       (andmap (lambda (ch) (let (code (char->integer ch))
                             (not (or (< code 32) (<= 127 code 159)))))
               (string->list value))))

(def (render-commit-title naming proposal)
  (string-append (.get naming project-key) "-" (.get proposal reference) " "
                 (.get proposal type) "(" (.get proposal scope) "): "
                 (.get proposal summary)))

(def (summary? value)
  (and (string? value) (positive? (string-length value))
       (not (char-whitespace? (string-ref value 0)))
       (ormap char-alphabetic? (string->list value))))

(def (reasoning? value)
  (and (string? value) (<= 1 (string-length value) 8192)
       (ormap (lambda (ch) (not (char-whitespace? ch))) (string->list value))
       (andmap (lambda (ch)
                 (let (code (char->integer ch))
                   (or (char=? ch #\newline) (not (or (< code 32) (<= 127 code 159))))))
               (string->list value))))

(def (within? prefix path)
  (or (equal? prefix path)
      (string-prefix? (string-append prefix "/") path)))

(def (same-cut? left right)
  (andmap (lambda (key) (equal? (.ref left key) (.ref right key)))
          '(project workspace change operation commit tree parents)))

;; Project references name actual ORG Elements. NASA clauses and PR numbers
;; are not engineering identities. The Host reads only configured references
;; from the recorded JJ tree; the Scheme projection verifies their elements.
(def (gitops-commit-semantics naming cut sources paths proposals)
  (unless (and (element? GitOpsCommitNaming naming)
               (element? GitOpsCommitCut cut)
               (element? GitOpsCommitSources sources)
               (element? GitOpsCommitProposals proposals))
    (error "invalid commit semantics inputs"))
  (let* ((declared-references (.get naming references))
         (declared-rows
          (map (lambda (r) (list (.get r identity) (.get r source) (.get r element)))
               declared-references))
         (observations-by-path
          (let (index (make-hash-table))
            (for-each (lambda (source)
                        (let (path (.get source path))
                          (hash-put! index path (cons source (hash-ref index path '())))))
                      sources)
            index))
         (reference-rows
          (filter-map
           (lambda (reference)
             (match reference
               ([identity path element]
                (and (identifier? identity) (not (string-prefix? "SWE-" identity))
                     (match (hash-ref observations-by-path path '())
                       ([source]
                        (and (same-cut? cut (.get source cut))
                             (source-has-element? (.get source text) element identity)
                             reference))
                       (else #f))))))
           (delete-duplicates/hash declared-rows)))
         (declared-scopes
          (delete-duplicates/hash
           (map (lambda (scope)
                  (list (.get scope name)
                        (list-sort string<? (delete-duplicates/hash (.get scope paths)))))
                (.get naming scopes))))
         (scope-rows
          (filter-map
           (lambda (scope)
             (and (identifier? (car scope))
                  (ormap (lambda (path)
                           (ormap (lambda (prefix) (within? prefix path)) (cadr scope))) paths)
                  (list (car scope))))
           declared-scopes))
         (proposal-rows
          (map (lambda (proposal)
                 (list (.get proposal identity) (.get proposal reference)
                       (.get proposal type) (.get proposal scope))) proposals))
         (language-paths (.get naming language-sources))
         (language-conflicts
          (filter-map (lambda (path)
                        (match (hash-ref observations-by-path path '())
                          ([_ _ . _] (list path))
                          (else #f)))
                      language-paths))
         (language-observations
          (filter-map (lambda (path)
                        (match (hash-ref observations-by-path path '())
                          ([source]
                           (and (same-cut? cut (.get source cut))
                                (positive? (string-length (.get source text)))
                                (list path)))
                          (else #f)))
                      language-paths))
         (well-formed
          (filter-map
           (lambda (proposal)
             (and (identifier? (.get naming project-key))
                  (identifier? (.get proposal type)) (identifier? (.get proposal scope))
                  (summary? (.get proposal summary)) (reasoning? (.get proposal rationale))
                  (gitops-commit-title? (render-commit-title naming proposal))
                  (list (.get proposal identity)))) proposals))
         (program
          (ascent
           (relation declared_reference (identity source element) declared-rows)
           (relation proposed (id reference kind scope) proposal-rows)
           (relation proposed_language (id language source)
                     (map (lambda (p) (list (.get p identity) (.get p language)
                                           (.get p language-source))) proposals))
           (relation language_source (source) language-observations)
           (relation conflicting_language_source (source) language-conflicts)
           (relation declared_language (language)
                     (if (.get naming primary-language) (list (list (.get naming primary-language))) '()))
           (relation grounded_language (id language source))
           (relation reference (identity source element) reference-rows)
           (relation allowed_type (kind) (map list (.get naming types)))
           (relation declared_scope (scope prefixes) declared-scopes)
           (relation scope_match (scope) scope-rows)
           (relation affected_scope (scope))
           (relation conflicting_scope (scope))
           (relation well_formed (id) well-formed)
           (relation reference_found (identity))
           (relation reference_conflict (identity))
           (relation unresolved_reference (identity))
           (relation open (id reason))
           (relation eligible (id reference kind scope))
           ((reference_found R) <-- (reference R _ _))
           ((conflicting_scope S) <-- (declared_scope S P) (declared_scope S Q)
            (guard (P Q) (lambda (p q) (not (equal? p q)))))
           ((affected_scope S) <-- (scope_match S) (not (conflicting_scope S)))
           ((grounded_language I L S) <-- (proposed_language I L S) (language_source S))
           ((open I (lit "missing-language-source")) <-- (proposed_language I L S)
            (not (language_source S)) (not (conflicting_language_source S)))
           ((open I (lit "conflicting-language-source")) <-- (proposed_language I _ S)
            (conflicting_language_source S))
           ((open I (lit "language-conflict")) <-- (proposed_language I L S) (declared_language D)
            (guard (L D) (lambda (l d) (not (equal? l d)))))
           ;; A declaration conflict exists even when one origin is missing,
           ;; stale or forged. A valid origin cannot erase its competitor.
           ((unresolved_reference R) <-- (declared_reference R S E) (not (reference R S E)))
           ((reference_conflict R) <-- (declared_reference R S _) (declared_reference R T _)
            (guard (S T) (lambda (s t) (not (equal? s t)))))
           ((reference_conflict R) <-- (declared_reference R _ E) (declared_reference R _ F)
            (guard (E F) (lambda (e f) (not (equal? e f)))))
           ((open I (lit "missing-reference")) <-- (proposed I R _ _)
            (not (reference_found R)) (not (reference_conflict R)))
           ((open I (lit "conflicting-reference")) <-- (proposed I R _ _) (reference_conflict R))
           ((open I (lit "unsupported-type")) <-- (proposed I _ K _) (not (allowed_type K)))
           ((open I (lit "unaffected-scope")) <-- (proposed I _ _ S)
            (not (affected_scope S)) (not (conflicting_scope S)))
           ((open I (lit "conflicting-scope")) <-- (proposed I _ _ S) (conflicting_scope S))
           ((open I (lit "invalid-narration")) <-- (proposed I _ _ _) (not (well_formed I)))
           ((eligible I R K S) <-- (proposed I R K S) (not (open I _)))))
         (result (gerbil-ascent-evaluate-program program)))
    (unless (.get result finished) (error "incomplete commit semantics query"))
    (let* ((rows (.get result rows-of))
           (duplicate-ids?
            (not (= (length proposals)
                    (length (delete-duplicates/hash (map (lambda (p) (.get p identity)) proposals))))))
           (title-rows
            (if duplicate-ids? '()
                (filter-map
                 (lambda (proposal)
                   (and (member (list (.get proposal identity) (.get proposal reference)
                                      (.get proposal type) (.get proposal scope)) (rows 'eligible))
                        (list (.get proposal identity)
                              (render-commit-title naming proposal)))) proposals))))
      (.o eligible: (if duplicate-ids? '() (rows 'eligible))
          open: (if duplicate-ids? '(("*" "duplicate-proposal")) (rows 'open))
          references: reference-rows affected-scopes: (rows 'affected_scope)
          conflicting-scopes: (rows 'conflicting_scope)
          unresolved-references: (rows 'unresolved_reference)
          conflicting-references: (rows 'reference_conflict)
          languages: (rows 'grounded_language)
          titles: title-rows
          ;; This is machine custody, never a human commit trailer.
          context: (source-lock-payload-digest
                    (string->utf8
                     (json->string
                      (vector (.get naming project-key) (.get naming types)
                              (.get naming primary-language) (.get naming language-sources)
                              declared-rows
                              (map (lambda (s) (list (.get s name) (.get s paths))) (.get naming scopes))
                              paths
                              (map (lambda (p)
                                     (list (.get p identity) (.get p reference) (.get p type)
                                           (.get p scope) (.get p summary) (.get p language)
                                           (.get p language-source) (.get p rationale))) proposals)
                              (map (lambda (s) (list (.get s path) (.get s text)
                                                   (same-cut? cut (.get s cut)))) sources)))))))))
