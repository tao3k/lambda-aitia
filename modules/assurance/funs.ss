;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :std/crypto/digest sha256)
        (only-in :gerbil/core list-sort string->utf8)
        :std/list/list
        (only-in :std/encoding/hex hex-encode)
        (only-in :poo-flow/src/graph/algorithms
                 poo-flow-graph-cycle-path
                 poo-flow-graph-reachable-ids
                 poo-flow-graph-topological-order)
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/assurance/types
        (only-in :poo-flow/lambda-aitia/modules/assurance/invalidation-projection
                 assurance-invalidation-analysis assurance-invalidation-graph)
        (only-in :poo-flow/lambda-aitia/modules/assurance/verification-projection
                 assurance-verification-dependency-graph))

(export assurance-node-canonical assurance-relation-canonical
        assurance-canonical-digest assurance-snapshot
        assurance-bind-obligation-to-snapshot
        assurance-support-admissible? assurance-invalidation-graph
        assurance-invalidate assurance-plan-verification)

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
    ((obligation) '(subject claim snapshot snapshot-revision
                    snapshot-context-digest evidence-kind capability scope))
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
;;; The context projection excludes only the obligation's own binding slots.
;;; Every other semantic change, including another obligation or relation,
;;; changes the context digest without creating a self-referential hash.
(def (assurance-node-context-canonical node)
  (if (assurance-obligation? node)
    (list (.ref node 'identity) (.ref node 'kind) (.ref node 'revision)
          (.ref node 'state) (.ref node 'content-digest)
          (map (lambda (name) (list name (.ref node name)))
               '(subject claim snapshot evidence-kind capability scope)))
    (assurance-node-canonical node)))
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
           (context-canonical
            (list 'lambda-aitia.assurance-snapshot-context
                  identity-value revision-value graph-identity-value
                  canonical-source-revisions canonical-claim-revisions
                  fact-cut-value policy-identity-value policy-revision-value
                  canonical-evidence-identities snapshot-state
                  (canonical-objects ordered-nodes
                                     assurance-node-context-canonical)
                  (canonical-objects ordered-relations
                                     assurance-relation-canonical)
                  missing all-conflicts))
           (snapshot-context-digest
            (assurance-canonical-digest context-canonical))
           (canonical
            (list 'lambda-aitia.assurance-snapshot identity-value revision-value
                  graph-identity-value canonical-source-revisions
                  canonical-claim-revisions
                  fact-cut-value policy-identity-value policy-revision-value
                  canonical-evidence-identities
                  snapshot-state snapshot-context-digest
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
           state: snapshot-state context-digest: snapshot-context-digest
           digest: snapshot-digest
           nodes: ordered-nodes relations: ordered-relations
           unresolved: missing conflicts: all-conflicts)))))))))

;;; Binding is explicit: snapshot construction never silently upgrades an old
;;; obligation. The caller must reconstruct the final snapshot with this value;
;;; planning then compares both revision and non-circular context digest.
(def (assurance-bind-obligation-to-snapshot obligation snapshot)
  (unless (and (assurance-obligation? obligation)
               (assurance-snapshot? snapshot)
               (string=? (.ref obligation 'snapshot) (.ref snapshot 'identity))
               (not (.ref obligation 'snapshot-revision))
               (not (.ref obligation 'snapshot-context-digest)))
    (error "obligation cannot bind to this snapshot"))
  (let ((bound-revision (.ref snapshot 'revision))
        (bound-context (.ref snapshot 'context-digest)))
    (poo-flow-check-model
     AssuranceObligation
     (.o (:: @ obligation)
         snapshot-revision: bound-revision
         snapshot-context-digest: bound-context))))

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

;;; Phase 3 selection boundary. This plan names only obligations already bound
;;; to the supplied snapshot. Deriving replacement revisions and invoking
;;; verifiers belong to later phases; neither can be inferred from a change.
(def (verification-base-blocker obligation snapshot capabilities
                                unresolved conflicts cycle-path
                                prerequisites planned-ids)
  (cond
   ((pair? conflicts) 'conflicted-snapshot)
   ((pair? unresolved) 'unresolved-frontier)
   ((pair? cycle-path) 'dependency-cycle)
   ((or (not (string=? (.ref obligation 'snapshot)
                       (.ref snapshot 'identity)))
        (not (equal? (.ref obligation 'snapshot-revision)
                     (.ref snapshot 'revision)))
        (not (equal? (.ref obligation 'snapshot-context-digest)
                     (.ref snapshot 'context-digest))))
    'stale-obligation)
   ((not (memq (.ref obligation 'capability) capabilities))
    'capability-unavailable)
   ((find (lambda (id) (not (member id planned-ids))) prerequisites)
    'dependency-unplanned)
   (else #f)))

(def (assurance-plan-verification identity snapshot changed-identities policy)
  (unless (and (assurance-text? identity)
               (assurance-snapshot? snapshot)
               (assurance-verification-policy? policy))
    (error "invalid assurance verification planning input"))
  (unless (and (string=? (.ref policy 'identity)
                          (.ref snapshot 'policy-identity))
               (string=? (.ref policy 'revision)
                          (.ref snapshot 'policy-revision)))
    (error "verification policy does not match the snapshot"))
  (let* ((invalidation
          (assurance-invalidate
           (string-append identity "/invalidation")
           snapshot changed-identities))
         (obligation-ids
          (assurance-invalidation-receipt-ref
           invalidation 'required-obligations))
         (changed
          (assurance-invalidation-receipt-ref invalidation 'changed))
         (impacted
          (assurance-invalidation-receipt-ref invalidation 'impacted))
         (blocked-effects
          (assurance-invalidation-receipt-ref invalidation 'blocked-effects))
         (witnesses
          (assurance-invalidation-receipt-ref invalidation 'witnesses))
         (unresolved
          (assurance-invalidation-receipt-ref invalidation 'unresolved))
         (conflicts (.ref snapshot 'conflicts))
         (capabilities (.ref policy 'capabilities)))
    (let-values (((dependency-graph prerequisites)
                  (assurance-verification-dependency-graph
                   snapshot obligation-ids)))
      (let* ((cycle-path
              (or (poo-flow-graph-cycle-path dependency-graph) '()))
             (ordered-ids
              (if (null? cycle-path)
                (poo-flow-graph-topological-order dependency-graph)
                obligation-ids))
             (base-blockers
              (map
               (lambda (obligation-id)
                 (cons
                  obligation-id
                  (verification-base-blocker
                   (node-by-identity (.ref snapshot 'nodes) obligation-id)
                   snapshot capabilities unresolved conflicts cycle-path
                   (cdr (assoc obligation-id prerequisites)) obligation-ids)))
               ordered-ids))
             (blocked-closure
              (poo-flow-graph-reachable-ids
               dependency-graph
               (map car (filter (lambda (entry) (cdr entry))
                                base-blockers))))
             (requests
              (map
               (lambda (obligation-id)
                 (let* ((obligation
                         (node-by-identity (.ref snapshot 'nodes)
                                           obligation-id))
                        (base-reason (cdr (assoc obligation-id base-blockers)))
                        (request-reason
                         (or base-reason
                             (and (member obligation-id blocked-closure)
                                  'dependency-blocked)))
                        (request-id obligation-id)
                        (request-dependencies
                         (cdr (assoc obligation-id prerequisites))))
                   (poo-flow-check-model
                    AssuranceVerificationRequest
                    (.o (:: @ (poo-flow-model-prototype
                               AssuranceVerificationRequest))
                        obligation-identity: request-id
                        subject: (.ref obligation 'subject)
                        claim: (.ref obligation 'claim)
                        snapshot-digest: (.ref snapshot 'digest)
                        evidence-kind: (.ref obligation 'evidence-kind)
                        capability: (.ref obligation 'capability)
                        dependencies: request-dependencies
                        selected?: (not request-reason)
                        blocker: request-reason))))
               ordered-ids))
         (blocked
          (map (lambda (request) (.ref request 'obligation-identity))
               (filter (lambda (request) (not (.ref request 'selected?)))
                       requests)))
         (selected
          (map (lambda (request) (.ref request 'obligation-identity))
               (filter (lambda (request) (.ref request 'selected?))
                       requests)))
         (request-projection
          (map (lambda (request)
                 (list (.ref request 'obligation-identity)
                       (.ref request 'subject) (.ref request 'claim)
                       (.ref request 'evidence-kind)
                       (.ref request 'capability)
                       (.ref request 'dependencies)
                       (.ref request 'selected?) (.ref request 'blocker)))
               requests))
         (digest
          (assurance-canonical-digest
           (list "lambda-aitia.planning-result" identity
                 (.ref snapshot 'digest)
                 (.ref policy 'identity) (.ref policy 'revision)
                 (.ref policy 'capabilities)
                 changed impacted blocked-effects witnesses
                 cycle-path
                 selected blocked request-projection
                 unresolved conflicts))))
    (let ((plan-identity identity)
          (plan-digest digest)
          (plan-selected selected)
          (plan-blocked blocked)
          (plan-changed changed)
          (plan-impacted impacted)
          (plan-blocked-effects blocked-effects)
          (plan-cycle-path cycle-path)
          (plan-witnesses witnesses)
          (plan-requests requests)
          (plan-unresolved unresolved)
          (plan-conflicts conflicts))
      (poo-flow-check-model
       AssuranceVerificationPlan
       (.o (:: @ (poo-flow-model-prototype AssuranceVerificationPlan))
           schema: "lambda-aitia.planning-result"
           identity: plan-identity snapshot-digest: (.ref snapshot 'digest)
           policy-identity: (.ref policy 'identity)
           policy-revision: (.ref policy 'revision)
           digest: plan-digest
           selected-obligations: plan-selected
           blocked-obligations: plan-blocked
           changed: plan-changed impacted: plan-impacted
           blocked-effects: plan-blocked-effects
           cycle-path: plan-cycle-path
           witnesses: plan-witnesses
           requests: plan-requests
           unresolved: plan-unresolved conflicts: plan-conflicts
           verifier-executed?: #f release-authorized?: #f
           runtime-executed?: #f)))))))
