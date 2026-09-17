;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/modules/governance/funs
                 poo-flow-governance-contribution)
        :poo-flow/lambda-aitia/modules/ADR/types
        :poo-flow/lambda-aitia/modules/ADR/objects
        (only-in :poo-flow/lambda-aitia/modules/assurance/objects
                 assurance-decision)
        (only-in :poo-flow/lambda-aitia/modules/assurance/funs
                 assurance-canonical-digest))

(export ADR-contribution ADR-module
        ADR-status-transition? ADR-transition ADR-supersede
        ADR-canonical ADR->assurance-decision)

(def (ADR-contribution profile)
  (unless (ADR-profile? profile) (error "invalid ADR profile"))
  (poo-flow-governance-contribution
   profile '(knowledge-governance) '()))

(def ADR-module (ADR-contribution ADRProfile))

(def (ADR-status-transition? current-status next-status)
  (case current-status
    ((proposed) (if (memq next-status '(accepted rejected)) #t #f))
    ((accepted) (if (memq next-status '(deprecated superseded)) #t #f))
    ((deprecated) (eq? next-status 'superseded))
    (else #f)))

(def (copy-record record status-value date-value revision-value links-value)
  (ADR-record
   (.ref record 'identity) (.ref record 'title) status-value date-value
   revision-value (.ref record 'context) (.ref record 'decision)
   (.ref record 'decision-drivers) (.ref record 'considered-options)
   (.ref record 'consequences) (.ref record 'confirmation)
   (.ref record 'decision-makers) (.ref record 'consulted)
   (.ref record 'informed) links-value))

;;; A transition always creates another value and revision.  It never rewrites
;;; the predecessor object or treats Git history as implicit semantic state.
(def (ADR-transition record next-status next-date next-revision next-links)
  (unless (ADR-record-valid? record) (error "invalid ADR predecessor"))
  (unless (ADR-status-transition? (.ref record 'status) next-status)
    (error "invalid ADR status transition" (.ref record 'status) next-status))
  (when (string=? (.ref record 'revision) next-revision)
    (error "ADR transition requires a new revision" next-revision))
  (copy-record record next-status next-date next-revision next-links))

(def (add-link record relation target)
  (let ((candidate (ADR-link relation target)))
    (if (member (cons relation target)
                (map (lambda (link)
                       (cons (.ref link 'relation) (.ref link 'target)))
                     (.ref record 'links)))
      (.ref record 'links)
      (append (.ref record 'links) (list candidate)))))

;;; Supersession is one operation producing both immutable sides of the link.
;;; The replacement must already be an accepted ADR; acceptance itself remains
;;; a distinct review decision.
(def (ADR-supersede predecessor replacement date-value
                    predecessor-revision replacement-revision)
  (unless (and (ADR-record-valid? predecessor)
               (ADR-record-valid? replacement)
               (eq? (.ref replacement 'status) 'accepted))
    (error "ADR supersession requires valid predecessor and accepted replacement"))
  (when (string=? (.ref predecessor 'identity) (.ref replacement 'identity))
    (error "ADR cannot supersede itself" (.ref predecessor 'identity)))
  (when (string=? (.ref replacement 'revision) replacement-revision)
    (error "ADR supersession requires a new replacement revision"
           replacement-revision))
  (values
   (ADR-transition
    predecessor 'superseded date-value predecessor-revision
    (add-link predecessor 'superseded-by (.ref replacement 'identity)))
   (copy-record
    replacement 'accepted date-value replacement-revision
    (add-link replacement 'supersedes (.ref predecessor 'identity)))))

(def (option-canonical option)
  (list (.ref option 'identity) (.ref option 'title)
        (.ref option 'description) (.ref option 'disposition)
        (.ref option 'pros) (.ref option 'cons)))
(def (consequence-canonical consequence)
  (list (.ref consequence 'sentiment) (.ref consequence 'statement)))
(def (link-canonical link)
  (list (.ref link 'relation) (.ref link 'target)))

(def (ADR-canonical record)
  (unless (ADR-record-valid? record) (error "invalid ADR record"))
  (list 'lambda-aitia.ADR-record
        (.ref record 'identity) (.ref record 'title) (.ref record 'status)
        (.ref record 'date) (.ref record 'revision) (.ref record 'context)
        (.ref record 'decision) (.ref record 'decision-drivers)
        (map option-canonical (.ref record 'considered-options))
        (map consequence-canonical (.ref record 'consequences))
        (.ref record 'confirmation) (.ref record 'decision-makers)
        (.ref record 'consulted) (.ref record 'informed)
        (map link-canonical (.ref record 'links))))

;;; An ADR is rationale and choice history.  Its assurance projection is never
;;; supported solely because the ADR is accepted, and therefore grants no
;;; effect authority.  Evidence admission may support a separate decision.
(def (ADR->assurance-decision record)
  (let ((state
         (case (.ref record 'status)
           ((deprecated superseded) 'stale)
           ((rejected) 'not-applicable)
           (else 'unknown))))
    (assurance-decision
     (string-append "ADR/" (.ref record 'identity))
     (.ref record 'revision)
     state
     (assurance-canonical-digest (ADR-canonical record)))))
