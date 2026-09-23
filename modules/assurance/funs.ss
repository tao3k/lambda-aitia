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
                 poo-flow-graph-loop-analysis-receipt
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
        assurance-invalidation-graph
        assurance-invalidate assurance-derive-replacement-requirements
        assurance-declare-replacement-obligation
        assurance-plan-verification assurance-explain-verifier-choices
        assurance-derive-composition-requirements)

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

;;; This derives the need for fresh declarations from the old snapshot's
;;; invalidation closure. It deliberately does not make a new obligation: a
;;; revised claim or policy may require a different question or evidence kind,
;;; and inserting an obligation would change the target snapshot context.
(def (replacement-requirement-blocker source-obligation source target
                                      change-unresolved)
  (let ((source-claim
         (node-by-identity (.ref source 'nodes)
                           (.ref source-obligation 'claim)))
        (target-claim
         (node-by-identity (.ref target 'nodes)
                           (.ref source-obligation 'claim))))
    (cond
     ((pair? (.ref source 'conflicts)) 'source-conflicted)
     ((pair? (.ref source 'unresolved)) 'source-unresolved)
     ((pair? change-unresolved) 'change-unresolved)
     ((or (not (equal? (.ref source-obligation 'snapshot)
                       (.ref source 'identity)))
          (not (equal? (.ref source-obligation 'snapshot-revision)
                       (.ref source 'revision)))
          (not (equal? (.ref source-obligation 'snapshot-context-digest)
                       (.ref source 'context-digest))))
      'stale-source)
     ((equal? (.ref source 'digest) (.ref target 'digest)) 'target-unchanged)
     ((pair? (.ref target 'conflicts)) 'target-conflicted)
     ((pair? (.ref target 'unresolved)) 'target-unresolved)
     ((not (equal? (.ref source 'identity) (.ref target 'identity)))
      'target-identity-changed)
     ((not (equal? (.ref source 'graph-identity)
                   (.ref target 'graph-identity)))
      'graph-changed)
     ((or (not (equal? (.ref source 'policy-identity)
                       (.ref target 'policy-identity)))
          (not (equal? (.ref source 'policy-revision)
                       (.ref target 'policy-revision))))
      'policy-changed)
     ((not (assurance-claim? target-claim)) 'claim-missing)
     ((or (not (assurance-claim? source-claim))
          (not (equal? (assurance-node-canonical source-claim)
                       (assurance-node-canonical target-claim))))
      'claim-changed)
     (else #f))))

(def (assurance-derive-replacement-requirements derivation-identity source target
                                                changed-identities)
  (unless (and (assurance-text? derivation-identity)
               (assurance-snapshot? source)
               (assurance-snapshot? target))
    (error "invalid replacement derivation input"))
  (let* ((invalidation
          (assurance-invalidate
           (string-append derivation-identity "/invalidation")
           source changed-identities))
         (changed-values
          (assurance-invalidation-receipt-ref invalidation 'changed))
         (change-witnesses
          (assurance-invalidation-receipt-ref invalidation 'witnesses))
         (change-unresolved
          (assurance-invalidation-receipt-ref invalidation 'unresolved))
         (obligation-ids
          (assurance-invalidation-receipt-ref
           invalidation 'required-obligations))
         (derived-requirements
          (map
           (lambda (obligation-id)
             (let ((obligation
                    (node-by-identity (.ref source 'nodes) obligation-id)))
               (poo-flow-check-model
                AssuranceReplacementRequirement
                (.o (:: @ (poo-flow-model-prototype
                           AssuranceReplacementRequirement))
                    source-obligation: obligation-id
                    source-revision: (.ref obligation 'revision)
                    claim: (.ref obligation 'claim)
                    subject: (.ref obligation 'subject)
                    evidence-kind: (.ref obligation 'evidence-kind)
                    capability: (.ref obligation 'capability)
                    scope: (.ref obligation 'scope)
                    blocker:
                    (replacement-requirement-blocker
                     obligation source target change-unresolved)))))
           obligation-ids))
         (derivation-digest
          (assurance-canonical-digest
           (list "lambda-aitia.replacement-requirements"
                 derivation-identity
                 (.ref source 'digest) (.ref target 'digest)
                 changed-values change-witnesses change-unresolved
                 (map (lambda (requirement)
                        (list (.ref requirement 'source-obligation)
                              (.ref requirement 'source-revision)
                              (.ref requirement 'claim)
                              (.ref requirement 'subject)
                              (.ref requirement 'evidence-kind)
                              (.ref requirement 'capability)
                              (.ref requirement 'scope)
                              (.ref requirement 'blocker)))
                      derived-requirements)))))
    (poo-flow-check-model
     AssuranceReplacementDerivation
     (.o (:: @ (poo-flow-model-prototype AssuranceReplacementDerivation))
         schema: "lambda-aitia.replacement-requirements"
         identity: derivation-identity
         source-snapshot-digest: (.ref source 'digest)
         target-snapshot-digest: (.ref target 'digest)
         changed: changed-values
         witnesses: change-witnesses
         unresolved: change-unresolved
         requirements: derived-requirements digest: derivation-digest
         verifier-executed?: #f release-authorized?: #f))))

;;; The new obligation, revised claim and supports edge must already be present
;;; in the caller's draft.  Only its snapshot binding is filled here.  The
;;; derivation is replayed against exact source/draft digests so a forged or
;;; unrelated receipt cannot be used to promote a candidate.
(def (snapshot-canonical? snapshot)
  (let ((rebuilt
         (assurance-snapshot
          (.ref snapshot 'identity) (.ref snapshot 'revision)
          (.ref snapshot 'graph-identity)
          (.ref snapshot 'source-revisions) (.ref snapshot 'claim-revisions)
          (.ref snapshot 'fact-cut) (.ref snapshot 'policy-identity)
          (.ref snapshot 'policy-revision)
          (.ref snapshot 'nodes) (.ref snapshot 'relations)
          evidence-identities: (.ref snapshot 'evidence-identities)
          unresolved: (.ref snapshot 'unresolved))))
    (and (equal? (.ref rebuilt 'digest) (.ref snapshot 'digest))
         (equal? (.ref rebuilt 'context-digest)
                 (.ref snapshot 'context-digest)))))

(def (replacement-declaration-blocker derivation source draft
                                      source-id candidate-id)
  (let* ((expected
          (assurance-derive-replacement-requirements
           (.ref derivation 'identity) source draft (.ref derivation 'changed)))
         (requirement
          (find (lambda (item)
                  (equal? (.ref item 'source-obligation) source-id))
                (.ref derivation 'requirements)))
         (candidate (node-by-identity (.ref draft 'nodes) candidate-id))
         (claim (and (assurance-obligation? candidate)
                     (node-by-identity (.ref draft 'nodes)
                                       (.ref candidate 'claim))))
         (support-links
          (filter (lambda (relation)
                    (and (eq? (.ref relation 'relation) 'supports)
                         (equal? (.ref relation 'source) candidate-id)
                         (assurance-obligation? candidate)
                         (equal? (.ref relation 'target)
                                 (.ref candidate 'claim))))
                  (.ref draft 'relations))))
    (cond
     ((or (not (snapshot-canonical? source))
          (not (snapshot-canonical? draft))
          (not (equal? (.ref derivation 'source-snapshot-digest)
                       (.ref source 'digest)))
          (not (equal? (.ref derivation 'target-snapshot-digest)
                       (.ref draft 'digest)))
          (not (equal? (.ref derivation 'digest) (.ref expected 'digest))))
      'derivation-mismatch)
     ((not requirement) 'source-requirement-missing)
     ((not (memq (.ref requirement 'blocker) '(#f claim-changed)))
      'source-requirement-blocked)
     ((or (pair? (.ref draft 'unresolved)) (pair? (.ref draft 'conflicts)))
      'target-frontier)
     ((not (assurance-obligation? candidate)) 'candidate-missing)
     ((node-by-identity (.ref source 'nodes) candidate-id)
      'candidate-not-fresh)
     ((or (not (equal? (.ref candidate 'snapshot) (.ref draft 'identity)))
          (.ref candidate 'snapshot-revision)
          (.ref candidate 'snapshot-context-digest))
      'candidate-not-unbound)
     ((not (eq? (.ref candidate 'state) 'unknown)) 'candidate-not-unknown)
     ((not (equal? (.ref candidate 'claim) (.ref requirement 'claim)))
      'candidate-claim-mismatch)
     ((not (assurance-claim? claim)) 'candidate-claim-mismatch)
     ((not (equal? (.ref candidate 'subject) (.ref claim 'subject)))
      'candidate-subject-mismatch)
     ((not (equal? (.ref candidate 'scope) (.ref claim 'scope)))
      'candidate-scope-mismatch)
     ((not (member candidate-id (.ref claim 'support-requirements)))
      'claim-not-declared)
     ((null? support-links) 'support-link-missing)
     ((not (find (lambda (relation)
                   (memq (.ref relation 'modality)
                         '(observed declared derived)))
                 support-links))
      'support-link-hypothetical)
     (else #f))))

(def (assurance-declare-replacement-obligation declaration-identity source draft derivation
                                               source-id candidate-id)
  (unless (and (assurance-text? declaration-identity)
               (assurance-text? source-id) (assurance-text? candidate-id)
               (assurance-snapshot? source) (assurance-snapshot? draft)
               (assurance-replacement-derivation? derivation))
    (error "invalid replacement declaration input"))
  (let* ((declaration-blocker
          (replacement-declaration-blocker
           derivation source draft source-id candidate-id))
         (final-snapshot
          (and (not declaration-blocker)
               (let* ((candidate
                       (node-by-identity (.ref draft 'nodes) candidate-id))
                      (bound
                       (assurance-bind-obligation-to-snapshot candidate draft)))
                 (assurance-snapshot
                  (.ref draft 'identity) (.ref draft 'revision)
                  (.ref draft 'graph-identity)
                  (.ref draft 'source-revisions) (.ref draft 'claim-revisions)
                  (.ref draft 'fact-cut) (.ref draft 'policy-identity)
                  (.ref draft 'policy-revision)
                  (map (lambda (node)
                         (if (equal? (.ref node 'identity) candidate-id)
                           bound node))
                       (.ref draft 'nodes))
                  (.ref draft 'relations)
                  evidence-identities: (.ref draft 'evidence-identities)
                  unresolved: (.ref draft 'unresolved)))))
         (final-digest (and final-snapshot (.ref final-snapshot 'digest)))
         (receipt-digest
          (assurance-canonical-digest
           (list "lambda-aitia.replacement-declaration" declaration-identity
                 (.ref derivation 'digest) (.ref source 'digest)
                 (.ref draft 'digest) final-digest
                 source-id candidate-id declaration-blocker)))
         (receipt
          (poo-flow-check-model
           AssuranceReplacementDeclarationReceipt
           (.o (:: @ (poo-flow-model-prototype
                     AssuranceReplacementDeclarationReceipt))
               schema: "lambda-aitia.replacement-declaration"
               identity: declaration-identity
               derivation-digest: (.ref derivation 'digest)
               source-snapshot-digest: (.ref source 'digest)
               draft-snapshot-digest: (.ref draft 'digest)
               final-snapshot-digest: final-digest
               source-obligation: source-id target-obligation: candidate-id
               blocker: declaration-blocker digest: receipt-digest
               verifier-executed?: #f release-authorized?: #f))))
    (when (and final-snapshot
               (not (equal? (.ref final-snapshot 'context-digest)
                            (.ref draft 'context-digest))))
      (error "replacement binding changed snapshot context"))
    (values final-snapshot receipt)))

;;; A structural 'composes edge declares a composite claim's components.
;;; Only an independent, explicitly linked and current obligation can answer
;;; its composition question; this receipt never discharges that obligation.
(def (composition-component-ids snapshot composition-id)
  (ordered-unique-text
   (map (lambda (relation) (.ref relation 'target))
        (filter (lambda (relation)
                  (and (eq? (.ref relation 'relation) 'composes)
                       (equal? (.ref relation 'source) composition-id)))
                (.ref snapshot 'relations)))))

(def (composition-direct-obligations snapshot composition-id claim-node)
  (if (not (assurance-claim? claim-node))
    '()
    (ordered-unique-text
     (map
      (lambda (obligation) (.ref obligation 'identity))
      (filter
       (lambda (obligation)
         (and (assurance-obligation? obligation)
              (equal? (.ref obligation 'claim) composition-id)
              (equal? (.ref obligation 'subject)
                      (.ref claim-node 'subject))
              (equal? (.ref obligation 'scope)
                      (.ref claim-node 'scope))
              (member (.ref obligation 'identity)
                      (.ref claim-node 'support-requirements))
              (find
               (lambda (relation)
                 (and (eq? (.ref relation 'relation) 'supports)
                      (eq? (.ref relation 'plane) 'assurance)
                      (memq (.ref relation 'modality)
                            '(declared observed derived))
                      (equal? (.ref relation 'source)
                              (.ref obligation 'identity))
                      (equal? (.ref relation 'target) composition-id)))
               (.ref snapshot 'relations))))
       (.ref snapshot 'nodes))))))

(def (composition-current-obligation? snapshot obligation-id)
  (let ((obligation (node-by-identity (.ref snapshot 'nodes) obligation-id)))
    (and (assurance-obligation? obligation)
         (equal? (.ref obligation 'snapshot) (.ref snapshot 'identity))
         (equal? (.ref obligation 'snapshot-revision)
                 (.ref snapshot 'revision))
         (equal? (.ref obligation 'snapshot-context-digest)
                 (.ref snapshot 'context-digest)))))

(def (composition-requirement-blocker snapshot composition-claim
                                      component-ids direct-ids current-ids)
  (cond
   ((pair? (.ref snapshot 'conflicts)) 'conflicted-snapshot)
   ((pair? (.ref snapshot 'unresolved)) 'unresolved-frontier)
   ((not (assurance-claim? composition-claim))
    'invalid-composition-claim)
   ((< (length component-ids) 2) 'insufficient-components)
   ((find (lambda (component-id)
            (not (assurance-claim?
                  (node-by-identity (.ref snapshot 'nodes) component-id))))
          component-ids)
    'invalid-component-claim)
   ((pair? current-ids) #f)
   ((pair? direct-ids) 'stale-direct-obligation)
   (else 'missing-direct-obligation)))

(def (assurance-derive-composition-requirements derivation-identity snapshot)
  (unless (and (assurance-text? derivation-identity)
               (assurance-snapshot? snapshot))
    (error "invalid composition derivation input"))
  (let* ((composition-ids
          (ordered-unique-text
           (map (lambda (relation) (.ref relation 'source))
                (filter
                 (lambda (relation)
                   (eq? (.ref relation 'relation) 'composes))
                 (.ref snapshot 'relations)))))
         (derived-requirements
          (map
           (lambda (composition-id)
             (let* ((composition-claim
                     (node-by-identity (.ref snapshot 'nodes)
                                       composition-id))
                    (component-ids
                     (composition-component-ids snapshot composition-id))
                    (direct-ids
                     (composition-direct-obligations
                      snapshot composition-id composition-claim))
                    (current-ids
                     (filter
                      (lambda (obligation-id)
                        (composition-current-obligation?
                         snapshot obligation-id))
                      direct-ids))
                    (blocker-value
                     (composition-requirement-blocker
                      snapshot composition-claim component-ids
                      direct-ids current-ids)))
               (poo-flow-check-model
                AssuranceCompositionRequirement
                (.o (:: @ (poo-flow-model-prototype
                           AssuranceCompositionRequirement))
                    composition-claim: composition-id
                    component-claims: component-ids
                    direct-obligations: direct-ids
                    current-obligations: current-ids
                    blocker: blocker-value))))
           composition-ids))
         (derivation-digest
          (assurance-canonical-digest
           (list "lambda-aitia.composition-requirements"
                 derivation-identity (.ref snapshot 'digest)
                 (map (lambda (requirement)
                        (list (.ref requirement 'composition-claim)
                              (.ref requirement 'component-claims)
                              (.ref requirement 'direct-obligations)
                              (.ref requirement 'current-obligations)
                              (.ref requirement 'blocker)))
                      derived-requirements)))))
    (poo-flow-check-model
     AssuranceCompositionDerivation
     (.o (:: @ (poo-flow-model-prototype AssuranceCompositionDerivation))
         schema: "lambda-aitia.composition-requirements"
         identity: derivation-identity
         snapshot-digest: (.ref snapshot 'digest)
         requirements: derived-requirements
         digest: derivation-digest
         verifier-executed?: #f release-authorized?: #f))))

;;; Phase 3 selection boundary. This plan names only obligations already bound
;;; to the supplied snapshot. Deriving replacement revisions and invoking
;;; verifiers belong to later phases; neither can be inferred from a change.
(def (verification-base-blocker obligation snapshot capabilities
                                unresolved conflicts cyclic-ids
                                prerequisites planned-ids)
  (cond
   ((pair? conflicts) 'conflicted-snapshot)
   ((pair? unresolved) 'unresolved-frontier)
   ((member (.ref obligation 'identity) cyclic-ids) 'dependency-cycle)
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
             (cyclic-components
              (.ref (poo-flow-graph-loop-analysis-receipt dependency-graph)
                    'cyclic-components))
             (cyclic-ids (concatenate cyclic-components))
             (cycle-blocked
              (poo-flow-graph-reachable-ids dependency-graph cyclic-ids))
             (base-blockers
              (map
               (lambda (obligation-id)
                 (cons
                  obligation-id
                  (verification-base-blocker
                   (node-by-identity (.ref snapshot 'nodes) obligation-id)
                   snapshot capabilities unresolved conflicts cyclic-ids
                   (cdr (assoc obligation-id prerequisites)) obligation-ids)))
               obligation-ids))
             (blocked-closure
              (poo-flow-graph-reachable-ids
               dependency-graph
               (append cycle-blocked
                       (map car (filter (lambda (entry) (cdr entry))
                                        base-blockers)))))
             (available-ids
              (filter (lambda (id) (not (member id blocked-closure)))
                      obligation-ids))
             (available-order
              (let-values (((available-graph _)
                            (assurance-verification-dependency-graph
                             snapshot available-ids)))
                (poo-flow-graph-topological-order available-graph)))
             (blocked-order
              (filter (lambda (id) (member id blocked-closure))
                      (if (null? cycle-path)
                        (poo-flow-graph-topological-order dependency-graph)
                        obligation-ids)))
             (ordered-ids (append available-order blocked-order))
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
                 cycle-path cyclic-components
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
          (plan-cyclic-components cyclic-components)
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
           cyclic-components: plan-cyclic-components
           witnesses: plan-witnesses
           requests: plan-requests
           unresolved: plan-unresolved conflicts: plan-conflicts
           verifier-executed?: #f release-authorized?: #f
           runtime-executed?: #f)))))))

;;; Candidate selection is a pure explanation over explicit declarations.
;;; It does not establish that an adapter is installed, runnable or trusted.
(def (verifier-candidate-matches? candidate request)
  (and (memq (.ref request 'evidence-kind)
             (.ref candidate 'evidence-kinds))
       (eq? (.ref request 'capability) (.ref candidate 'capability))))

(def (verifier-choice-reason candidate request selected-candidate)
  (cond
   ((not (.ref request 'selected?)) 'request-blocked)
   ((not (memq (.ref request 'evidence-kind)
               (.ref candidate 'evidence-kinds)))
    'evidence-kind-unsupported)
   ((not (eq? (.ref request 'capability)
              (.ref candidate 'capability)))
    'capability-mismatch)
   ((and selected-candidate
         (equal? (.ref candidate 'identity)
                 (.ref selected-candidate 'identity)))
    'chosen)
   (else 'lower-priority)))

(def (assurance-explain-verifier-choices explanation-identity plan candidates)
  (unless (and (assurance-text? explanation-identity)
               (assurance-verification-plan? plan)
               (list? candidates)
               (every assurance-verifier-candidate? candidates))
    (error "invalid verifier choice input"))
  (let* ((ordered-candidates
         (list-sort
           (lambda (left right)
             (or (< (.ref left 'priority) (.ref right 'priority))
                 (and (= (.ref left 'priority) (.ref right 'priority))
                      (string<? (.ref left 'identity)
                                (.ref right 'identity)))))
           candidates))
         (candidate-ids (map (lambda (candidate)
                               (.ref candidate 'identity))
                             ordered-candidates)))
    (unless (= (length candidate-ids)
               (length (delete-duplicates/hash candidate-ids)))
      (error "duplicate verifier candidate identity" candidate-ids))
    (let* ((requests (.ref plan 'requests))
           (candidate-choices
            (concatenate
             (map
              (lambda (request)
                (let ((selected-candidate
                       (and (.ref request 'selected?)
                            (find (lambda (candidate)
                                    (verifier-candidate-matches?
                                     candidate request))
                                  ordered-candidates))))
                  (map
                   (lambda (candidate)
                     (let ((choice-reason
                            (verifier-choice-reason
                             candidate request selected-candidate)))
                       (poo-flow-check-model
                        AssuranceVerifierChoice
                        (.o (:: @ (poo-flow-model-prototype
                                   AssuranceVerifierChoice))
                            obligation-identity:
                            (.ref request 'obligation-identity)
                            candidate-identity: (.ref candidate 'identity)
                            selected?: (eq? choice-reason 'chosen)
                            reason: choice-reason))))
                   ordered-candidates)))
              requests)))
           (unassigned-ids
            (map
             (lambda (request) (.ref request 'obligation-identity))
             (filter
              (lambda (request)
                (and (.ref request 'selected?)
                     (not (find
                           (lambda (candidate)
                             (verifier-candidate-matches?
                              candidate request))
                           ordered-candidates))))
              requests)))
           (explanation-digest
            (assurance-canonical-digest
             (list "lambda-aitia.verifier-choices"
                   explanation-identity (.ref plan 'digest)
                   (map (lambda (candidate)
                          (list (.ref candidate 'identity)
                                (.ref candidate 'revision)
                                (.ref candidate 'priority)
                                (.ref candidate 'evidence-kinds)
                                (.ref candidate 'capability)))
                        ordered-candidates)
                   (map (lambda (choice)
                          (list (.ref choice 'obligation-identity)
                                (.ref choice 'candidate-identity)
                                (.ref choice 'selected?)
                                (.ref choice 'reason)))
                        candidate-choices)
                   unassigned-ids))))
      (poo-flow-check-model
       AssuranceVerifierChoiceReceipt
       (.o (:: @ (poo-flow-model-prototype AssuranceVerifierChoiceReceipt))
           schema: "lambda-aitia.verifier-choices"
           identity: explanation-identity
           plan-digest: (.ref plan 'digest)
           candidates: ordered-candidates
           choices: candidate-choices
           unassigned-obligations: unassigned-ids
           digest: explanation-digest
           verifier-executed?: #f release-authorized?: #f)))))
