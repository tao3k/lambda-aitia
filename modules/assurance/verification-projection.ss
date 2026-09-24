;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Aitia owns the meaning of obligation dependencies; POO Flow owns Graph
;;; ordering, reachability and cycle algorithms. No verifier runs here.

(import (only-in :clan/poo/object .ref)
        (only-in :gerbil/core list-sort)
        :std/list/list
        (only-in :poo-flow/src/graph/types
                 poo-flow-graph poo-flow-graph-edge poo-flow-graph-node)
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-verification-dependency-graph)

(def (canonical-ids ids)
  (list-sort string<? (delete-duplicates/hash ids)))

(def (obligation-node? nodes identity)
  (let ((node
         (find (lambda (candidate)
                 (string=? (.ref candidate 'identity) identity))
               nodes)))
    (and node (assurance-obligation? node))))

;;; Returns a POO Graph and the direct prerequisite IDs for each planned
;;; obligation. A prerequisite outside the affected set remains visible to
;;; the planner; it is never presumed discharged by an older plan.
(def (assurance-verification-dependency-graph snapshot obligation-ids)
  (unless (and (assurance-snapshot? snapshot)
               (list? obligation-ids)
               (every assurance-text? obligation-ids))
    (error "invalid verification dependency projection"))
  (let* ((ids (canonical-ids obligation-ids))
         (nodes (.ref snapshot 'nodes))
         (relations (.ref snapshot 'relations))
         (prerequisites
          (map
           (lambda (id)
             (cons id
                   (canonical-ids
                    (map (lambda (relation) (.ref relation 'target))
                         (filter
                          (lambda (relation)
                            (and (eq? (.ref relation 'plane) 'structural)
                                 (eq? (.ref relation 'relation) 'depends-on)
                                 (string=? (.ref relation 'source) id)
                                 (obligation-node?
                                  nodes (.ref relation 'target))))
                          relations)))))
           ids))
         (edges
          (concatenate
           (map
            (lambda (entry)
              (map (lambda (prerequisite)
                     (poo-flow-graph-edge prerequisite (car entry)
                                          'depends-on))
                   (filter (lambda (prerequisite)
                             (member prerequisite ids))
                           (cdr entry))))
            prerequisites)))
         (graph-value
          (poo-flow-graph
           (string-append (.ref snapshot 'graph-identity) "/verification")
           (map poo-flow-graph-node ids)
           edges
           (list (cons 'semantic-owner 'lambda-aitia)
                 (cons 'graph-owner 'poo-flow)
                 (cons 'purpose 'verification-dependencies)))))
    (values graph-value prerequisites)))
