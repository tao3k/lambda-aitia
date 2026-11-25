;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get .ref)
        (only-in :clan/poo/type element?)
        (only-in :gerbil/core string-prefix?)
        (only-in :std/list/list append-map delete-duplicates/hash)
        (only-in :std/error Error? Error-message)
        (only-in :std/encoding/json json->string)
        (only-in :gerbil-ascent/program/api
                 relational-fragment relational-export relational-compose
                 relational-open-session relational-session-prepare-transaction
                 relational-prepare-queries)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :orgize/languages/org/modules/org-elements/source-interface
                 org-source-element-graph org-source-element-field)
        (only-in :orgize/languages/org/modules/org-elements/values
                 org-element-graph-kind-of org-element-graph-records org-element-graph-id-of
                 make-org-element-graph-view
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
(def (engineering-source-graph text)
  ;; Orgize rejects duplicate properties before constructing a graph. This
  ;; source cannot support a reference; unrelated evaluator errors propagate.
  (with-catch
    (lambda (failure)
      (if (and (Error? failure)
               (equal? (Error-message failure) "duplicate Org property"))
          #f
          (raise failure)))
    (lambda () (org-source-element-graph text))))

;; This document-wide Contract counts ID properties anywhere in the
;; parsed source. Preserve every ID and its record identity; only the
;; document root is needed for the query's ancestry. The original graph
;; still supplies the headline and its ENGINEERING_ID.
(def (document-id-view graph)
  (let* ((id-of (org-element-graph-id-of graph))
         (kind-of (org-element-graph-kind-of graph))
         (records (filter (lambda (record)
                            (or (= (id-of record) 0)
                                (and (equal? (kind-of record) "node-property")
                                     (equal? (org-source-element-field record "key") "ID"))))
                          (org-element-graph-records graph))))
    (make-org-element-graph-view records id-of
      (lambda (record) (and (not (= (id-of record) 0)) 0))
      kind-of org-source-element-field)))

(def (admitted-source-elements graph references)
  (let* ((elements (delete-duplicates/hash (map caddr references)))
         (one (make-org-contract-expectation 'exactly 1))
         (assertions
          (map (lambda (identity index)
                 (make-org-contract-assertion
                  (string-append "unique-element-" (number->string index)) 'error
                  (make-org-element-query-groups
                   "node-property"
                   (list (list (make-org-element-property-clause "key" "ID" 'exact)
                               (make-org-element-property-clause "value" identity 'exact)))
                   'any #f)
                  one))
               elements (iota (length elements))))
         (contract (make-org-contract-definition "aitia.engineering-reference" 'document assertions))
         (results (org-contract-evaluate-definition contract (document-id-view graph) 0))
         (owners (make-hash-table))
         (kind-of (org-element-graph-kind-of graph)))
    ;; Orgize evaluates the assertions in declaration order with one query context.
    (for-each (lambda (identity result)
                (when (org-contract-result-passed? result)
                  (hash-put! owners identity #f)))
              elements results)
    (for-each (lambda (record)
                (when (equal? (kind-of record) "headline")
                  (let (identity (org-source-element-field record "property:ID"))
                    (when (hash-key? owners identity)
                      (hash-put! owners identity
                        (org-source-element-field record "property:ENGINEERING_ID"))))))
              (org-element-graph-records graph))
    owners))

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

;;; Pre-admitted modular ASCENT engine built once from 3 checked
;;; `relational-fragment`s (zero arbitrary host lambdas, strict stratification,
;;; role separation, and bounded budgets). Each call commits one atomic checked
;;; transaction via `relational-session-prepare-transaction`.
(def +commit-semantics-engine-mutex+ (make-mutex 'commit-semantics-engine))
(def +commit-semantics-engine-cell+ (box #f))

(def (make-commit-semantics-engine)
  (let* ((scope-frag
          (relational-fragment
           (import)
           (source (declared_scope (scope prefixes) '() (role input))
                   (changed_path (path) '() (role input))
                   (scope_match (scope path) '() (role input)))
           (private (conflicting_scope (scope))
                    (scope_path (scope path))
                    (affected_scope (scope))
                    (covered_path (path))
                    (unscoped_path (path)))
           (export (declared_scope declared_scope)
                   (changed_path changed_path)
                   (scope_match scope_match)
                   (conflicting_scope conflicting_scope)
                   (scope_path scope_path)
                   (affected_scope affected_scope)
                   (unscoped_path unscoped_path))
           (rule (conflicting_scope ?s)
                 (declared_scope ?s ?p)
                 (declared_scope ?s ?q)
                 (where (< ?p ?q)))
           (rule (scope_path ?s ?p)
                 (scope_match ?s ?p)
                 (not (conflicting_scope ?s)))
           (rule (affected_scope ?s)
                 (scope_path ?s ?_))
           (rule (covered_path ?p)
                 (scope_path ?_ ?p))
           (rule (unscoped_path ?p)
                 (changed_path ?p)
                 (not (covered_path ?p)))))
         (ref-lang-frag
          (relational-fragment
           (import)
           (source (declared_reference (identity source element) '() (role input))
                   (reference (identity source element) '() (role input))
                   (proposed_language (id language source) '() (role input))
                   (language_source (source) '() (role input))
                   (conflicting_language_source (source) '() (role input))
                   (declared_language (language) '() (role input)))
           (private (reference_found (identity))
                    (reference_conflict (identity))
                    (unresolved_reference (identity))
                    (grounded_language (id language source))
                    (language_open (id reason)))
           (export (declared_reference declared_reference)
                   (reference reference)
                   (proposed_language proposed_language)
                   (language_source language_source)
                   (conflicting_language_source conflicting_language_source)
                   (declared_language declared_language)
                   (reference_found reference_found)
                   (reference_conflict reference_conflict)
                   (unresolved_reference unresolved_reference)
                   (grounded_language grounded_language)
                   (language_open language_open))
           (rule (reference_found ?r)
                 (reference ?r ?_ ?_))
           (rule (unresolved_reference ?r)
                 (declared_reference ?r ?s ?e)
                 (not (reference ?r ?s ?e)))
           (rule (reference_conflict ?r)
                 (declared_reference ?r ?s ?_)
                 (declared_reference ?r ?t ?_)
                 (where (< ?s ?t)))
           (rule (reference_conflict ?r)
                 (declared_reference ?r ?_ ?e)
                 (declared_reference ?r ?_ ?f)
                 (where (< ?e ?f)))
           (rule (grounded_language ?i ?l ?s)
                 (proposed_language ?i ?l ?s)
                 (language_source ?s))
           (rule (language_open ?i (value 'missing-language-source))
                 (proposed_language ?i ?l ?s)
                 (not (language_source ?s))
                 (not (conflicting_language_source ?s)))
           (rule (language_open ?i (value 'conflicting-language-source))
                 (proposed_language ?i ?_ ?s)
                 (conflicting_language_source ?s))
           (rule (language_open ?i (value 'language-conflict))
                 (proposed_language ?i ?l ?s)
                 (declared_language ?d)
                 (where (< ?l ?d)))
           (rule (language_open ?i (value 'language-conflict))
                 (proposed_language ?i ?l ?s)
                 (declared_language ?d)
                 (where (< ?d ?l)))))
         (elig-frag
          (relational-fragment
           (import (affected_scope (relational-export scope-frag 'affected_scope))
                   (conflicting_scope (relational-export scope-frag 'conflicting_scope))
                   (reference_found (relational-export ref-lang-frag 'reference_found))
                   (reference_conflict (relational-export ref-lang-frag 'reference_conflict))
                   (language_open (relational-export ref-lang-frag 'language_open)))
           (source (proposed (id reference kind scope) '() (role input))
                   (allowed_type (kind) '() (role input))
                   (well_formed (id) '() (role input)))
           (private (open (id reason))
                    (has_open (id))
                    (eligible (id reference kind scope)))
           (export (proposed proposed)
                   (allowed_type allowed_type)
                   (well_formed well_formed)
                   (open open)
                   (eligible eligible))
           (rule (open ?i ?reason)
                 (language_open ?i ?reason))
           (rule (open ?i (value 'missing-reference))
                 (proposed ?i ?r ?_ ?_)
                 (not (reference_found ?r))
                 (not (reference_conflict ?r)))
           (rule (open ?i (value 'conflicting-reference))
                 (proposed ?i ?r ?_ ?_)
                 (reference_conflict ?r))
           (rule (open ?i (value 'unsupported-type))
                 (proposed ?i ?_ ?k ?_)
                 (not (allowed_type ?k)))
           (rule (open ?i (value 'unaffected-scope))
                 (proposed ?i ?_ ?_ ?s)
                 (not (affected_scope ?s))
                 (not (conflicting_scope ?s)))
           (rule (open ?i (value 'conflicting-scope))
                 (proposed ?i ?_ ?_ ?s)
                 (conflicting_scope ?s))
           (rule (open ?i (value 'invalid-narration))
                 (proposed ?i ?_ ?_ ?_)
                 (not (well_formed ?i)))
           (rule (has_open ?i)
                 (open ?i ?_))
           (rule (eligible ?i ?r ?k ?s)
                 (proposed ?i ?r ?k ?s)
                 (not (has_open ?i)))))
         (composed (relational-compose (list scope-frag ref-lang-frag elig-frag) 4096 16384 16384))
         (session (relational-open-session composed))
         (run-tx
          (relational-session-prepare-transaction
           session
           (list (list scope-frag 'declared_scope)
                 (list scope-frag 'changed_path)
                 (list scope-frag 'scope_match)
                 (list ref-lang-frag 'declared_reference)
                 (list ref-lang-frag 'reference)
                 (list ref-lang-frag 'proposed_language)
                 (list ref-lang-frag 'language_source)
                 (list ref-lang-frag 'conflicting_language_source)
                 (list ref-lang-frag 'declared_language)
                 (list elig-frag 'proposed)
                 (list elig-frag 'allowed_type)
                 (list elig-frag 'well_formed))))
         (read-scope
          (relational-prepare-queries
           scope-frag '(affected_scope scope_path unscoped_path conflicting_scope)))
         (read-ref-lang
          (relational-prepare-queries
           ref-lang-frag '(unresolved_reference reference_conflict grounded_language)))
         (read-elig
          (relational-prepare-queries
           elig-frag '(eligible open))))
    (.o (run-tx := run-tx)
        (read-scope := read-scope)
        (read-ref-lang := read-ref-lang)
        (read-elig := read-elig))))

(def (commit-semantics-engine!)
  (or (unbox +commit-semantics-engine-cell+)
      (let ((engine (make-commit-semantics-engine)))
        (set-box! +commit-semantics-engine-cell+ engine)
        engine)))

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
          (let ((by-path (make-hash-table))
                (admitted (make-hash-table))
                (references (filter (lambda (row)
                                      (let (identity (car row))
                                        (and (identifier? identity)
                                             (not (string-prefix? "SWE-" identity)))))
                                    (delete-duplicates/hash declared-rows))))
            (for-each (lambda (row)
                        (let (path (cadr row))
                          (hash-put! by-path path (cons row (hash-ref by-path path '())))))
                      references)
            (def (owners path)
              (unless (hash-key? admitted path)
                (hash-put! admitted path
                  (match (hash-ref observations-by-path path '())
                    ([source]
                     (and (same-cut? cut (.get source cut))
                          (let (graph (engineering-source-graph (.get source text)))
                            (and graph
                                 (admitted-source-elements graph (hash-ref by-path path))))))
                    (else #f))))
              (hash-ref admitted path))
            (filter (lambda (row)
                      (match row
                        ([identity path element]
                         (let (index (owners path))
                           (and index (equal? identity (hash-get index element)))))))
                    references)))
         (declared-scopes
          (delete-duplicates/hash
           (map (lambda (scope)
                  (list (.get scope name)
                        (list-sort string<? (delete-duplicates/hash (.get scope paths)))))
                (.get naming scopes))))
         (scope-rows
          (append-map
           (lambda (scope)
             (let ((name (car scope)) (prefixes (cadr scope)))
               (if (identifier? name)
                   (filter-map (lambda (path)
                                 (and (ormap (lambda (prefix) (within? prefix path)) prefixes)
                                      (list name path))) paths)
                   '())))
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
         (val->id (make-hash-table))
         (id->val (make-hash-table test: eqv?))
         (next-id 0)
         (intern!
          (lambda (value)
            (or (hash-get val->id value)
                (let ((id next-id))
                  (set! next-id (+ id 1))
                  (hash-put! val->id value id)
                  (hash-put! id->val id value)
                  id))))
         (decode (lambda (id) (hash-ref id->val id)))
         (intern-rows (lambda (rows) (map (lambda (row) (map intern! row)) rows)))
         (decode-rows (lambda (rows) (map (lambda (row) (map decode row)) rows)))
         (tx-batches
          (list (intern-rows declared-scopes)
                (intern-rows (map list paths))
                (intern-rows scope-rows)
                (intern-rows declared-rows)
                (intern-rows reference-rows)
                (intern-rows
                 (map (lambda (p)
                        (list (.get p identity) (.get p language)
                              (.get p language-source)))
                      proposals))
                (intern-rows language-observations)
                (intern-rows language-conflicts)
                (if (.get naming primary-language)
                  (list (list (intern! (.get naming primary-language))))
                  '())
                (intern-rows proposal-rows)
                (intern-rows (map list (.get naming types)))
                (intern-rows well-formed)))
         (query-results
          (dynamic-wind
            (lambda () (mutex-lock! +commit-semantics-engine-mutex+))
            (lambda ()
              (let* ((eng (commit-semantics-engine!))
                     (solution ((.get eng run-tx) tx-batches)))
                (list ((.get eng read-scope) solution)
                      ((.get eng read-ref-lang) solution)
                      ((.get eng read-elig) solution))))
            (lambda () (mutex-unlock! +commit-semantics-engine-mutex+))))
         (scope-out (car query-results))
         (ref-lang-out (cadr query-results))
         (elig-out (caddr query-results))
         (affected-scope-rows (decode-rows (list-ref scope-out 0)))
         (scope-path-rows (decode-rows (list-ref scope-out 1)))
         (unscoped-path-rows (decode-rows (list-ref scope-out 2)))
         (conflicting-scope-rows (decode-rows (list-ref scope-out 3)))
         (unresolved-ref-rows (decode-rows (list-ref ref-lang-out 0)))
         (conflicting-ref-rows (decode-rows (list-ref ref-lang-out 1)))
         (grounded-lang-rows (decode-rows (list-ref ref-lang-out 2)))
         (eligible-rows (decode-rows (list-ref elig-out 0)))
         (open-rows
          (map (lambda (row) (list (decode (car row)) (symbol->string (cadr row))))
               (list-ref elig-out 1))))
    (let* ((duplicate-ids?
            (not (= (length proposals)
                    (length (delete-duplicates/hash (map (lambda (p) (.get p identity)) proposals))))))
           (title-rows
            (if duplicate-ids? '()
                (filter-map
                 (lambda (proposal)
                   (and (member (list (.get proposal identity) (.get proposal reference)
                                      (.get proposal type) (.get proposal scope)) eligible-rows)
                        (list (.get proposal identity)
                              (render-commit-title naming proposal)))) proposals))))
      (.o eligible: (if duplicate-ids? '() eligible-rows)
          open: (if duplicate-ids? '(("*" "duplicate-proposal")) open-rows)
          references: reference-rows affected-scopes: affected-scope-rows
          scope-paths: scope-path-rows
          unscoped-paths: (map car unscoped-path-rows)
          conflicting-scopes: conflicting-scope-rows
          unresolved-references: unresolved-ref-rows
          conflicting-references: conflicting-ref-rows
          languages: grounded-lang-rows
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
