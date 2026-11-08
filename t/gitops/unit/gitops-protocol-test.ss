;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .cc .ref .get .o)
        (only-in :clan/poo/mop element?)
        :yuanxu/poo-clos/interface
        "../../../user-interface/adapters/gitops-evaluation.ss"
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export gitops-protocol-test)

(def gitops (.get (.get lambda-aitia.init.exports modules) gitops))
(def gitops-change (.get gitops change))
(def gitops-profile? (.get gitops profile?))
(def gitops-profile-matches? (.get gitops matches?))
(def GitOpsEvaluationProtocol (.get GitOpsEvaluation protocol))
(def GitOpsEvaluator (poo-clos-class 'gitops/test-base-evaluator))
(.defclass TestGitOpsEvaluator (GitOpsEvaluator) ())
(def TestGitOpsMethod
  (poo-clos-method
   'gitops/test-evaluation
   (list (poo-clos-class-specializer TestGitOpsEvaluator)
         (poo-clos-any-specializer) (poo-clos-any-specializer)
         (poo-clos-any-specializer))
   (lambda (_frame _evaluator _composition _change _checks)
     'specialized-evaluation)))
(.defmethod-bundle TestGitOpsMethods GitOpsEvaluationProtocol TestGitOpsMethod)
(def base-dev
  (.o (:: @ (.get gitops profile)) name: 'base-dev
      environment: 'dev event: 'pull-request target-ref: "develop"
      required-checks: '(build)
      reconciliation: 'automatic next-profile: 'staging
      .matches?: ((.get gitops match-change) 'pull-request "develop")))
(def test-dev
  (.o (:: @ base-dev) name: 'test-dev required-checks: '(build test)))

(def gitops-protocol-test
  (test-suite "GitOps Module dispatch and evidence boundaries"
    (test-case "POO prototype validates a declarative Profile"
      (check-equal? (gitops-profile? test-dev) #t)
      (check-equal?
       (gitops-profile-matches?
        test-dev (gitops-change 'github 'pull-request "owner/repo" "sha"
                                "feature/x" "develop" 7))
       #t))
    (test-case "GitHub Feature binds the provider through the GitOps Scope"
      (let* ((github (.get gitops github))
             (change ((.get github change) 'pull-request "owner/repo" "r2"
                       "feature/x" "develop" 7)))
        (check-equal? (.ref change 'provider) 'github)))
    (test-case "slot dispatch remains open to profile refinement"
      (let (refined (.cc base-dev '.matches? (lambda (_change) #t)))
        (check-equal?
         (gitops-profile-matches?
          refined (gitops-change 'github 'push "owner/repo" "sha"
                                 "other" "other" #f))
         #t)))
    (test-case "CLOS class specialization composes through a checked bundle"
      (let ((generic (poo-clos-generic-function
                      'gitops/test-generic 4
                      protocol: GitOpsEvaluationProtocol))
            (evaluator (poo-clos-make-instance TestGitOpsEvaluator)))
        (poo-clos-compose-method-bundle generic
          ((.get GitOpsEvaluation default-methods) gitops GitOpsEvaluator))
        (poo-clos-compose-method-bundle generic TestGitOpsMethods)
        (check-equal? (element? ClosMethodBundle TestGitOpsMethods) #t)
        (check-equal? (poo-clos-call generic evaluator #f #f '())
                      'specialized-evaluation)
        (let (decision (poo-clos-call generic (poo-clos-make-instance GitOpsEvaluator)
                          (.o profiles: '())
                          (gitops-change 'github 'push "owner/repo" "r2" "develop" "develop" #f)
                          '()))
          (check-equal? (.ref decision 'profile) 'unmatched)
          (check-equal? (.ref decision 'accepted) #f))))
    (test-case "default evaluation distinguishes current checks from stale revision"
      (let* ((composition (.o profiles: (list test-dev)))
             (change (gitops-change 'github 'pull-request "owner/repo" "r2" "feature/x" "develop" 7))
             (check-for (.get gitops check))
             (test-result (check-for 'test "owner/repo" "r2" 'success))
             (evaluate (.get gitops evaluate))
             (accepted (evaluate composition change
                         (list (check-for 'build "owner/repo" "r2" 'success
                                          standard-edition: #f source-lock-digest: #f)
                               test-result)))
             (stale (evaluate composition change
                      (list (check-for 'build "owner/repo" "r1" 'success) test-result))))
        (check-equal? (.ref accepted 'accepted) #t)
        (check-equal? (.ref stale 'accepted) #f)
        (check-equal? (.ref stale 'stale-checks) '(build))))))
