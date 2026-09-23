;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Aitia only maps assurance relation semantics onto a POO Flow
;;; Graph. Impact traversal, relation trajectories, and SCC analysis remain
;;; owned by POO Flow.

(import (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/graph/algorithms
                 poo-flow-graph-loop-analysis-receipt)
        (only-in :poo-flow/src/graph/types
                 poo-flow-graph poo-flow-graph-edge poo-flow-graph-node)
        (only-in :poo-flow/src/modules/temporal-causality/funs
                 poo-flow-structural-impact-analyze)
        (only-in :gerbil/core list-sort)
        :std/list/list
        :poo-flow/lambda-aitia/modules/assurance/types)

(export assurance-invalidation-graph assurance-invalidation-analysis)

(def +assurance-invalidation-relations+
  '(depends-on implements tests refines supports discharges
    invalidates defeats authorizes denies requires-review))

(def (invalidation-graph-id identity)
  (string->symbol identity))

(def (invalidation-direction relation)
  (let ((plane (.ref relation 'plane)) (kind (.ref relation 'relation)))
    (cond
     ((and (eq? plane 'structural)
           (memq kind '(depends-on implements tests refines)))
      (cons (.ref relation 'target) (.ref relation 'source)))
     ((and (eq? plane 'assurance) (memq kind '(supports discharges)))
      (cons (.ref relation 'target) (.ref relation 'source)))
     ((and (eq? plane 'assurance) (memq kind '(invalidates defeats)))
      (cons (.ref relation 'source) (.ref relation 'target)))
     ((and (eq? plane 'authority)
           (memq kind '(authorizes denies requires-review)))
      (cons (.ref relation 'source) (.ref relation 'target)))
     (else #f))))

(def (known-direction? direction identities)
  (and direction
       (member (car direction) identities)
       (member (cdr direction) identities)))

(def (assurance-invalidation-graph snapshot)
  (unless (assurance-snapshot? snapshot) (error "invalid assurance snapshot"))
  (let* ((nodes (.ref snapshot 'nodes))
         (identities (map (lambda (node) (.ref node 'identity)) nodes))
         (relations (.ref snapshot 'relations))
         (graph-nodes
          (map (lambda (node)
                 (poo-flow-graph-node
                  (invalidation-graph-id (.ref node 'identity)) (.ref node 'kind)
                  (list (cons 'semantic-owner 'lambda-aitia)
                        (cons 'assurance-identity (.ref node 'identity))
                        (cons 'revision (.ref node 'revision)))))
               nodes))
         (graph-edges
          (map (lambda (entry)
                 (let ((relation (car entry)) (direction (cdr entry)))
                   (poo-flow-graph-edge
                    (invalidation-graph-id (car direction))
                    (invalidation-graph-id (cdr direction))
                    (.ref relation 'relation)
                    (list (cons 'relation-identity (.ref relation 'identity))
                          (cons 'relation-plane (.ref relation 'plane))))))
               (filter (lambda (entry)
                         (known-direction? (cdr entry) identities))
                       (map (lambda (relation)
                              (cons relation (invalidation-direction relation)))
                            relations)))))
    (poo-flow-graph
     (invalidation-graph-id (.ref snapshot 'graph-identity))
     graph-nodes graph-edges
     (list (cons 'semantic-owner 'lambda-aitia)
           (cons 'graph-owner 'poo-flow)
           (cons 'purpose 'structural-invalidation)))))

(def (components->identities components)
  (map (lambda (component) (map symbol->string component)) components))

(def (trajectory->projection trajectory)
  (list (symbol->string (.ref trajectory 'target-node-id))
        (map symbol->string (.ref trajectory 'node-path))
        (map symbol->string (.ref trajectory 'relation-path))))

(def (trajectory-projection<? left right)
  (string<? (car left) (car right)))

(def (assurance-invalidation-analysis snapshot seeds)
  (let* ((graph-value (assurance-invalidation-graph snapshot))
         (loop-analysis (poo-flow-graph-loop-analysis-receipt graph-value)))
    (if (null? seeds)
      (values '() '()
              (components->identities (.ref loop-analysis 'components))
              (components->identities (.ref loop-analysis 'cyclic-components)))
      (let* ((impact
              (poo-flow-structural-impact-analyze
               graph-value
               (map invalidation-graph-id seeds)
               +assurance-invalidation-relations+
               'dependencies
               (and (null? (.ref snapshot 'unresolved))
                    (null? (.ref snapshot 'conflicts)))))
             (affected
              (list-sort string<?
                         (map symbol->string (.ref impact 'affected-node-ids))))
             (trajectories
              (list-sort trajectory-projection<?
                         (map trajectory->projection
                              (.ref impact 'relation-trajectories)))))
        (values affected trajectories
                (components->identities (.ref loop-analysis 'components))
                (components->identities
                 (.ref loop-analysis 'cyclic-components)))))))
