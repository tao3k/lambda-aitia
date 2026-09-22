;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Finite source-inventory impact projection, not a graph runtime or approval.
(import (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/sdlc/types
        :std/list/list
        :gerbil/core
        (only-in :poo-flow/src/graph/types
                 poo-flow-graph poo-flow-graph-edge poo-flow-graph-node)
        (only-in :poo-flow/src/modules/temporal-causality/funs
                 poo-flow-structural-impact-analyze))
(export sdlc-change-impact)
(def (same-snapshot? value project)
  (every (lambda (slot) (equal? (.ref value slot) (.ref project slot))) '(subject revision scope)))
(def (unique? values)
  (let ((ids (map (lambda (v) (.ref v 'identity)) values)))
    (= (length ids) (length (delete-duplicates/hash ids)))))
(def (impact-symbol value) (string->symbol value))
(def (impact-text value) (symbol->string value))
(def (sdlc-change-impact project nodes edges changed relations)
  (unless (and (sdlc-project? project)
               (list? nodes) (every sdlc-trace-node? nodes) (unique? nodes)
               (list? edges) (every sdlc-trace-edge? edges) (unique? edges)
               (list? changed) (pair? changed) (every sdlc-text? changed)
               (list? relations) (pair? relations) (every sdlc-text? relations))
    (error "invalid change-impact inventory or selection"))
  (let* ((current (filter (lambda (n) (same-snapshot? n project)) nodes))
         (ids (map (lambda (n) (.ref n 'identity)) current))
         (seeds (list-sort string<? (delete-duplicates/hash changed)))
         (selected-relation-values
          (list-sort string<? (delete-duplicates/hash relations)))
         (selected (list-sort
                    (lambda (a b)
                      (string<? (.ref a 'identity) (.ref b 'identity)))
                    (filter (lambda (e) (and (same-snapshot? e project)
                                             (member (.ref e 'relation)
                                                     selected-relation-values)))
                            edges)))
         (valid (list-sort
                 (lambda (a b) (string<? (.ref a 'identity) (.ref b 'identity)))
                 (filter (lambda (e) (and (member (.ref e 'source) ids)
                                          (member (.ref e 'target) ids)))
                         selected)))
         (unresolved (filter (lambda (e) (not (memq e valid))) selected)))
    (unless (every (lambda (id) (member id ids)) seeds)
      (error "changed object missing from selected snapshot"))
    ;; Traversal, cycle termination and shortest relation trajectories belong
    ;; to POO Flow Graph. Aitia only projects its revision-scoped SDLC facts
    ;; into that mechanism and retains its native trajectory witnesses.
    (let* ((graph
            (poo-flow-graph
             (impact-symbol
              (string-append (.ref project 'subject) "@"
                             (.ref project 'revision) ":"
                             (.ref project 'scope)))
             (map (lambda (node)
                    (poo-flow-graph-node
                     (impact-symbol (.ref node 'identity))))
                  current)
             (map (lambda (edge)
                    (poo-flow-graph-edge
                     (impact-symbol (.ref edge 'source))
                     (impact-symbol (.ref edge 'target))
                     (impact-symbol (.ref edge 'relation))))
                  selected)))
           (structural
            (poo-flow-structural-impact-analyze
             graph (map impact-symbol seeds)
             (map impact-symbol selected-relation-values)
             'dependencies (.ref project 'complete?)))
           (trajectories (.ref structural 'relation-trajectories))
           (affected
            (map impact-text (.ref structural 'affected-node-ids)))
               (status-value (cond ((not (.ref project 'complete?)) 'partial-impact)
                                   ((pair? unresolved) 'invalid-inventory)
                                   (else 'scoped-impact-complete))))
          (.o kind: 'sdlc.change-impact status: status-value
              subject: (.ref project 'subject) revision: (.ref project 'revision)
              scope: (.ref project 'scope) changed-identities: seeds
              affected-identities: affected witnesses: trajectories
              recheck-verifications:
              (list-sort
               string<?
               (map (lambda (n) (.ref n 'identity))
                    (filter (lambda (n)
                              (and (eq? (.ref n 'category) 'verification)
                                   (member (.ref n 'identity) affected)))
                            current)))
              unresolved-edges:
              (list-sort string<?
                         (map (lambda (e) (.ref e 'identity)) unresolved))
              selected-relations: selected-relation-values
              excluded-edges: (- (length edges) (length selected))
              evidence-action: 'reassessment-required
              release-authorized?: #f runtime-executed?: #f))))
