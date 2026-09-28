;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An inert, snapshot-bound design-to-source declaration. Source currentness
;;; is checked against Assurance; semantic conformance is not inferred.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil/core list-sort)
        :std/list/list
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/lambda-aitia/modules/assurance/interface
                 assurance-artifact? assurance-digest?
                 assurance-snapshot? assurance-snapshot-canonical?)
        :poo-flow/lambda-aitia/modules/sdlc/types
        :poo-flow/lambda-aitia/modules/sdlc/design)

(export SdlcDesignImplementationLink sdlc-design-implementation-link?
        sdlc-design-implementation-link sdlc-design-implementation-review)

(def (text-slot name)
  (poo-clos-direct-slot-definition name type-predicate: sdlc-text?))
(def (digest-slot name)
  (poo-clos-direct-slot-definition name type-predicate: assurance-digest?))

(def SdlcDesignImplementationLink
  (poo-clos-class 'sdlc/design-implementation-link
    direct-slots:
    (list (text-slot 'contract) (text-slot 'contract-revision)
          (digest-slot 'contract-digest)
          (text-slot 'guarantee) (text-slot 'guarantee-revision)
          (text-slot 'source) (text-slot 'source-revision)
          (digest-slot 'source-digest)
          (text-slot 'snapshot) (text-slot 'snapshot-revision)
          (digest-slot 'snapshot-context-digest))))

(def (sdlc-design-implementation-link? value)
  (poo-flow-model? SdlcDesignImplementationLink value))

(def (sdlc-design-implementation-link contract-value guarantee-value
                                      source-value snapshot-value)
  (unless (and (sdlc-design-contract? contract-value)
               (sdlc-design-clause? guarantee-value)
               (eq? (.ref guarantee-value 'kind) 'guarantee)
               (assurance-artifact? source-value)
               (assurance-snapshot-canonical? snapshot-value))
    (error "invalid design implementation link input"))
  (poo-flow-check-model
   SdlcDesignImplementationLink
   (.o (:: @ (poo-flow-model-prototype SdlcDesignImplementationLink))
       contract: (.ref contract-value 'identity)
       contract-revision: (.ref contract-value 'revision)
       contract-digest: (sdlc-design-contract-digest contract-value)
       guarantee: (.ref guarantee-value 'identity)
       guarantee-revision: (.ref guarantee-value 'revision)
       source: (.ref source-value 'identity)
       source-revision: (.ref source-value 'revision)
       source-digest: (.ref source-value 'content-digest)
       snapshot: (.ref snapshot-value 'identity)
       snapshot-revision: (.ref snapshot-value 'revision)
       snapshot-context-digest: (.ref snapshot-value 'context-digest))))

(def (ordered-ids values)
  (list-sort string<? (delete-duplicates/hash values)))
(def (find-id values id)
  (find (lambda (value) (equal? (.ref value 'identity) id)) values))
(def (bound-source snapshot id)
  (let ((binding (assoc id (.ref snapshot 'source-revisions)))
        (node (find-id (.ref snapshot 'nodes) id)))
    (and binding node (assurance-artifact? node)
         (equal? (cdr binding) (.ref node 'revision)) node)))

(def (link-blocker contract snapshot link)
  (let ((guarantee (find-id (.ref contract 'guarantees)
                            (.ref link 'guarantee)))
        (source (bound-source snapshot (.ref link 'source))))
    (cond
     ((or (not (equal? (.ref link 'contract) (.ref contract 'identity)))
          (not (equal? (.ref link 'contract-revision)
                       (.ref contract 'revision)))
          (not (equal? (.ref link 'contract-digest)
                       (sdlc-design-contract-digest contract))))
      'contract-changed)
     ((not guarantee) 'guarantee-undeclared)
     ((not (equal? (.ref link 'guarantee-revision)
                   (.ref guarantee 'revision)))
      'guarantee-revision-changed)
     ((or (not (equal? (.ref link 'snapshot) (.ref snapshot 'identity)))
          (not (equal? (.ref link 'snapshot-revision)
                       (.ref snapshot 'revision)))
          (not (equal? (.ref link 'snapshot-context-digest)
                       (.ref snapshot 'context-digest))))
      'snapshot-changed)
     ((not source) 'source-unbound)
     ((or (not (equal? (.ref link 'source-revision)
                       (.ref source 'revision)))
          (not (equal? (.ref link 'source-digest)
                       (.ref source 'content-digest)))
          (not (eq? (.ref source 'state) 'supported)))
      'source-changed)
     (else #f))))

(def (sdlc-design-implementation-review contract-value snapshot-value links)
  (unless (and (sdlc-design-contract? contract-value)
               (assurance-snapshot? snapshot-value)
               (assurance-snapshot-canonical? snapshot-value)
               (list? links)
               (every sdlc-design-implementation-link? links))
    (error "invalid design implementation review input"))
  (let* ((checks
          (map (lambda (link)
                 (.o guarantee: (.ref link 'guarantee)
                     source: (.ref link 'source)
                     blocker: (link-blocker contract-value snapshot-value link)))
               links))
         (current-guarantees
          (ordered-ids
           (map (lambda (check) (.ref check 'guarantee))
                (filter (lambda (check) (not (.ref check 'blocker))) checks))))
         (unmapped
          (ordered-ids
           (filter (lambda (id) (not (member id current-guarantees)))
                   (map (lambda (guarantee) (.ref guarantee 'identity))
                        (.ref contract-value 'guarantees)))))
         (blocked (filter (lambda (check) (.ref check 'blocker)) checks))
         (frontier? (or (pair? (.ref snapshot-value 'conflicts))
                        (pair? (.ref snapshot-value 'unresolved)))))
    (.o kind: 'sdlc.design-implementation-review
        contract: (.ref contract-value 'identity)
        contract-revision: (.ref contract-value 'revision)
        snapshot: (.ref snapshot-value 'identity)
        snapshot-revision: (.ref snapshot-value 'revision)
        snapshot-digest: (.ref snapshot-value 'digest)
        mapping-current?: (and (null? blocked) (null? unmapped)
                               (not frontier?))
        mapped-guarantees: current-guarantees
        unmapped-guarantees: unmapped
        blocked-links: blocked
        snapshot-frontier?: frontier?
        implementation-conforms?: #f
        evidence-admitted?: #f
        release-authorized?: #f)))
