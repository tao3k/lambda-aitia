;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list find)
        (only-in :clan/poo/object .get .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in "../../modules/gitops/config.ss" Config)
        (only-in "../../modules/gitops/types.ss" GitOpsScopeContract)
        (only-in "../../modules/gitops/features/github/objects.ss" enable-github)
        (only-in "../../modules/gitops/features/github/types.ss" GitHubFeatureContract)
        (only-in "../../modules/sdlc/objects.ss" SdlcProfile StandardProfile.)
        (only-in "../../modules/sdlc/func.ss" sdlc-with-standards)
        (rename-in (only-in "../../modules/nasa-7150-2d-catalog/config.ss" Config)
                   (Config NasaCatalog))
        (only-in "../../user-interface/profiles/gitops/config.ss" make-delivery-profile-scope)
        (only-in "../../user-interface/profiles/nasa/config.ss" make-nasa-profile-scope)
        (only-in "../../user-interface/scenarios/github-gitops/config.ss" make-github-gitops-scope))
(export github-workflow-test)

(def gitops (validate GitHubFeatureContract (enable-github (validate GitOpsScopeContract Config))))
(def nasa
  (make-nasa-profile-scope
    (.o profile: SdlcProfile standard-profile: StandardProfile. with-standards: sdlc-with-standards)
    NasaCatalog))
(def github-gitops-sdlc
  (.get (make-github-gitops-scope (make-delivery-profile-scope gitops) nasa) scenario))
(def github-change (.get gitops github change))
(def github-check (.get gitops check))
(def github-run-gitops (.get gitops evaluate))
(def nasa-sdlc-npr7150_2 (.get nasa standard))

(def repository "tao3k/agentic-ai-lab")
(def revision "0123456789abcdef")
(def nasa-standard (car (.ref nasa-sdlc-npr7150_2 'standards)))
(def (nasa-check (edition (.ref nasa-standard 'edition))
                 (digest (.ref nasa-standard 'source-lock-digest)))
  (github-check 'nasa/sdlc/npr-7150.2 repository revision 'success
                standard-edition: edition source-lock-digest: digest))
(def (successful-checks names (at-revision revision))
  (map (lambda (name)
         (if (eq? name 'nasa/sdlc/npr-7150.2)
           (github-check name repository at-revision 'success
                         standard-edition: (.ref nasa-standard 'edition)
                         source-lock-digest:
                         (.ref nasa-standard 'source-lock-digest))
           (github-check name repository at-revision 'success)))
       names))
(def dev-checks '(commit-policy build unit-test nasa/sdlc/npr-7150.2))
(def (run-github-gitops change checks)
  (github-run-gitops github-gitops-sdlc change checks))

(def github-workflow-test
  (test-suite "GitHub GitOps SDLC lifecycle"
    (test-case "Dev Staging Production are GitOps Profiles; NASA is one Standard"
      (check-equal? (.ref github-gitops-sdlc 'name)
                    'github-gitops-sdlc)
      (check-equal? (map (lambda (profile) (.ref profile 'name))
                         (.ref github-gitops-sdlc 'profiles))
                    '(actions dev staging production nasa/sdlc/npr-7150.2))
      (check-equal? (map (lambda (standard) (.ref standard 'identity))
                         (.ref nasa-sdlc-npr7150_2 'standards))
                    '("nasa/sdlc/npr-7150.2"))
      (check-equal? (map (lambda (standard) (.ref standard 'edition))
                         (.ref nasa-sdlc-npr7150_2 'standards))
                    '("D"))
      (let* ((proof
              (find (lambda (value)
                      (eq? (.ref value 'profile-identity) 'npr-7150.2))
                    (.ref github-gitops-sdlc 'selection-proofs)))
             (module-id (.ref proof 'module-definition)))
        (check-equal? (.ref module-id 'namespace) 'nasa)
        (check-equal? (.ref module-id 'name) 'sdlc)
        (check-equal? (.ref proof 'profile-identity) 'npr-7150.2)))
    (test-case "PR into develop advances Dev only with current checks and Standard assessment"
      (let* ((change (github-change 'pull-request repository revision
                                    "feature/gitops" "develop" 42))
             (decision (run-github-gitops change (successful-checks dev-checks))))
        (check-equal? (.ref decision 'profile) 'dev)
        (check-equal? (.ref decision 'environment) 'dev)
        (check-equal? (.ref decision 'accepted) #t)
        (check-equal? (.ref decision 'next-profile) 'staging)
        (check-equal? (.ref decision 'standards) '(nasa/sdlc/npr-7150.2))))
    (test-case "missing NASA assessment fails closed"
      (let (decision
            (run-github-gitops
             (github-change 'pull-request repository revision
                            "feature/gitops" "develop" 42)
             (successful-checks '(commit-policy build unit-test))))
        (check-equal? (.ref decision 'accepted) #f)
        (check-equal? (.ref decision 'missing-checks) '(nasa/sdlc/npr-7150.2))))
    (test-case "same-name green check without an edition-bound source lock fails closed"
      (let (decision
            (run-github-gitops
             (github-change 'pull-request repository revision
                            "feature/gitops" "develop" 42)
             (append (successful-checks '(commit-policy build unit-test))
                     (list (github-check 'nasa/sdlc/npr-7150.2
                                         repository revision 'success)))))
        (check-equal? (.ref decision 'accepted) #f)
        (check-equal? (.ref decision 'stale-checks) '(nasa/sdlc/npr-7150.2))
        (check-equal? (.ref decision 'reasons)
                      '(standard-assessment-mismatch))))
    (test-case "wrong NASA edition or source lock cannot authorize promotion"
      (for-each
       (lambda (check)
         (let (decision
               (run-github-gitops
                (github-change 'pull-request repository revision
                               "feature/gitops" "develop" 42)
                (append (successful-checks '(commit-policy build unit-test))
                        (list check))))
           (check-equal? (.ref decision 'accepted) #f)
           (check-equal? (.ref decision 'reasons)
                         '(standard-assessment-mismatch))))
       (list (nasa-check "C") (nasa-check
                               (.ref nasa-standard 'edition)
                               "sha256:wrong-lock"))))
    (test-case "checks for another Git revision cannot authorize promotion"
      (let (decision
            (run-github-gitops
             (github-change 'pull-request repository revision
                            "feature/gitops" "develop" 42)
             (successful-checks dev-checks "previous-revision")))
        (check-equal? (.ref decision 'accepted) #f)
        (check-equal? (.ref decision 'stale-checks) dev-checks)))
    (test-case "merge and protected release select different Profiles"
      (let* ((staging-decision
              (run-github-gitops
               (github-change 'push repository revision "develop" "develop" #f)
               (successful-checks
                '(integration-test security-review nasa/sdlc/npr-7150.2))))
             (production-decision
              (run-github-gitops
               (github-change 'workflow-dispatch repository revision
                              "develop" "production" #f)
               (successful-checks
                '(release-authority signed-provenance nasa/sdlc/npr-7150.2)))))
        (check-equal? (.ref staging-decision 'profile) 'staging)
        (check-equal? (.ref staging-decision 'next-profile) 'production)
        (check-equal? (.ref production-decision 'profile) 'production)
        (check-equal? (.ref production-decision 'environment) 'production)
        (check-equal? (.ref production-decision 'next-profile) 'complete)))
    (test-case "unrelated Git changes do not enter an environment Profile"
      (let (decision
            (run-github-gitops
             (github-change 'push repository revision "feature/x" "feature/x" #f)
             '()))
        (check-equal? (.ref decision 'profile) 'unmatched)
        (check-equal? (.ref decision 'reasons)
                      '(no-gitops-profile-matches-change))))))
