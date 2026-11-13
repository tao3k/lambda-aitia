;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .ref .slot?)
        (only-in :clan/poo/mop .new validate .defgeneric)
        :std/list/list
        (only-in :tao3k/yuanxu/utilities/algorithms
                 yuanxu-make-value-index yuanxu-value-index-put!
                 yuanxu-value-index-ref)
        "types.ss")
(export gitops-change gitops-check gitops-profile-matches? gitops-match-change
        gitops-evaluate-default)

(.defgeneric (gitops-profile-matches? profile change) slot: .matches?)

(def ((gitops-match-change event target-ref) change)
  (and (gitops-change? change)
       (eq? (.ref change 'event) event)
       (equal? (.ref change 'target-ref) target-ref)))

(def (gitops-change provider-value event-value repository-value revision-value
                    source-ref-value target-ref-value pull-request-value)
  (.new GitOpsChange
    provider: provider-value event: event-value repository: repository-value
    revision: revision-value source-ref: source-ref-value
    target-ref: target-ref-value pull-request: pull-request-value))
(def (gitops-check name-value repository-value revision-value conclusion-value
                   standard-edition: (standard-edition-value #f)
                   source-lock-digest: (source-lock-digest-value #f))
  (.new GitOpsCheck name: name-value repository: repository-value
        revision: revision-value conclusion: conclusion-value
        standard-edition: standard-edition-value
        source-lock-digest: source-lock-digest-value))

(def (composition-gitops-profiles composition)
  (filter gitops-profile? (.ref composition 'profiles)))
(def (composition-standard-bindings composition)
  (map (lambda (profile)
         (let (standards (.ref profile 'standards))
           (unless (and (list? standards) (= (length standards) 1))
             (error "standard Profile must bind exactly one Standard"
                    (.ref profile 'name)))
           (cons (.ref profile 'name) (car standards))))
       (filter (lambda (profile)
                 (and (.slot? profile 'role)
                      (eq? (.ref profile 'role) 'standard)))
               (.ref composition 'profiles))))
(def (standard-check-current? check standard)
  (and (.slot? standard 'edition)
       (.slot? standard 'source-lock-digest)
       (equal? (.ref check 'standard-edition) (.ref standard 'edition))
       (equal? (.ref check 'source-lock-digest)
               (.ref standard 'source-lock-digest))))
(def (check-index checks)
  (let (index (yuanxu-make-value-index))
    (for-each
     (lambda (check)
       (validate GitOpsCheck check)
       (let-values (((present? previous)
                     (yuanxu-value-index-ref index (.ref check 'name))))
         (when present? (error "duplicate GitOps check" (.ref check 'name)))
         (yuanxu-value-index-put! index (.ref check 'name) check)))
     checks)
    index))
(def (gitops-profile-decision profile standard-bindings change checks)
  (let* ((required (.ref profile 'required-checks))
         (standards (map car standard-bindings))
         (index (check-index checks))
         (missing '()) (blockers '()) (stale '())
         (revision-mismatch? #f)
         (standard-mismatch? #f))
    (for-each
     (lambda (name)
       (let-values (((present? check) (yuanxu-value-index-ref index name)))
         (cond ((not present?) (set! missing (cons name missing)))
               ((or (not (equal? (.ref check 'repository) (.ref change 'repository)))
                    (not (equal? (.ref check 'revision) (.ref change 'revision))))
                (set! stale (cons name stale))
                (set! revision-mismatch? #t))
               ((let (binding (assoc name standard-bindings))
                  (and binding
                       (not (standard-check-current? check (cdr binding)))))
                (set! stale (cons name stale))
                (set! standard-mismatch? #t))
               ((not (eq? (.ref check 'conclusion) 'success))
                (set! blockers (cons check blockers))))))
     (append required standards))
    (let (accepted? (and (null? missing) (null? blockers) (null? stale)))
      (validate GitOpsDecision
        (.new GitOpsDecision
          repository: (.ref change 'repository) revision: (.ref change 'revision)
          profile: (.ref profile 'name) accepted: accepted?
          next-profile: (.ref profile 'next-profile)
          environment: (.ref profile 'environment)
          required-checks: required standards: standards
          missing-checks: (reverse missing)
          failed-checks: (map (lambda (check) (.ref check 'name)) (reverse blockers))
          check-blockers: (reverse blockers)
          stale-checks: (reverse stale)
          reasons: (append (if (null? missing) '() '(required-check-missing))
                           (if (null? blockers) '() '(required-check-failed))
                           (if revision-mismatch?
                             '(check-revision-mismatch) '())
                           (if standard-mismatch?
                             '(standard-assessment-mismatch) '())))))))
(def (gitops-unmatched-decision change)
  (validate GitOpsDecision
    (.new GitOpsDecision
      repository: (.ref change 'repository) revision: (.ref change 'revision)
      profile: 'unmatched accepted: #f next-profile: 'none environment: 'none
      required-checks: '() standards: '() missing-checks: '()
      failed-checks: '() check-blockers: '() stale-checks: '()
      reasons: '(no-gitops-profile-matches-change))))
(def (gitops-evaluate-default composition change checks)
  (validate GitOpsChange change)
  (unless (and (list? checks) (every gitops-check? checks))
    (error "invalid GitOps checks" checks))
  (let (profile
        (find (lambda (candidate)
                (gitops-profile-matches? candidate change))
              (composition-gitops-profiles composition)))
    (if profile
      (gitops-profile-decision
       profile (composition-standard-bindings composition) change checks)
        (gitops-unmatched-decision change))))
