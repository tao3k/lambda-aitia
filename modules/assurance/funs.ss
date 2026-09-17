;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/crypto/digest sha256)
        (only-in :std/sort sort)
        (only-in :std/srfi/1 every)
        (only-in :std/text/hex hex-encode)
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-node-canonical assurance-relation-canonical
        assurance-canonical-digest assurance-snapshot
        assurance-support-admissible?)

(def (assurance-node-canonical node)
  (unless (assurance-node? node) (error "invalid assurance node" node))
  (list (.ref node 'identity) (.ref node 'kind) (.ref node 'revision)
        (.ref node 'state) (.ref node 'content-digest)))
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

(def (assurance-snapshot identity-value revision-value nodes relations
                         (unresolved '()))
  (unless (and (list? nodes) (every assurance-node? nodes)
               (list? relations) (every assurance-relation? relations)
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
           (snapshot-state
            (cond ((pair? conflicts-value) 'conflicted)
                  ((pair? missing) 'unknown)
                  (else 'supported)))
           (canonical
            (list 'lambda-aitia.assurance-snapshot identity-value revision-value
                  snapshot-state
                  (canonical-objects ordered-nodes assurance-node-canonical)
                  (canonical-objects ordered-relations assurance-relation-canonical)
                  missing conflicts-value))
           (snapshot-digest (assurance-canonical-digest canonical)))
      (poo-flow-check-model
       AssuranceSnapshot
       (.o (:: @ (poo-flow-model-prototype AssuranceSnapshot))
           identity: identity-value revision: revision-value
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
