;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc .get)
        (only-in :gerbil/core string-suffix?)
        (only-in :tao3k/yuanxu/graph/types yuanxu-graph yuanxu-graph-edge yuanxu-graph-node))
(export gitops-review-lineage)

(def +valid-adr-statuses+ '(proposed accepted rejected deprecated superseded))
(def +valid-adr-relations+ '(implements-rfc refines-rfc supersedes superseded-by related-to))

(def (lineage-node identity payload)
  (yuanxu-graph-node identity (.o (:: @ payload) (identity := identity))))

(def (index-observations rows key label)
  (let (index (make-hash-table))
    (for-each
     (lambda (row)
       (let (identity (key row))
         (when (hash-key? index identity)
           (error "Duplicate review lineage observation" label identity))
         (hash-put! index identity row)))
     rows)
    index))

(def (observed-path row)
  (hash-ref row "path"))

(def (regular-file-entry? entry)
  (and (hash-table? entry) (equal? (hash-get entry "kind") "file")))

(def (recorded-file-entry? entry)
  (and (regular-file-entry? entry)
       (string? (hash-ref entry "id" #f))
       (boolean? (hash-ref entry "executable" 'missing))))

(def (same-file-entry? left right)
  (and (recorded-file-entry? right)
       (equal? (hash-ref left "id") (hash-ref right "id"))
       (eq? (hash-ref left "executable") (hash-ref right "executable"))))

(def (validate-file-observation! row changed label)
  (let* ((path (observed-path row))
         (entry (hash-ref row "entry"))
         (change (hash-get changed path)))
    (unless (and (recorded-file-entry? entry)
                 (or (not change) (same-file-entry? entry (hash-ref change "after"))))
      (error "Review lineage file disagrees with the recorded revision" label path))))

(def (validate-lineage-observations! changes inputs reports missing parsed-documents policy-sources)
  (let ((changed (index-observations changes observed-path 'change))
        (configured (index-observations inputs observed-path 'project-input))
        (verified (index-observations reports values 'verified-report)))
    (index-observations policy-sources observed-path 'policy-source)
    (index-observations missing values 'missing-report)
    (index-observations parsed-documents values 'parsed-document)
    (for-each
     (lambda (method)
       (when (hash-key? verified method)
         (error "Review lineage report is both verified and missing" method)))
     missing)
    (unless (eq? (hash-key? verified "sysml.parse") (pair? parsed-documents))
      (error "Review lineage model paths require a verified parse report"))
    (for-each
     (lambda (path)
       (let* ((row (hash-get changed path))
              (entry (and row (hash-ref row "after"))))
         (unless (and (string-suffix? ".sysml" path) (regular-file-entry? entry))
           (error "Review lineage model path is outside the recorded model files" path))))
     parsed-documents)
    (for-each (lambda (input) (validate-file-observation! input changed 'project-input)) inputs)
    (for-each
     (lambda (source)
       (validate-file-observation! source changed 'policy-source)
       (let* ((path (observed-path source))
              (input (hash-get configured path)))
         (when (and input (not (same-file-entry? (hash-ref source "entry") (hash-ref input "entry"))))
           (error "Review lineage policy source disagrees with the project input" path))))
     policy-sources)))

(def (validate-adr-references! adr-references policy-paths)
  (index-observations adr-references (lambda (adr) (.get adr identity)) 'adr-reference)
  (for-each
   (lambda (adr)
     (let ((status (.get adr status))
           (relation (.get adr relation))
           (source (.get adr source)))
       (unless (memq status +valid-adr-statuses+)
         (error "Review lineage ADR has invalid status" (.get adr identity) status))
       (unless (memq relation +valid-adr-relations+)
         (error "Review lineage ADR has invalid relation" (.get adr identity) relation))
       (unless (member source policy-paths)
         (error "Review lineage ADR source is outside the recorded policy files"
                (.get adr identity) source))))
   adr-references))

(def (validate-affected-domains! affected-domains changed)
  (index-observations affected-domains (lambda (row) (.get row domain)) 'affected-domain)
  (for-each
   (lambda (row)
     (let ((domain (.get row domain))
           (paths (.get row paths)))
       (unless (and (string? domain) (positive? (string-length domain))
                    (string? (.get row owner-module))
                    (positive? (string-length (.get row owner-module)))
                    (list? paths) (pair? paths))
         (error "Review lineage domain declaration is incomplete" domain))
       (for-each
        (lambda (path)
          (unless (member path changed)
            (error "Review lineage domain path is outside the recorded changes" domain path)))
        paths)))
   affected-domains))

;; The JJ host has already verified the applied revision and reproduced the
;; archived reports. This projection records observed relations only.
;; Related ADRs (including superseded decisions) and affected domains remain
;; non-authoritative projections over admitted revision facts.
(def (gitops-review-lineage revision changes inputs reports missing parsed-documents
                            (policy-sources '()) (engineering-reference #f)
                            adr-references: (adr-references '())
                            affected-domains: (affected-domains '()))
  (validate-lineage-observations! changes inputs reports missing parsed-documents policy-sources)
  (let* ((root (string->symbol revision))
         (path-id (lambda (path) (string->symbol (string-append revision "#path:" path))))
         (report-id (lambda (method) (string->symbol (string-append revision "#report:" method))))
         (reference-id (string->symbol (string-append revision "#engineering-reference")))
         (adr-id (lambda (id) (string->symbol (string-append revision "#adr:" id))))
         (domain-id (lambda (name) (string->symbol (string-append revision "#domain:" name))))
         (input-paths (map observed-path inputs))
         (policy-paths (map observed-path policy-sources))
         (changed (map observed-path changes))
         (changed-nodes
          (map (lambda (row)
                 (let (file-path (hash-ref row "path"))
                   (lineage-node
                    (path-id file-path)
                    (.o label: 'FileVersion path: file-path changed: #t
                        before: (hash-ref row "before") after: (hash-ref row "after")))))
               changes))
         (unchanged-nodes
          (map (lambda (row)
                 (let (file-path (hash-ref row "path"))
                   (lineage-node
                    (path-id file-path)
                    (.o label: 'FileVersion path: file-path changed: #f
                        after: (hash-ref row "entry")))))
               (filter (lambda (row) (not (member (observed-path row) changed)))
                       (append inputs
                               (filter (lambda (row) (not (member (observed-path row) input-paths)))
                                       policy-sources)))))
         (report-node
          (lambda (method state)
            (lineage-node (report-id method)
                          (.o label: 'EvidenceReport (method := method) (state := state))))))
    (when (and engineering-reference
               (not (member (.get engineering-reference source) policy-paths)))
      (error "Engineering reference source is outside the recorded policy files"))
    (validate-adr-references! adr-references policy-paths)
    (validate-affected-domains! affected-domains changed)
    (yuanxu-graph
     root
     (append (list (lineage-node root (.o label: 'Revision (revision := revision))))
             changed-nodes unchanged-nodes
             (if engineering-reference
                 (list (lineage-node reference-id
                         (.o label: 'EngineeringReference
                             engineeringId: (.get engineering-reference engineering-id)
                             element: (.get engineering-reference element))))
                 '())
             (map (lambda (adr)
                    (let ((adr-status (.get adr status)))
                      (lineage-node (adr-id (.get adr identity))
                        (.o label: 'DecisionRecord
                            (adrId := (.get adr identity))
                            (revision := (.get adr revision))
                            (status := (symbol->string adr-status))
                            (relation := (symbol->string (.get adr relation)))
                            (superseded := (eq? adr-status 'superseded))))))
                  adr-references)
             (map (lambda (row)
                    (lineage-node (domain-id (.get row domain))
                      (.o label: 'Domain
                          (domain := (.get row domain))
                          (ownerModule := (.get row owner-module)))))
                  affected-domains)
             (map (lambda (method) (report-node method 'verified)) reports)
             (map (lambda (method) (report-node method 'missing)) missing))
     (append
      (map (lambda (path) (yuanxu-graph-edge root (path-id path) 'changes)) changed)
      (map (lambda (path) (yuanxu-graph-edge root (path-id path) 'reads_config)) input-paths)
      (map (lambda (path) (yuanxu-graph-edge root (path-id path) 'has_policy_source)) policy-paths)
      (if engineering-reference
          (list (yuanxu-graph-edge root reference-id 'names_engineering_item)
                (yuanxu-graph-edge reference-id
                  (path-id (.get engineering-reference source)) 'declared_in))
          '())
      (apply append
        (map (lambda (adr)
               (let ((node (adr-id (.get adr identity))))
                 (append
                  (list (yuanxu-graph-edge root node 'relates_decision)
                        (yuanxu-graph-edge node (path-id (.get adr source)) 'declared_in))
                  (if engineering-reference
                      (list (yuanxu-graph-edge node reference-id (.get adr relation)))
                      '()))))
             adr-references))
      (apply append
        (map (lambda (row)
               (let ((node (domain-id (.get row domain))))
                 (cons (yuanxu-graph-edge root node 'affects_domain)
                       (map (lambda (path)
                              (yuanxu-graph-edge (path-id path) node 'owned_by_domain))
                            (.get row paths)))))
             affected-domains))
      (map (lambda (method) (yuanxu-graph-edge root (report-id method) 'verified_report)) reports)
      (map (lambda (method) (yuanxu-graph-edge root (report-id method) 'missing_report)) missing)
      (map (lambda (path)
             (yuanxu-graph-edge (path-id path) (report-id "sysml.parse") 'parsed_by))
           parsed-documents)
      (if (member "jj.recorded-change" reports)
          (map (lambda (path)
                 (yuanxu-graph-edge (path-id path) (report-id "jj.recorded-change") 'enumerated_by))
               changed)
          '())))))
