;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .get .o)
        (only-in :clan/poo/type validate)
        "types.ss")

(export ADR-link ADR-option ADR-consequence ADR-record
        ADR-status-transition? ADR-transition ADR-supersede
        ADR-canonical ADR-assurance-projector)

(def (ADR-link relation target)
  (validate ADRLink
    (.o (:: @ (.get ADRLink proto))
        (relation := relation)
        (target := target))))

(def (ADR-option identity title description disposition pros cons)
  (validate ADROption
    (.o (:: @ (.get ADROption proto))
        (identity := identity)
        (title := title)
        (description := description)
        (disposition := disposition)
        (pros := pros)
        (cons := cons))))

(def (ADR-consequence sentiment statement)
  (validate ADRConsequence
    (.o (:: @ (.get ADRConsequence proto))
        (sentiment := sentiment)
        (statement := statement))))

(def (ADR-record identity title status date revision context decision
                 drivers options consequences confirmation
                 decision-makers consulted informed links)
  (let ((record
         (validate ADRRecord
           (.o (:: @ (.get ADRRecord proto))
               (identity := identity)
               (title := title)
               (status := status)
               (date := date)
               (revision := revision)
               (context := context)
               (decision := decision)
               (decision-drivers := drivers)
               (considered-options := options)
               (consequences := consequences)
               (confirmation := confirmation)
               (decision-makers := decision-makers)
               (consulted := consulted)
               (informed := informed)
               (links := links)))))
    (unless (ADR-record-valid? record)
      (error "invalid ADR decision record" identity status))
    record))

(def (ADR-status-transition? current-status next-status)
  (case current-status
    ((proposed) (if (memq next-status '(accepted rejected)) #t #f))
    ((accepted) (if (memq next-status '(deprecated superseded)) #t #f))
    ((deprecated) (eq? next-status 'superseded))
    (else #f)))

(def (copy-record record status date revision links)
  (ADR-record
   (.get record identity) (.get record title) status date revision
   (.get record context) (.get record decision)
   (.get record decision-drivers) (.get record considered-options)
   (.get record consequences) (.get record confirmation)
   (.get record decision-makers) (.get record consulted)
   (.get record informed) links))

;;; A transition always creates another value and revision.  It never rewrites
;;; the predecessor object or treats Git history as implicit semantic state.
(def (ADR-transition record next-status next-date next-revision next-links)
  (unless (ADR-record-valid? record) (error "invalid ADR predecessor"))
  (unless (ADR-status-transition? (.get record status) next-status)
    (error "invalid ADR status transition" (.get record status) next-status))
  (when (string=? (.get record revision) next-revision)
    (error "ADR transition requires a new revision" next-revision))
  (copy-record record next-status next-date next-revision next-links))

(def (add-link record relation target)
  (let ((candidate (ADR-link relation target))
        (existing (.get record links)))
    (if (member (cons relation target)
                (map (lambda (link)
                       (cons (.get link relation) (.get link target)))
                     existing))
      existing
      (append existing (list candidate)))))

;;; Supersession is one operation producing both immutable sides of the link.
;;; The replacement must already be an accepted ADR; acceptance itself remains
;;; a distinct review decision.
(def (ADR-supersede predecessor replacement date
                    predecessor-revision replacement-revision)
  (unless (and (ADR-record-valid? predecessor)
               (ADR-record-valid? replacement)
               (eq? (.get replacement status) 'accepted))
    (error "ADR supersession requires valid predecessor and accepted replacement"))
  (when (string=? (.get predecessor identity) (.get replacement identity))
    (error "ADR cannot supersede itself" (.get predecessor identity)))
  (when (string=? (.get replacement revision) replacement-revision)
    (error "ADR supersession requires a new replacement revision"
           replacement-revision))
  (values
   (ADR-transition
    predecessor 'superseded date predecessor-revision
    (add-link predecessor 'superseded-by (.get replacement identity)))
   (copy-record
    replacement 'accepted date replacement-revision
    (add-link replacement 'supersedes (.get predecessor identity)))))

(def (option-canonical option)
  (list (.get option identity) (.get option title)
        (.get option description) (.get option disposition)
        (.get option pros) (.get option cons)))
(def (consequence-canonical consequence)
  (list (.get consequence sentiment) (.get consequence statement)))
(def (link-canonical link)
  (list (.get link relation) (.get link target)))

(def (ADR-canonical record)
  (unless (ADR-record-valid? record) (error "invalid ADR record"))
  (list 'lambda-aitia.ADR-record
        (.get record identity) (.get record title) (.get record status)
        (.get record date) (.get record revision) (.get record context)
        (.get record decision) (.get record decision-drivers)
        (map option-canonical (.get record considered-options))
        (map consequence-canonical (.get record consequences))
        (.get record confirmation) (.get record decision-makers)
        (.get record consulted) (.get record informed)
        (map link-canonical (.get record links))))

;;; An ADR is rationale and choice history.  Its assurance projection is never
;;; supported solely because the ADR is accepted, and therefore grants no
;;; effect authority.  Evidence admission may support a separate decision.
(def ((ADR-assurance-projector assurance-decision assurance-canonical-digest) record)
  (let ((state
         (case (.get record status)
           ((deprecated superseded) 'stale)
           ((rejected) 'not-applicable)
           (else 'unknown))))
    (assurance-decision
     (string-append "ADR/" (.get record identity))
     (.get record revision)
     state
     (assurance-canonical-digest (ADR-canonical record))
     subject: (.get record identity)
     snapshot: "unbound"
     policy: "ADR-selection-only"
     authority: "unadmitted"
     outcome: 'unknown)))
