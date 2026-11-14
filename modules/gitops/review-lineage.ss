;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .cc .get)
        (only-in :gerbil/core string-suffix?)
        (only-in :tao3k/yuanxu/graph/types yuanxu-graph yuanxu-graph-edge yuanxu-graph-node))
(export gitops-review-lineage)

(def (lineage-node identity-value payload)
  (yuanxu-graph-node identity-value (.cc payload identity: identity-value)))

(def (index-observations rows key label)
  (let (index (make-hash-table))
    (for-each
     (lambda (row)
       (let (identity-value (key row))
         (when (hash-key? index identity-value)
           (error "Duplicate review lineage observation" label identity-value))
         (hash-put! index identity-value row)))
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

;; The JJ host has already verified the applied revision and reproduced the
;; archived reports. This projection records observed relations only.
(def (gitops-review-lineage revision-value changes inputs reports missing parsed-documents
                           (policy-sources '()) (engineering-reference #f))
  (validate-lineage-observations! changes inputs reports missing parsed-documents policy-sources)
  (let* ((root (string->symbol revision-value))
         (path-id (lambda (path) (string->symbol (string-append revision-value "#path:" path))))
         (report-id (lambda (method) (string->symbol (string-append revision-value "#report:" method))))
         (reference-id (string->symbol (string-append revision-value "#engineering-reference")))
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
          (lambda (method-value state-value)
            (lineage-node (report-id method-value)
                               (.o label: 'EvidenceReport method: method-value state: state-value)))))
    (when (and engineering-reference
               (not (member (.get engineering-reference source) policy-paths)))
      (error "Engineering reference source is outside the recorded policy files"))
    (yuanxu-graph
     root
     (append (list (lineage-node root (.o label: 'Revision revision: revision-value)))
             changed-nodes unchanged-nodes
             (if engineering-reference
                 (list (lineage-node reference-id
                         (.o label: 'EngineeringReference
                             engineeringId: (.get engineering-reference engineering-id)
                             element: (.get engineering-reference element))))
                 '())
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
