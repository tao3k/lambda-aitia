;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .o .def .get .ref .slot? object?)
        (only-in "types.ss" gitops-commit-convention?))
(export OpenGitOpsProfile
        CommitConvention. ConventionalCommitsConvention ProjectKeyedCommitConvention
        gitops-resolve-commit-convention)

(def GitOpsProfile
  (.o gitops-profile?: #t
      identity: "gitops/profile"
      owner: 'lambda-aitia
      name: 'gitops
      environment: 'unbound
      event: 'reconciliation
      target-ref: "unbound"
      required-checks: '()
      reconciliation: 'continuous
      next-profile: 'complete
      principles: '()
      source-url: #f
      runtime-executed: #f
      .matches?: (lambda (_change) #f)))

(.def (OpenGitOpsProfile @ GitOpsProfile)
  ;; The public identity is stable; standard revisions belong in evidence,
  ;; not in Scheme/Python namespaces or exported binding names.
  (identity "open-gitops")
  (name 'open-gitops)
  (principles '(declarative versioned-and-immutable pulled-automatically
                continuously-reconciled))
  (source-url "https://opengitops.dev/"))

;;; First-class POO Commit Convention standard prototypes.
;;; Profiles and project naming map declaratively onto a CommitConvention
;;; instead of hard-coding title formatting inside semantic checks.
(def CommitConvention.
  (.o commit-convention?: #t
      identity: "gitops/commit-convention"
      name: 'commit-convention
      edition: "1.0.0"
      source-url: #f
      .valid-naming?: (lambda (_naming) #t)
      .render-title: (lambda (_naming _proposal) "")))

(.def (ConventionalCommitsConvention @ CommitConvention.)
  (identity "conventional-commits/1.0.0")
  (name 'conventional-commits)
  (edition "1.0.0")
  (source-url "https://www.conventionalcommits.org/en/v1.0.0/")
  (.valid-naming? (lambda (_naming) #t))
  (.render-title
   (lambda (_naming proposal)
     (string-append (.get proposal type) "(" (.get proposal scope) "): "
                    (.get proposal summary) " (" (.get proposal reference) ")"))))

(.def (ProjectKeyedCommitConvention @ CommitConvention.)
  (identity "project-keyed-conventional/1.0.0")
  (name 'project-keyed-conventional)
  (edition "1.0.0")
  (source-url "https://www.conventionalcommits.org/en/v1.0.0/")
  (.valid-naming?
   (lambda (naming)
     (let ((pk (.get naming project-key)))
       (and (string? pk) (> (string-length pk) 0)))))
  (.render-title
   (lambda (naming proposal)
     (string-append (.get naming project-key) "-" (.get proposal reference) " "
                    (.get proposal type) "(" (.get proposal scope) "): "
                    (.get proposal summary)))))

(def (gitops-resolve-commit-convention naming)
  (let ((declared (and (object? naming) (.slot? naming 'convention) (.ref naming 'convention))))
    (cond
     ((gitops-commit-convention? declared) declared)
     ((or (equal? declared "conventional-commits")
          (equal? declared "conventional-commits/1.0.0")
          (eq? declared 'conventional-commits))
      ConventionalCommitsConvention)
     ((or (equal? declared "project-keyed-conventional")
          (equal? declared "project-keyed-conventional/1.0.0")
          (eq? declared 'project-keyed-conventional))
      ProjectKeyedCommitConvention)
     ((not declared)
      (if (and (object? naming) (.slot? naming 'project-key) (string? (.ref naming 'project-key)))
        ProjectKeyedCommitConvention
        ConventionalCommitsConvention))
     (else #f))))
