;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow/src/graph/algorithms
                 poo-flow-graph-cycle-path
                 poo-flow-graph-topological-order)
        (only-in :poo-flow/src/graph/types
                 poo-flow-graph poo-flow-graph-edge poo-flow-graph-node)
        (only-in :poo-flow/src/modules/governance/funs
                 poo-flow-governance-contribution)
        (only-in :std/srfi/1 every delete-duplicates))
(import :poo-flow/lambda-aitia/modules/sdlc/types :poo-flow/lambda-aitia/modules/sdlc/objects)
(export sdlc-with-standards sdlc-contribution sdlc-module
        +sdlc-flow-stages+ sdlc-flow-graph sdlc-flow-plan)

;;; Aitia owns the SDLC phase vocabulary; POO Flow owns Graph and DAG analysis.
;;; This projection is inert and does not execute a verifier or grant authority.
(def +sdlc-flow-stages+
  '(change invalidate plan verify admit decide authorize effect))

(def (sdlc-flow-node-id lifecycle-id stage)
  (string->symbol
   (string-append lifecycle-id "/" (symbol->string stage))))

(def (sdlc-flow-graph lifecycle-id)
  (unless (sdlc-text? lifecycle-id)
    (error "SDLC flow requires a non-empty lifecycle identity" lifecycle-id))
  (let ((nodes
         (map (lambda (stage)
                (poo-flow-graph-node
                 (sdlc-flow-node-id lifecycle-id stage)
                 stage
                 (list (cons 'semantic-owner 'lambda-aitia))))
              +sdlc-flow-stages+))
        (edges
         (let loop ((stages +sdlc-flow-stages+) (result '()))
           (if (or (null? stages) (null? (cdr stages)))
             (reverse result)
             (loop
              (cdr stages)
              (cons
               (poo-flow-graph-edge
                (sdlc-flow-node-id lifecycle-id (car stages))
                (sdlc-flow-node-id lifecycle-id (cadr stages))
                'sdlc-next
                (list (cons 'semantic-owner 'lambda-aitia)))
               result))))))
    (poo-flow-graph
     lifecycle-id nodes edges
     (list (cons 'semantic-owner 'lambda-aitia)
           (cons 'runtime-owner 'poo-flow)))))

(def (sdlc-flow-plan lifecycle-id)
  (let* ((graph-value (sdlc-flow-graph lifecycle-id))
         (cycle-path (poo-flow-graph-cycle-path graph-value))
         (order (and (not cycle-path)
                     (poo-flow-graph-topological-order graph-value))))
    (.o schema: 'lambda-aitia.sdlc-flow-plan
        lifecycle-id: lifecycle-id
        graph: graph-value
        stages: +sdlc-flow-stages+
        topological-order: order
        cycle-path: cycle-path
        accepted?: (and order #t)
        semantic-owner: 'lambda-aitia
        runtime-owner: 'poo-flow
        release-authorized?: #f
        runtime-executed?: #f)))
(def (sdlc-with-standards profile-value standard-values)
  (unless (and (sdlc-profile? profile-value)
               (list? standard-values) (every standard-profile? standard-values))
    (error "invalid SDLC standard selection"))
  (let ((identities (map (lambda (standard) (.ref standard 'identity)) standard-values)))
    (unless (= (length identities) (length (delete-duplicates identities equal?)))
      (error "duplicate SDLC standard identity")))
  (.o (:: @ profile-value) standards: standard-values))
(def (sdlc-contribution profile-value)
  (unless (sdlc-profile? profile-value)
    (error "invalid SDLC profile" profile-value))
  (poo-flow-governance-contribution
   profile-value '(lifecycle-governance) '()))
(def sdlc-module (sdlc-contribution SdlcProfile))

(import (only-in :std/srfi/1 any filter find))
(export sdlc-trace-review)
(def (trace-bound? value project)
  (every (lambda (slot) (equal? (.ref value slot) (.ref project slot))) '(subject revision scope)))
(def (unique-identities? values)
  (let ((ids (map (lambda (v) (.ref v 'identity)) values)))
    (= (length ids) (length (delete-duplicates ids equal?)))))
(def (sdlc-trace-review project rule nodes edges)
  (unless (and (sdlc-project? project) (sdlc-trace-rule? rule)
               (list? nodes) (every sdlc-trace-node? nodes) (unique-identities? nodes)
               (list? edges) (every sdlc-trace-edge? edges) (unique-identities? edges))
    (error "invalid or ambiguous trace inventory"))
  (let* ((current-nodes (filter (lambda (n) (trace-bound? n project)) nodes))
         (selected (filter (lambda (e) (and (trace-bound? e project)
                                            (equal? (.ref e 'relation) (.ref rule 'identity)))) edges))
         (of-kind (lambda (category) (filter (lambda (n) (eq? (.ref n 'category) category)) current-nodes)))
         (sources (of-kind (.ref rule 'source-category)))
         (targets (of-kind (.ref rule 'target-category)))
         (endpoint? (lambda (id values) (any (lambda (n) (equal? (.ref n 'identity) id)) values)))
         (valid-edges (filter (lambda (e) (and (endpoint? (.ref e 'source) sources)
                                              (endpoint? (.ref e 'target) targets))) selected))
         (unresolved-edge-values (filter (lambda (e) (not (memq e valid-edges))) selected))
         (unlinked (lambda (values slot)
                     (map (lambda (n) (.ref n 'identity))
                          (filter (lambda (n) (not (any (lambda (e)
                                                         (equal? (.ref e slot) (.ref n 'identity))) valid-edges))) values))))
         (forward (unlinked sources 'source))
         (backward (unlinked targets 'target))
         (status-value (cond ((and (.ref project 'complete?) (pair? unresolved-edge-values)) 'invalid-endpoints)
                             ((not (.ref project 'complete?)) 'unknown)
                             ((or (null? sources) (null? targets)) 'inventory-review-required)
                             ((or (pair? forward) (pair? backward)) 'trace-gaps)
                             (else 'trace-evidence-present))))
    (.o kind: 'sdlc.trace-review status: status-value
        relation: (.ref rule 'identity) subject: (.ref project 'subject)
        revision: (.ref project 'revision) scope: (.ref project 'scope)
        missing-forward: forward missing-backward: backward
        invalid-edges: (if (.ref project 'complete?)
                        (map (lambda (e) (.ref e 'identity)) unresolved-edge-values) '())
        unresolved-edges: (if (.ref project 'complete?) '()
                           (map (lambda (e) (.ref e 'identity)) unresolved-edge-values))
        witnesses: (map (lambda (e) (.ref e 'identity)) valid-edges)
        excluded-nodes: (- (length nodes) (length current-nodes))
        excluded-edges: (- (length edges) (length selected))
        compliance: 'not-evaluated runtime-executed?: #f)))
