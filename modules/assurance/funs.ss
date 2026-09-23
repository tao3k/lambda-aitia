;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/crypto/digest sha256)
        (only-in :gerbil/core list-sort string->utf8)
        :std/list/list
        (only-in :std/encoding/hex hex-encode)
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types
        (only-in :poo-flow/lambda-aitia/modules/assurance/invalidation-projection
                 assurance-invalidation-analysis assurance-invalidation-graph))

(export assurance-node-canonical assurance-relation-canonical
        assurance-canonical-digest assurance-snapshot
        assurance-support-admissible? assurance-invalidation-graph
        assurance-invalidate)

(def (assurance-node-semantic-slots kind)
  (case kind
    ((artifact) '(owner media-kind provenance))
    ((claim) '(subject predicate assumptions defeaters support-requirements
               scope valid-from valid-until))
    ((assumption) '(owner scope review-policy expires-at))
    ((observation) '(subject source clock-role logical-position))
    ((event) '(subject event-kind observation payload-digest modality
               commitment-state causal-parents))
    ((action) '(subject action-kind requested-by scope))
    ((obligation) '(subject claim snapshot evidence-kind capability scope))
    ((evidence) '(producer tool tool-version input-artifacts obligation subject
                  scope valid-from valid-until admission-state))
    ((counterexample) '(subject challenges evidence details-digest))
    ((finding) '(subject challenges evidence finding-kind))
    ((decision) '(subject snapshot policy authority outcome))
    ((effect) '(subject decision effect-kind effect-state))
    (else (error "unknown assurance node kind" kind))))

(def (assurance-node-canonical node)
  (unless (assurance-node? node) (error "invalid assurance node" node))
  (list (.ref node 'identity) (.ref node 'kind) (.ref node 'revision)
        (.ref node 'state) (.ref node 'content-digest)
        (map (lambda (name) (list name (.ref node name)))
             (assurance-node-semantic-slots (.ref node 'kind)))))
(def (assurance-relation-canonical relation)
  (unless (assurance-relation? relation)
    (error "invalid assurance relation" relation))
  (list (.ref relation 'identity) (.ref relation 'plane)
        (.ref relation 'relation) (.ref relation 'source)
        (.ref relation 'target) (.ref relation 'modality)))
(def (assurance-canonical-digest value)
  (string-append
   "sha256:"
   (hex-encode
    (sha256
     (string->utf8
      (call-with-output-string (lambda (port) (write value port))))))))

(def (canonical<? left right)
  (string<? (car left) (car right)))
(def (canonical-objects input-values projection)
  (list-sort canonical<? (map projection input-values)))

;;; Returns canonical unique objects and conflicting identities.  Equal
;;; duplicates collapse; unequal duplicates never use last-write-wins.
(def (deduplicate input-values projection)
  (let loop ((rest input-values) (seen '()) (unique '()) (conflicts '()))
    (if (null? rest)
      (values (reverse unique) (list-sort string<? conflicts))
      (let* ((value (car rest))
             (canonical (projection value))
             (identity (car canonical))
             (entry (assoc identity seen)))
        (cond
         ((not entry)
          (loop (cdr rest) (cons (cons identity canonical) seen)
                (cons value unique) conflicts))
         ((equal? canonical (cdr entry))
          (loop (cdr rest) seen unique conflicts))
         (else
          (loop (cdr rest) seen unique
                (if (member identity conflicts) conflicts
                    (cons identity conflicts)))))))))

(def (known-identities nodes)
  (map (lambda (node) (.ref node 'identity)) nodes))
(def (relation-unresolved relation identities)
  (let ((source (.ref relation 'source)) (target (.ref relation 'target)))
    (append (if (member source identities) '() (list source))
            (if (member target identities) '() (list target)))))
(def (ordered-unique-text input-values)
  (list-sort string<? (delete-duplicates/hash input-values)))

(def (canonical-bindings input-values)
  (let loop ((rest (list-sort
                    (lambda (left right)
                      (string<? (car left) (car right)))
                    (map (lambda (binding) binding) input-values)))
             (seen '()) (result '()) (conflicts '()))
    (if (null? rest)
      (values (reverse result)
              (ordered-unique-text conflicts))
      (let* ((binding (car rest))
             (identity (car binding))
             (revision (cdr binding))
             (previous (assoc identity seen)))
        (cond
         ((not previous)
          (loop (cdr rest) (cons binding seen) (cons binding result) conflicts))
         ((string=? revision (cdr previous))
          (loop (cdr rest) seen result conflicts))
         (else
          (loop (cdr rest) seen result (cons identity conflicts))))))))

(def (inventory-node nodes identity)
  (find (lambda (node) (string=? (.ref node 'identity) identity)) nodes))

;;; Snapshot bindings are semantic claims about the exact node inventory, not
;;; free-standing metadata.  Missing identities retain an unknown frontier;
;;; wrong kinds or revisions are contradictory and therefore conflicted.
(def (binding-resolution bindings expected-kind nodes)
  (let loop ((rest bindings) (missing '()) (conflicts '()))
    (if (null? rest)
      (values (ordered-unique-text missing) (ordered-unique-text conflicts))
      (let* ((binding (car rest))
             (identity (car binding))
             (revision (cdr binding))
             (node (inventory-node nodes identity)))
        (cond
         ((not node)
          (loop (cdr rest) (cons identity missing) conflicts))
         ((or (not (eq? (.ref node 'kind) expected-kind))
              (not (string=? (.ref node 'revision) revision)))
          (loop (cdr rest) missing (cons identity conflicts)))
         (else (loop (cdr rest) missing conflicts)))))))

(def (evidence-resolution identities nodes)
  (let loop ((rest identities) (missing '()) (conflicts '()))
    (if (null? rest)
      (values (ordered-unique-text missing) (ordered-unique-text conflicts))
      (let* ((identity (car rest))
             (node (inventory-node nodes identity)))
        (cond
         ((not node)
          (loop (cdr rest) (cons identity missing) conflicts))
         ((or (not (eq? (.ref node 'kind) 'evidence))
              (not (eq? (.ref node 'state) 'supported))
              (not (eq? (.ref node 'admission-state) 'admitted)))
          (loop (cdr rest) missing (cons identity conflicts)))
         (else (loop (cdr rest) missing conflicts)))))))

(def (assurance-snapshot identity-value revision-value graph-identity-value
                         source-revision-values claim-revision-values
                         fact-cut-value policy-identity-value policy-revision-value
                         nodes relations
                         evidence-identities: (evidence-identity-values '())
                         unresolved: (unresolved '()))
  (unless (and (list? nodes) (every assurance-node? nodes)
               (list? relations) (every assurance-relation? relations)
               (list? source-revision-values)
               (list? claim-revision-values)
               (list? evidence-identity-values)
               (list? unresolved) (every assurance-text? unresolved))
    (error "invalid assurance snapshot inventory"))
  (let-values (((unique-nodes node-conflicts)
                (deduplicate nodes assurance-node-canonical))
               ((unique-relations relation-conflicts)
                (deduplicate relations assurance-relation-canonical)))
    (let-values (((canonical-source-revisions source-revision-conflicts)
                  (canonical-bindings source-revision-values)))
      (let-values (((canonical-claim-revisions claim-revision-conflicts)
                    (canonical-bindings claim-revision-values)))
        (let ((canonical-evidence-identities
               (ordered-unique-text evidence-identity-values)))
          (let-values (((source-binding-missing source-binding-conflicts)
                        (binding-resolution canonical-source-revisions
                                            'artifact unique-nodes))
                       ((claim-binding-missing claim-binding-conflicts)
                        (binding-resolution canonical-claim-revisions
                                            'claim unique-nodes))
                       ((evidence-binding-missing evidence-binding-conflicts)
                        (evidence-resolution canonical-evidence-identities
                                             unique-nodes)))
        (let* ((identities (known-identities unique-nodes))
           (missing
            (ordered-unique-text
             (append unresolved source-binding-missing claim-binding-missing
                     evidence-binding-missing
                     (concatenate
                      (map (lambda (relation)
                             (relation-unresolved relation identities))
                           unique-relations)))))
           (conflicts-value
            (ordered-unique-text
             (append node-conflicts relation-conflicts)))
           (binding-conflicts
            (ordered-unique-text
             (append source-revision-conflicts claim-revision-conflicts
                     source-binding-conflicts claim-binding-conflicts
                     evidence-binding-conflicts)))
           (all-conflicts
            (ordered-unique-text (append conflicts-value binding-conflicts)))
           (ordered-nodes
            (list-sort
             (lambda (left right)
               (string<? (.ref left 'identity) (.ref right 'identity)))
             unique-nodes))
           (ordered-relations
            (list-sort
             (lambda (left right)
               (string<? (.ref left 'identity) (.ref right 'identity)))
             unique-relations))
           (node-states (map (lambda (node) (.ref node 'state)) ordered-nodes))
           (snapshot-state
            (cond ((pair? all-conflicts) 'conflicted)
                  ((pair? missing) 'unknown)
                  ((memq 'violated node-states) 'violated)
                  ((memq 'stale node-states) 'stale)
                  ((or (memq 'unknown node-states)
                       (memq 'hypothesized node-states)
                       (memq 'counterfactual node-states)) 'unknown)
                  (else 'supported)))
           (canonical
            (list 'lambda-aitia.assurance-snapshot identity-value revision-value
                  graph-identity-value canonical-source-revisions
                  canonical-claim-revisions
                  fact-cut-value policy-identity-value policy-revision-value
                  canonical-evidence-identities
                  snapshot-state
                  (canonical-objects ordered-nodes assurance-node-canonical)
                  (canonical-objects ordered-relations assurance-relation-canonical)
                  missing all-conflicts))
           (snapshot-digest (assurance-canonical-digest canonical)))
      (poo-flow-check-model
       AssuranceSnapshot
       (.o (:: @ (poo-flow-model-prototype AssuranceSnapshot))
           identity: identity-value revision: revision-value
           graph-identity: graph-identity-value
           source-revisions: canonical-source-revisions
           claim-revisions: canonical-claim-revisions fact-cut: fact-cut-value
           policy-identity: policy-identity-value policy-revision: policy-revision-value
           evidence-identities: canonical-evidence-identities
           state: snapshot-state digest: snapshot-digest
           nodes: ordered-nodes relations: ordered-relations
           unresolved: missing conflicts: all-conflicts)))))))))

;;; Shape and a green-looking relation never grant support.  The exact
;;; evidence and obligation identities must match, and alternate modalities
;;; cannot discharge an observed-fact obligation.
(def (assurance-support-admissible? relation evidence obligation)
  (and (assurance-relation? relation)
       (assurance-evidence? evidence)
       (assurance-obligation? obligation)
       (eq? (.ref relation 'plane) 'assurance)
       (memq (.ref relation 'relation) '(supports discharges))
       (equal? (.ref relation 'source) (.ref evidence 'identity))
       (equal? (.ref relation 'target) (.ref obligation 'identity))
       (equal? (.ref evidence 'obligation) (.ref obligation 'identity))
       (equal? (.ref evidence 'subject) (.ref obligation 'subject))
       (equal? (.ref evidence 'scope) (.ref obligation 'scope))
       (equal? (.ref evidence 'revision) (.ref obligation 'revision))
       (eq? (.ref evidence 'state) 'supported)
       (eq? (.ref evidence 'admission-state) 'admitted)
       (not (memq (.ref relation 'modality) '(hypothesized counterfactual)))))

(def (identity-member? identity values)
  (if (member identity values) #t #f))
(def (ordered-unique input-values)
  (ordered-unique-text input-values))
(def (node-by-identity nodes identity)
  (let loop ((rest nodes))
    (cond ((null? rest) #f)
          ((string=? (.ref (car rest) 'identity) identity) (car rest))
          (else (loop (cdr rest))))))
(def (impacted-kind-identities nodes impacted kind)
  (ordered-unique
   (map (lambda (node) (.ref node 'identity))
        (filter (lambda (node)
                  (and (eq? (.ref node 'kind) kind)
                       (identity-member? (.ref node 'identity) impacted)))
                nodes))))

;;; This is an inert, pure impact receipt.  It selects current affected values;
;;; Phase 3 owns derivation of replacement obligations and no verifier is called.
(def (assurance-invalidate receipt-identity snapshot changed-identities)
  (unless (and (assurance-text? receipt-identity)
               (assurance-snapshot? snapshot)
               (list? changed-identities)
               (every assurance-text? changed-identities))
    (error "invalid assurance invalidation input"))
  (let* ((nodes (.ref snapshot 'nodes))
         (known (map (lambda (node) (.ref node 'identity)) nodes))
         (unresolved
          (ordered-unique
           (append
            (.ref snapshot 'unresolved)
            (filter (lambda (identity) (not (identity-member? identity known)))
                    changed-identities)))))
    (let ((seeds (filter (lambda (identity)
                           (identity-member? identity known))
                         changed-identities)))
      (let-values (((impacted witnesses strong-components cyclic-components)
                    (assurance-invalidation-analysis snapshot seeds)))
        (make-assurance-invalidation-receipt-record
         receipt-identity (.ref snapshot 'digest)
         (ordered-unique changed-identities) impacted
         (impacted-kind-identities nodes impacted 'evidence)
         (impacted-kind-identities nodes impacted 'obligation)
         (impacted-kind-identities nodes impacted 'decision)
         (impacted-kind-identities nodes impacted 'effect)
         witnesses unresolved strong-components cyclic-components
         #f #f #f)))))
