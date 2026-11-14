;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .cc .ref .get .o)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export github-adapter-test)

(def delivery (.get lambda-aitia.init.exports Profiles delivery))
(def gitops (.get lambda-aitia.init.exports modules gitops))
(def dev (.get delivery dev))
(def staging (.get delivery staging))
(def production (.get delivery production))
(def github-change (.get gitops github change))
(def github-check (.get gitops check))
(def github-run-gitops (.get gitops evaluate))
(def gitops-profile-matches? (.get lambda-aitia.init.exports modules gitops matches?))

(def github-adapter-test
  (test-suite "GitHub adapter Profile composition"
    (test-case "GitHub adapter consumes the maintained Profiles through the Module"
      (let* ((change (github-change 'pull-request "owner/repo" "r2" "feature/x" "develop" 7))
             (profiles (.o profiles: (list dev staging production)))
             (checks (map (lambda (name) (github-check name "owner/repo" "r2" 'success))
                          '(commit-policy build unit-test)))
             (decision (github-run-gitops profiles change checks))
             (retargeted (.cc dev 'target-ref "review")))
        (check-equal? (.ref decision 'profile) 'dev)
        (check-equal? (.ref decision 'accepted) #t)
        (check-equal? (gitops-profile-matches? retargeted change) #f)
        (check-equal? (gitops-profile-matches? retargeted
                        (github-change 'pull-request "owner/repo" "r2" "feature/x" "review" 7)) #t)))))
