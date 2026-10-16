;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Project a design guarantee onto existing Assurance Host admission.
;;; This does not issue an admission, interpret a verifier, or authorize effects.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil/core list-sort)
        :std/list/list
        (only-in :poo-flow/lambda-aitia/modules/assurance/interface
                 assurance-claim? assurance-node-canonical
                 assurance-relation? assurance-snapshot-canonical?
                 assurance-verification-subject?
                 assurance-verification-subject-snapshot
                 assurance-host-admission-current?
                 assurance-host-source-current?
                 assurance-host-admitted-support?
                 assurance-host-required-support)
        :poo-flow/lambda-aitia/modules/sdlc/design
        :poo-flow/lambda-aitia/modules/sdlc/implementation)

(export sdlc-design-guarantee-support-review)

(def (ordered-ids values)
  (list-sort string<? values))
(def (node-at snapshot-value identity-value)
  (find (lambda (node)
          (equal? (.ref node 'identity) identity-value))
        (.ref snapshot-value 'nodes)))
(def (same-claim? snapshot-value claim-value)
  (let (current (node-at snapshot-value (.ref claim-value 'identity)))
    (and current (assurance-claim? current)
         (equal? (assurance-node-canonical current)
                 (assurance-node-canonical claim-value))
         (member (cons (.ref claim-value 'identity)
                       (.ref claim-value 'revision))
                 (.ref snapshot-value 'claim-revisions)))))
(def (source-dependency? snapshot-value claim-value source-id)
  (find (lambda (relation)
          (and (eq? (.ref relation 'plane) 'structural)
               (eq? (.ref relation 'relation) 'depends-on)
               (equal? (.ref relation 'source) (.ref claim-value 'identity))
               (equal? (.ref relation 'target) source-id)
               (not (memq (.ref relation 'modality)
                          '(hypothesized counterfactual)))))
        (.ref snapshot-value 'relations)))
(def (input-bound? outcome-value link-value)
  (find (lambda (input)
          (and (equal? (.ref input 'identity) (.ref link-value 'source))
               (equal? (.ref input 'revision)
                       (.ref link-value 'source-revision))
               (equal? (.ref input 'digest)
                       (.ref link-value 'source-digest))))
        (.ref outcome-value 'inputs)))

;;; One Host admission must bind a verifier outcome to at least one source
;;; declared for this guarantee. All claim obligations still need Host support.
;;; The returned value is an inert assessment, never an authority token.
(def (sdlc-design-guarantee-support-review
      host-value contract-value guarantee-value implementation-links
      claim-value subject-value relation-value admission-value admissions)
  (unless (and (sdlc-design-contract? contract-value)
               (sdlc-design-clause? guarantee-value)
               (eq? (.ref guarantee-value 'kind) 'guarantee)
               (list? implementation-links)
               (every sdlc-design-implementation-link? implementation-links)
               (assurance-claim? claim-value)
               (assurance-verification-subject? subject-value)
               (assurance-relation? relation-value)
               (list? admissions))
    (error "invalid design guarantee support review input"))
  (let* ((snapshot-value (.ref subject-value 'snapshot))
         (obligation-value (.ref subject-value 'obligation))
         (outcome-value (.ref subject-value 'outcome))
         (mapping
          (sdlc-design-implementation-review
           contract-value snapshot-value implementation-links))
         (guarantee-current?
          (find (lambda (declared)
                  (and (equal? (.ref declared 'identity)
                               (.ref guarantee-value 'identity))
                       (equal? (.ref declared 'revision)
                               (.ref guarantee-value 'revision))
                       (equal? (.ref declared 'statement)
                               (.ref guarantee-value 'statement))))
                (.ref contract-value 'guarantees)))
         (claim-current-value
          (and (assurance-snapshot-canonical? snapshot-value)
               (same-claim? snapshot-value claim-value)
               (equal? (.ref claim-value 'subject)
                       (.ref contract-value 'identity))
               (equal? (.ref claim-value 'predicate)
                       (.ref guarantee-value 'statement))
               (equal? (ordered-ids (.ref claim-value 'assumptions))
                       (ordered-ids
                        (map (lambda (assumption)
                               (.ref assumption 'identity))
                             (.ref contract-value 'assumptions))))
               (member (.ref obligation-value 'identity)
                       (.ref claim-value 'support-requirements))))
         (source-links
          (filter (lambda (link)
                    (equal? (.ref link 'guarantee)
                            (.ref guarantee-value 'identity)))
                  implementation-links))
         (source-bound?
          (find (lambda (link)
                  (and (source-dependency?
                        snapshot-value claim-value (.ref link 'source))
                       (input-bound? outcome-value link)))
                source-links))
         (source-bytes-bound?
          (find (lambda (link)
                  (and (source-dependency?
                        snapshot-value claim-value (.ref link 'source))
                       (input-bound? outcome-value link)
                       (let (source-value
                             (node-at snapshot-value (.ref link 'source)))
                         (and source-value
                              (assurance-host-source-current?
                               host-value snapshot-value source-value)))))
                source-links))
         (admission-current?
          (and admission-value
               (memq admission-value admissions)
               (assurance-host-admission-current? host-value admission-value)
               (equal? (.ref admission-value 'subject-digest)
                       (assurance-verification-subject-snapshot subject-value))
               (assurance-host-admitted-support?
                host-value relation-value admission-value)))
         (support
          (and (.ref mapping 'mapping-current?) guarantee-current?
               claim-current-value source-bound? admission-current?
               (assurance-host-required-support
                host-value claim-value admissions)))
         (support-current?
          (and support (.ref support 'complete?)
               (equal? (.ref support 'snapshot-digest)
                       (.ref snapshot-value 'digest)))))
    (.o kind: 'sdlc.design-guarantee-support-review
        contract: (.ref contract-value 'identity)
        contract-digest: (sdlc-design-contract-digest contract-value)
        guarantee: (.ref guarantee-value 'identity)
        snapshot-digest: (.ref snapshot-value 'digest)
        mapping-current?: (.ref mapping 'mapping-current?)
        claim-current?: (and guarantee-current? claim-current-value #t)
        source-input-bound?: (and source-bound? #t)
        source-bytes-match?: (and source-bytes-bound? #t)
        host-admission-current?: (and admission-current? #t)
        required-support-current?: (and support-current? #t)
        source-bound-support-current?: (and support-current? #t)
        source-bytes-checked-support-current?:
        (and support-current? source-bytes-bound? #t)
        verifier-independence-established?: #f
        implementation-conforms?: #f
        release-authorized?: #f
        runtime-executed?: #f)))
