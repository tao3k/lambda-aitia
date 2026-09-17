;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/crypto/digest sha256)
        (only-in :std/sort sort)
        (only-in :std/srfi/1 every filter)
        (only-in :std/text/hex hex-encode)
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-node-canonical assurance-relation-canonical
        assurance-canonical-digest assurance-snapshot
        assurance-support-admissible? assurance-invalidate)

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
     (call-with-output-string (lambda (port) (write value port)))))))

(def (canonical<? left right)
  (string<? (car left) (car right)))
(def (canonical-objects input-values projection)
  (sort (map projection input-values) canonical<?))

;;; Returns canonical unique objects and conflicting identities.  Equal
;;; duplicates collapse; unequal duplicates never use last-write-wins.
(def (deduplicate input-values projection)
  (let loop ((rest input-values) (seen '()) (unique '()) (conflicts '()))
    (if (null? rest)
      (values (reverse unique) (sort conflicts string<?))
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
  (let loop ((rest (sort input-values string<?)) (previous #f) (result '()))
    (cond
     ((null? rest) (reverse result))
     ((and previous (string=? previous (car rest)))
      (loop (cdr rest) previous result))
     (else (loop (cdr rest) (car rest) (cons (car rest) result))))))

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
    (let* ((identities (known-identities unique-nodes))
           (missing
            (ordered-unique-text
             (append unresolved
                     (apply append
                            (map (lambda (relation)
                                   (relation-unresolved relation identities))
                                 unique-relations)))))
           (conflicts-value
            (ordered-unique-text
             (append node-conflicts relation-conflicts)))
           (ordered-nodes
            (sort unique-nodes
                  (lambda (left right)
                    (string<? (.ref left 'identity) (.ref right 'identity)))))
           (ordered-relations
            (sort unique-relations
                  (lambda (left right)
                    (string<? (.ref left 'identity) (.ref right 'identity)))))
           (node-states (map (lambda (node) (.ref node 'state)) ordered-nodes))
           (snapshot-state
            (cond ((pair? conflicts-value) 'conflicted)
                  ((pair? missing) 'unknown)
                  ((memq 'violated node-states) 'violated)
                  ((memq 'stale node-states) 'stale)
                  ((or (memq 'unknown node-states)
                       (memq 'hypothesized node-states)
                       (memq 'counterfactual node-states)) 'unknown)
                  (else 'supported)))
           (canonical
            (list 'lambda-aitia.assurance-snapshot identity-value revision-value
                  graph-identity-value source-revision-values claim-revision-values
                  fact-cut-value policy-identity-value policy-revision-value
                  evidence-identity-values
                  snapshot-state
                  (canonical-objects ordered-nodes assurance-node-canonical)
                  (canonical-objects ordered-relations assurance-relation-canonical)
                  missing conflicts-value))
           (snapshot-digest (assurance-canonical-digest canonical)))
      (poo-flow-check-model
       AssuranceSnapshot
       (.o (:: @ (poo-flow-model-prototype AssuranceSnapshot))
           identity: identity-value revision: revision-value
           graph-identity: graph-identity-value
           source-revisions: source-revision-values
           claim-revisions: claim-revision-values fact-cut: fact-cut-value
           policy-identity: policy-identity-value policy-revision: policy-revision-value
           evidence-identities: evidence-identity-values
           state: snapshot-state digest: snapshot-digest
           nodes: ordered-nodes relations: ordered-relations
           unresolved: missing conflicts: conflicts-value)))))

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
       (not (memq (.ref evidence 'state) '(hypothesized counterfactual stale
                                            conflicted unknown violated)))
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
(def (dependency-from relation current)
  (let ((kind (.ref relation 'relation))
        (source (.ref relation 'source))
        (target (.ref relation 'target)))
    (cond
     ((and (memq kind '(depends-on implements tests refines supports discharges))
           (string=? target current))
      source)
     ((and (memq kind '(invalidates defeats authorizes denies requires-review
                        enables prevents causal-parent))
           (string=? source current))
      target)
     (else #f))))
(def (impact-closure relations seeds)
  (let loop ((frontier (ordered-unique seeds))
             (impacted (ordered-unique seeds))
             (witnesses '()))
    (if (null? frontier)
      (values (ordered-unique impacted) (reverse witnesses))
      (let ((current (car frontier)))
        (let scan ((rest relations) (additions '()) (new-witnesses witnesses))
          (if (null? rest)
            (loop (append (cdr frontier) (reverse additions))
                  (append additions impacted) new-witnesses)
            (let* ((relation (car rest))
                   (addition (dependency-from relation current)))
              (if (and addition
                       (not (identity-member? addition impacted))
                       (not (identity-member? addition additions)))
                (scan
                 (cdr rest) (cons addition additions)
                 (cons (list (.ref relation 'identity)
                             (.ref relation 'source)
                             (.ref relation 'target))
                       new-witnesses))
                (scan (cdr rest) additions new-witnesses)))))))))
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
         (relations (.ref snapshot 'relations))
         (known (map (lambda (node) (.ref node 'identity)) nodes))
         (unresolved
          (ordered-unique
           (filter (lambda (identity) (not (identity-member? identity known)))
                   changed-identities))))
    (let-values (((impacted witnesses)
                  (impact-closure relations
                                  (filter (lambda (identity)
                                            (identity-member? identity known))
                                          changed-identities))))
      (make-assurance-invalidation-receipt-record
       receipt-identity (.ref snapshot 'digest)
       (ordered-unique changed-identities) impacted
       (impacted-kind-identities nodes impacted 'evidence)
       (impacted-kind-identities nodes impacted 'obligation)
       (impacted-kind-identities nodes impacted 'decision)
       (impacted-kind-identities nodes impacted 'effect)
       witnesses unresolved #f #f #f))))
