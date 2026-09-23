;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Aitia owns software-design meaning; POO Flow owns graph traversal and
;;; runtime authority. This is an inert declaration-level replacement check.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil/core list-sort)
        :std/list/list
        :poo-flow/src/module-system/contribution/model
        :poo-flow/lambda-aitia/modules/sdlc/types)

(export SdlcDesignClause SdlcDesignVariation SdlcDesignContract
        sdlc-design-clause? sdlc-design-variation? sdlc-design-contract?
        sdlc-design-assumption sdlc-design-guarantee
        sdlc-design-variation sdlc-design-contract
        sdlc-design-replacement-review)

(def (text-list? values)
  (and (list? values) (every sdlc-text? values)
       (= (length values) (length (delete-duplicates/hash values)))))
(def (nonempty-text-list? values)
  (and (text-list? values) (pair? values)))
(def (identified-list? values predicate)
  (and (list? values) (every predicate values)
       (let (ids (map (lambda (value) (.ref value 'identity)) values))
         (= (length ids) (length (delete-duplicates/hash ids))))))
(def (clause-list? kind)
  (lambda (values)
    (and (identified-list? values sdlc-design-clause?)
         (every (lambda (value) (eq? (.ref value 'kind) kind)) values))))
(def (variation-list? values)
  (identified-list? values sdlc-design-variation?))
(def (slot name predicate)
  (poo-clos-direct-slot-definition name type-predicate: predicate))

(def SdlcDesignClause
  (poo-clos-class 'sdlc/design-clause
    direct-slots:
    (list (slot 'identity sdlc-text?) (slot 'revision sdlc-text?)
          (slot 'kind (lambda (value) (if (memq value '(assumption guarantee)) #t #f)))
          (slot 'statement sdlc-text?))))
(def SdlcDesignVariation
  (poo-clos-class 'sdlc/design-variation
    direct-slots:
    (list (slot 'identity sdlc-text?) (slot 'revision sdlc-text?)
          (slot 'affects-guarantees nonempty-text-list?))))
(def SdlcDesignContract
  (poo-clos-class 'sdlc/design-contract
    direct-slots:
    (list (slot 'identity sdlc-text?) (slot 'revision sdlc-text?)
          (slot 'decision sdlc-text?)
          (slot 'responsibilities text-list?)
          (slot 'owned-state text-list?)
          (slot 'allowed-effects text-list?)
          (slot 'assumptions (clause-list? 'assumption))
          (slot 'guarantees (clause-list? 'guarantee))
          (slot 'variations variation-list?))))

(def (sdlc-design-clause? value)
  (poo-flow-model? SdlcDesignClause value))
(def (sdlc-design-variation? value)
  (poo-flow-model? SdlcDesignVariation value))
(def (sdlc-design-contract? value)
  (and (poo-flow-model? SdlcDesignContract value)
       (pair? (.ref value 'responsibilities))
       (pair? (.ref value 'guarantees))
       (let (guarantees (map (lambda (clause) (.ref clause 'identity))
                            (.ref value 'guarantees)))
         (every (lambda (variation)
                  (every (lambda (id) (member id guarantees))
                         (.ref variation 'affects-guarantees)))
                (.ref value 'variations)))))

(def (design-clause kind-value id revision-value statement-value)
  (poo-flow-check-model
   SdlcDesignClause
   (.o (:: @ (poo-flow-model-prototype SdlcDesignClause))
       identity: id revision: revision-value kind: kind-value
       statement: statement-value)))
(def (sdlc-design-assumption id revision-value statement-value)
  (design-clause 'assumption id revision-value statement-value))
(def (sdlc-design-guarantee id revision-value statement-value)
  (design-clause 'guarantee id revision-value statement-value))
(def (sdlc-design-variation id revision-value affected-guarantees)
  (poo-flow-check-model
   SdlcDesignVariation
   (.o (:: @ (poo-flow-model-prototype SdlcDesignVariation))
       identity: id revision: revision-value
       affects-guarantees: affected-guarantees)))
(def (sdlc-design-contract id revision-value decision-value responsibility-values
                           owned-state-values effect-values assumption-values
                           guarantee-values variation-values)
  (let (value
        (poo-flow-check-model
         SdlcDesignContract
         (.o (:: @ (poo-flow-model-prototype SdlcDesignContract))
             identity: id revision: revision-value decision: decision-value
             responsibilities: responsibility-values
             owned-state: owned-state-values
             allowed-effects: effect-values assumptions: assumption-values
             guarantees: guarantee-values variations: variation-values)))
    (unless (sdlc-design-contract? value)
      (error "design contract lacks a responsibility or guarantee, or a variation references an undeclared guarantee" id))
    value))

(def (ordered-ids values)
  (list-sort string<? (delete-duplicates/hash values)))
(def (clause-key value)
  (list (.ref value 'identity) (.ref value 'revision)
        (.ref value 'kind) (.ref value 'statement)))
(def (variation-key value)
  (list (.ref value 'identity) (.ref value 'revision)
        (ordered-ids (.ref value 'affects-guarantees))))
(def (ordered-keys values key)
  (list-sort (lambda (left right) (string<? (car left) (car right)))
             (map key values)))
(def (contract-body value)
  (list (.ref value 'decision)
        (ordered-ids (.ref value 'responsibilities))
        (ordered-ids (.ref value 'owned-state))
        (ordered-ids (.ref value 'allowed-effects))
        (ordered-keys (.ref value 'assumptions) clause-key)
        (ordered-keys (.ref value 'guarantees) clause-key)
        (ordered-keys (.ref value 'variations) variation-key)))
(def (changed-ids old-values new-values key)
  (ordered-ids
   (append
    (map (lambda (value) (.ref value 'identity))
         (filter (lambda (value) (not (member (key value) (map key new-values))))
                 old-values))
    (map (lambda (value) (.ref value 'identity))
         (filter (lambda (value) (not (member (key value) (map key old-values))))
                 new-values)))))
(def (subset? left right)
  (every (lambda (value) (member value right)) left))
(def (clause-subset? left right)
  (subset? (map clause-key left) (map clause-key right)))
(def (variation-affected values ids)
  (concatenate
   (map (lambda (variation)
          (if (member (.ref variation 'identity) ids)
            (.ref variation 'affects-guarantees) '()))
        values)))

;;; Exact clause equality is the only declaration-level entailment admitted:
;;; old assumptions must cover every new assumption, while new guarantees
;;; must retain every old guarantee. No textual/logical equivalence is inferred.
;;; Selected guarantees are re-verification requests, never admitted evidence.
(def (sdlc-design-replacement-review old new)
  (unless (and (sdlc-design-contract? old)
               (sdlc-design-contract? new)
               (equal? (.ref old 'identity) (.ref new 'identity)))
    (error "design replacement requires two valid versions of one contract"))
  (when (and (equal? (.ref old 'revision) (.ref new 'revision))
             (not (equal? (contract-body old) (contract-body new))))
    (error "design declaration changed without a revision change"))
  (let* ((old-assumptions (.ref old 'assumptions))
         (new-assumptions (.ref new 'assumptions))
         (old-guarantees (.ref old 'guarantees))
         (new-guarantees (.ref new 'guarantees))
         (changed-assumptions
          (changed-ids old-assumptions new-assumptions clause-key))
         (changed-guarantees
          (changed-ids old-guarantees new-guarantees clause-key))
         (changed-variations
          (changed-ids (.ref old 'variations) (.ref new 'variations)
                       variation-key))
         (responsibilities-changed?
          (not (equal? (ordered-ids (.ref old 'responsibilities))
                       (ordered-ids (.ref new 'responsibilities)))))
         (state-changed?
          (not (equal? (ordered-ids (.ref old 'owned-state))
                       (ordered-ids (.ref new 'owned-state)))))
         (effects-changed?
          (not (equal? (ordered-ids (.ref old 'allowed-effects))
                       (ordered-ids (.ref new 'allowed-effects)))))
         (decision-changed?
          (not (equal? (.ref old 'decision) (.ref new 'decision))))
         (all-guarantees
          (ordered-ids (append (map (lambda (v) (.ref v 'identity)) old-guarantees)
                               (map (lambda (v) (.ref v 'identity)) new-guarantees))))
         (broad-change?
          (or (pair? changed-assumptions) responsibilities-changed?
              state-changed? effects-changed? decision-changed?))
         (affected
          (ordered-ids
           (if broad-change?
             all-guarantees
             (append changed-guarantees
                     (variation-affected (.ref old 'variations)
                                         changed-variations)
                     (variation-affected (.ref new 'variations)
                                         changed-variations)))))
         (blocker-values
          (append
           (if (clause-subset? new-assumptions old-assumptions) '()
             '(stronger-or-changed-assumption))
           (if (clause-subset? old-guarantees new-guarantees) '()
             '(weaker-or-changed-guarantee))
           (if (subset? (.ref new 'allowed-effects) (.ref old 'allowed-effects))
             '() '(new-effect))
           (if responsibilities-changed? '(responsibility-changed) '())
           (if state-changed? '(state-ownership-changed) '())
           (if decision-changed? '(decision-changed) '())
           (if (pair? changed-variations) '(variation-changed) '()))))
    (.o kind: 'sdlc.design-replacement-review
        contract: (.ref old 'identity)
        from-revision: (.ref old 'revision)
        to-revision: (.ref new 'revision)
        declared-substitutable?: (null? blocker-values)
        blockers: blocker-values
        changed-identities:
        (ordered-ids
         (append changed-assumptions changed-guarantees changed-variations
                 (if (or responsibilities-changed? state-changed? effects-changed?
                         decision-changed?
                         (and (not (equal? (.ref old 'revision)
                                           (.ref new 'revision)))
                              (equal? (contract-body old)
                                      (contract-body new))))
                   (list (.ref old 'identity)) '())))
        recheck-guarantees:
        (if (and (not (equal? (.ref old 'revision) (.ref new 'revision)))
                 (equal? (contract-body old) (contract-body new)))
          all-guarantees affected)
        evidence-admitted?: #f
        release-authorized?: #f
        runtime-executed?: #f)))
