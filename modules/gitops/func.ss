;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .get .slot?)
        (only-in :clan/poo/mop .new .defgeneric)
        (only-in :clan/poo/type validate)
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
       (eq? (.get change event) event)
       (equal? (.get change target-ref) target-ref)))

(def (gitops-change provider event repository revision source-ref target-ref pull-request)
  (.new GitOpsChange
    provider: provider event: event repository: repository
    revision: revision source-ref: source-ref
    target-ref: target-ref pull-request: pull-request))

(def (gitops-check name repository revision conclusion
                   standard-edition: (standard-edition #f)
                   source-lock-digest: (source-lock-digest #f))
  (.new GitOpsCheck
    name: name repository: repository
    revision: revision conclusion: conclusion
    standard-edition: standard-edition
    source-lock-digest: source-lock-digest))

(def (composition-gitops-profiles composition)
  (filter gitops-profile? (.get composition profiles)))

(def (composition-standard-bindings composition)
  (map (lambda (profile)
         (let (standards (.get profile standards))
           (unless (and (list? standards) (= (length standards) 1))
             (error "standard Profile must bind exactly one Standard"
                    (.get profile name)))
           (cons (.get profile name) (car standards))))
       (filter (lambda (profile)
                 (and (.slot? profile 'role)
                      (eq? (.get profile role) 'standard)))
               (.get composition profiles))))

(def (standard-check-current? check standard)
  (and (.slot? standard 'edition)
       (.slot? standard 'source-lock-digest)
       (equal? (.get check standard-edition) (.get standard edition))
       (equal? (.get check source-lock-digest)
               (.get standard source-lock-digest))))

(def (check-index checks)
  (let (index (yuanxu-make-value-index))
    (for-each
     (lambda (check)
       (validate GitOpsCheck check)
       (let-values (((present? _previous)
                     (yuanxu-value-index-ref index (.get check name))))
         (when present? (error "duplicate GitOps check" (.get check name)))
         (yuanxu-value-index-put! index (.get check name) check)))
     checks)
    index))

(def (gitops-profile-decision profile standard-bindings change checks)
  (let* ((required (.get profile required-checks))
         (standards (map car standard-bindings))
         (index (check-index checks))
         (missing '()) (blockers '()) (stale '())
         (revision-mismatch? #f)
         (standard-mismatch? #f))
    (for-each
     (lambda (name)
       (let-values (((present? check) (yuanxu-value-index-ref index name)))
         (cond ((not present?) (set! missing (cons name missing)))
               ((or (not (equal? (.get check repository) (.get change repository)))
                    (not (equal? (.get check revision) (.get change revision))))
                (set! stale (cons name stale))
                (set! revision-mismatch? #t))
               ((let (binding (assoc name standard-bindings))
                  (and binding
                       (not (standard-check-current? check (cdr binding)))))
                (set! stale (cons name stale))
                (set! standard-mismatch? #t))
               ((not (eq? (.get check conclusion) 'success))
                (set! blockers (cons check blockers))))))
     (append required standards))
    (let (accepted? (and (null? missing) (null? blockers) (null? stale)))
      (validate GitOpsDecision
        (.new GitOpsDecision
          repository: (.get change repository) revision: (.get change revision)
          profile: (.get profile name) accepted: accepted?
          next-profile: (.get profile next-profile)
          environment: (.get profile environment)
          required-checks: required standards: standards
          missing-checks: (reverse missing)
          failed-checks: (map (lambda (check) (.get check name)) (reverse blockers))
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
      repository: (.get change repository) revision: (.get change revision)
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
