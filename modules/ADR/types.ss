;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot?)
        :std/list/list
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/src/modules/governance/types
                 poo-flow-governance-profile?))

(export ADR-profile?
        ADR-text? ADR-date? ADR-status? ADR-link-relation?
        ADR-option-disposition? ADR-consequence-sentiment?
        +ADR-statuses+ +ADR-link-relations+
        ADRLink ADROption ADRConsequence ADRRecord
        ADR-link? ADR-option? ADR-consequence? ADR-record?
        ADR-record-valid?)

(def +ADR-statuses+ '(proposed accepted rejected deprecated superseded))
(def +ADR-link-relations+
  '(supersedes superseded-by amends amended-by relates-to
    refines-rfc implements-rfc))

(def (ADR-text? value)
  (and (string? value) (> (string-length value) 0)))
(def (ADR-date? value)
  (and (string? value)
       (= (string-length value) 10)
       (char=? (string-ref value 4) #\-)
       (char=? (string-ref value 7) #\-)
       (every char-numeric?
              (map (lambda (index) (string-ref value index))
                   '(0 1 2 3 5 6 8 9)))))
(def (ADR-status? value) (if (memq value +ADR-statuses+) #t #f))
(def (ADR-link-relation? value)
  (if (memq value +ADR-link-relations+) #t #f))
(def (ADR-option-disposition? value)
  (if (memq value '(undecided chosen rejected)) #t #f))
(def (ADR-consequence-sentiment? value)
  (if (memq value '(positive negative neutral)) #t #f))

(def (text-slot name)
  (poo-clos-direct-slot-definition name type-predicate: ADR-text?))
(def (predicate-slot name predicate)
  (poo-clos-direct-slot-definition name type-predicate: predicate))
(def (ADR-text-list? input-values)
  (and (list? input-values) (every ADR-text? input-values)))

(def ADRLink
  (poo-clos-class 'aitia/ADR-link
    direct-slots:
    (list (predicate-slot 'relation ADR-link-relation?)
          (text-slot 'target))))

(def ADROption
  (poo-clos-class 'aitia/ADR-option
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'title)
          (text-slot 'description)
          (predicate-slot 'disposition ADR-option-disposition?)
          (predicate-slot 'pros ADR-text-list?)
          (predicate-slot 'cons ADR-text-list?))))

(def ADRConsequence
  (poo-clos-class 'aitia/ADR-consequence
    direct-slots:
    (list (predicate-slot 'sentiment ADR-consequence-sentiment?)
          (text-slot 'statement))))

(def (ADR-link-list? input-values)
  (and (list? input-values) (every ADR-link? input-values)))
(def (ADR-option-list? input-values)
  (and (list? input-values) (every ADR-option? input-values)))
(def (ADR-consequence-list? input-values)
  (and (list? input-values) (every ADR-consequence? input-values)))

(def ADRRecord
  (poo-clos-class 'aitia/ADR-record
    direct-slots:
    (list (text-slot 'identity)
          (text-slot 'title)
          (predicate-slot 'status ADR-status?)
          (predicate-slot 'date ADR-date?)
          (text-slot 'revision)
          (text-slot 'context)
          (text-slot 'decision)
          (predicate-slot 'decision-drivers ADR-text-list?)
          (predicate-slot 'considered-options ADR-option-list?)
          (predicate-slot 'consequences ADR-consequence-list?)
          (predicate-slot 'confirmation ADR-text-list?)
          (predicate-slot 'decision-makers ADR-text-list?)
          (predicate-slot 'consulted ADR-text-list?)
          (predicate-slot 'informed ADR-text-list?)
          (predicate-slot 'links ADR-link-list?))))

(def (ADR-link? value) (poo-flow-model? ADRLink value))
(def (ADR-option? value) (poo-flow-model? ADROption value))
(def (ADR-consequence? value) (poo-flow-model? ADRConsequence value))
(def (ADR-record? value) (poo-flow-model? ADRRecord value))

(def (unique-by? projection input-values)
  (let loop ((rest input-values) (seen '()))
    (cond
     ((null? rest) #t)
     ((member (projection (car rest)) seen) #f)
     (else (loop (cdr rest) (cons (projection (car rest)) seen))))))
(def (link-key link)
  (cons (.ref link 'relation) (.ref link 'target)))
(def (links-contain? record relation)
  (let loop ((rest (.ref record 'links)))
    (and (pair? rest)
         (or (eq? (.ref (car rest) 'relation) relation)
             (loop (cdr rest))))))
(def (chosen-option-count record)
  (length
   (filter (lambda (option)
             (eq? (.ref option 'disposition) 'chosen))
           (.ref record 'considered-options))))
(def (no-self-links? record)
  (every (lambda (link)
           (not (string=? (.ref record 'identity) (.ref link 'target))))
         (.ref record 'links)))

;;; Structural validity is nominal; semantic validity also enforces the MADR
;;; decision core and lifecycle constraints used by Aitia.
(def (ADR-record-valid? record)
  (and (ADR-record? record)
       (pair? (.ref record 'decision-drivers))
       (pair? (.ref record 'considered-options))
       (unique-by? (lambda (option) (.ref option 'identity))
                   (.ref record 'considered-options))
       (unique-by? link-key (.ref record 'links))
       (no-self-links? record)
       (let ((status (.ref record 'status))
             (chosen (chosen-option-count record)))
         (case status
           ((proposed) (<= chosen 1))
           ((rejected) (= chosen 0))
           ((accepted deprecated)
            (and (= chosen 1)
                 (pair? (.ref record 'consequences))
                 (pair? (.ref record 'decision-makers))))
           ((superseded)
            (and (= chosen 1)
                 (pair? (.ref record 'consequences))
                 (pair? (.ref record 'decision-makers))
                 (links-contain? record 'superseded-by)))
           (else #f)))))

(def (ADR-profile? value)
  (and (poo-flow-governance-profile? value)
       (.slot? value 'module-family)
       (eq? (.ref value 'module-family) 'ADR)))
