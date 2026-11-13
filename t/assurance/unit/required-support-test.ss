;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .ref)
        (only-in "../../../init.ss" lambda-aitia.init.exports)
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature
                 source-lock-payload-digest))

(export required-support-test)

;;; Tests consume the admitted Scope; assertions below are unchanged.
(def assurance-module-scope (.get (.get lambda-aitia.init.exports modules) assurance))
(def AssessmentRequiredSupport (.get (.get assurance-module-scope contracts) required-support-row))
(def assessment-required-support? (.get assurance-module-scope required-support-row?))
(def assurance-artifact (.get assurance-module-scope artifact))
(def assurance-assumption (.get assurance-module-scope assumption))
(def assurance-bind-obligation-to-snapshot (.get assurance-module-scope bind-obligation))
(def assurance-claim (.get assurance-module-scope claim))
(def assurance-counterexample (.get assurance-module-scope counterexample))
(def assurance-decision (.get assurance-module-scope decision))
(def assurance-evidence (.get assurance-module-scope evidence))
(def assurance-host-admit (.get assurance-module-scope host-admit))
(def assurance-host-required-support (.get assurance-module-scope host-required-support))
(def assurance-host-revoke-admission! (.get assurance-module-scope host-revoke-admission!))
(def assurance-obligation (.get assurance-module-scope obligation))
(def assurance-relation (.get assurance-module-scope relation))
(def assurance-required-support? (.get assurance-module-scope required-support?))
(def assurance-snapshot (.get assurance-module-scope snapshot))
(def assurance-verification-host (.get assurance-module-scope verification-host))
(def assurance-verifier-input (.get assurance-module-scope verifier-input))
(def assurance-verifier-outcome (.get assurance-module-scope verifier-outcome))

(def source-bytes "the current recorded source")
(def digest-a (source-lock-payload-digest source-bytes))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def artifact
  (assurance-artifact "artifact/source" "r1" 'supported digest-a
                      owner: "maintainer" media-kind: 'scheme-source))
(def claim
  (assurance-claim "claim/release" "r1" 'unknown digest-b
                   subject: "software/release" predicate: "ready"
                   support-requirements: '("obligation/test")
                   scope: "repository" valid-from: "2026-09-23"))
(def obligation
  (assurance-obligation
   "obligation/test" "r1" 'unknown digest-a
   subject: "software/release" claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: 'gerbil-test scope: "repository"))
(def evidence
  (assurance-evidence
   "evidence/test" "r1" 'supported digest-b
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   input-artifacts: '("artifact/source") obligation: "obligation/test"
   subject: "software/release" scope: "repository"
   valid-from: "2026-09-23" admission-state: 'candidate))
(def evidence-link
  (assurance-relation "relation/discharge" 'assurance 'discharges
                      "evidence/test" "obligation/test" 'observed))
(def requirement-link
  (assurance-relation "relation/requirement" 'assurance 'supports
                      "obligation/test" "claim/release" 'declared))
(def relations (list evidence-link requirement-link))

(def (construct claim-value obligation-value relation-values (extra-nodes '()))
  (assurance-snapshot
   "snapshot/software" "r1" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
   "event-cut/1" "policy/release" "r1"
   (append (list artifact claim-value obligation-value evidence) extra-nodes) relation-values))
(def (bound-cut claim-value relation-values (extra-nodes '()))
  (let (draft (construct claim-value obligation relation-values extra-nodes))
    (construct claim-value
               (assurance-bind-obligation-to-snapshot obligation draft)
               relation-values extra-nodes)))
(def (bound-obligation snapshot)
  (find (lambda (node)
          (equal? (.ref node 'identity) "obligation/test"))
        (.ref snapshot 'nodes)))
(def (reported-outcome snapshot)
  (assurance-verifier-outcome
   "outcome/test" 'succeeded
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   obligation: "obligation/test" subject: "software/release"
   scope: "repository" snapshot-revision: "r1"
   snapshot-context-digest: (.ref snapshot 'context-digest)
   inputs: (list (assurance-verifier-input artifact))
   output-digest: digest-b))
(def (make-host source)
  (assurance-verification-host
   "host/required-support"
   (lambda (subject-value issued-at expires-at) #t)
   (lambda () 11) 9 source))
(def (first-blocker receipt)
  (.ref (car (.ref receipt 'requirements)) 'blocker))

(def (review-condition authority
        linked?: (linked? #t) scope: (scope "repository") expiry: (expiry #f)
        recorded?: (recorded? #t))
  (let* ((condition
          (assurance-assumption "assumption/toolchain" "r1" 'unknown digest-a
                                owner: "maintainer" scope: scope
                                review-policy: "human-review" expires-at: expiry))
         (conditional (.o (:: @ claim) assumptions: '("assumption/toolchain")))
         (review-obligation
          (.o (:: @ obligation) evidence-kind: 'human-review capability: 'assumption-review))
         (review-evidence
          (.o (:: @ evidence) producer: "review-service" tool: "review-record"))
         (review-relations
          (if linked?
            (cons (assurance-relation "relation/premise" 'assurance 'supports
                                      "obligation/test" "assumption/toolchain" 'declared)
                  relations)
            relations))
         (cut (lambda (bound)
                (assurance-snapshot
                 "snapshot/software" "r1" "graph/software"
                 '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
                 "event-cut/1" "policy/release" "r1"
                 (list artifact conditional bound review-evidence condition)
                 review-relations)))
         (snapshot
          (cut (assurance-bind-obligation-to-snapshot review-obligation
                                                      (cut review-obligation))))
         (outcome
          (.o (:: @ (reported-outcome snapshot)) producer: "review-service"
              tool: "review-record" accountable-authority: authority review-scope: "repository"))
         (recorded ((.get assurance-module-scope verifier-outcome-digest) outcome))
         (host (if recorded?
                 (assurance-verification-host
                  "host/assumption-review"
                  (lambda (subject now until inputs) #t)
                  (lambda () 11) 9 (lambda () snapshot)
                  source-reader: (lambda (identity)
                                   (and (equal? identity "artifact/source") source-bytes))
                  execution-reader: (lambda (identity)
                                      (and (equal? identity "outcome/test") recorded)))
                 (make-host (lambda () snapshot))))
         (admission (assurance-host-admit host (bound-obligation snapshot)
                                           review-evidence outcome)))
    (values host conditional admission)))

(def (assumption-result assessment)
  (car (.ref assessment 'assumption-assessments)))

(def (residual-case authority
        outcome: (decision-outcome 'allow) bind-decision?: (bind-decision? #t))
  (let* ((decision
          (assurance-decision "decision/residual" "r1" 'supported digest-b
                              subject: "software/release" snapshot: "snapshot/software"
                              policy: "policy/release" authority: "maintainer"
                              outcome: decision-outcome))
         (review-obligation
          (.o (:: @ obligation) identity: "obligation/residual-review"
              evidence-kind: 'human-review capability: 'residual-risk-acceptance))
         (decision-digest ((.get assurance-module-scope digest)
                           ((.get assurance-module-scope node-canonical) decision)))
         (report-digest (if bind-decision? decision-digest digest-b))
         (review-evidence
          (.o (:: @ evidence) identity: "evidence/residual-review"
              obligation: "obligation/residual-review" content-digest: report-digest
              producer: "review-service" tool: "review-record"))
         (edges
          (list requirement-link
                (assurance-relation "relation/residual" 'authority 'requires-review
                                    "obligation/test" "decision/residual" 'declared)
                (assurance-relation "relation/decision-claim" 'structural 'depends-on
                                    "decision/residual" "claim/release" 'declared)
                (assurance-relation "relation/review-decision" 'assurance 'supports
                                    "obligation/residual-review" "decision/residual" 'declared)
                (assurance-relation "relation/review-evidence" 'assurance 'discharges
                                    "evidence/residual-review" "obligation/residual-review" 'observed)))
         (cut (lambda (revision nodes)
                (assurance-snapshot
                 "snapshot/software" revision "graph/software"
                 '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
                 "event-cut/1" "policy/release" "r1"
                 (append (list artifact claim review-evidence decision) nodes) edges)))
         (make-cut (lambda (revision)
                     (let* ((nodes (list obligation review-obligation))
                            (draft (cut revision nodes)))
                       (cut revision (map (lambda (node)
                                            (assurance-bind-obligation-to-snapshot node draft))
                                          nodes)))))
         (snapshot (make-cut "r1"))
         (outcome
          (.o (:: @ (reported-outcome snapshot)) identity: "outcome/residual-review"
              obligation: "obligation/residual-review" producer: "review-service"
              tool: "review-record" accountable-authority: authority
              review-scope: "repository" output-digest: report-digest))
         (recorded ((.get assurance-module-scope verifier-outcome-digest) outcome))
         (host
          (assurance-verification-host
           "host/residual-review" (lambda (subject now until inputs) #t)
           (lambda () 11) 9 (lambda () snapshot)
           source-reader: (lambda (identity)
                            (and (equal? identity "artifact/source") source-bytes))
           execution-reader: (lambda (identity)
                               (and (equal? identity "outcome/residual-review") recorded))))
         (review-node
          (find (lambda (node) (equal? (.ref node 'identity) "obligation/residual-review"))
                (.ref snapshot 'nodes)))
         (admission (assurance-host-admit host review-node review-evidence outcome)))
    (values host admission (lambda () (set! snapshot (make-cut "r2"))))))

(def required-support-test
  (test-suite "Host required support is an inert Decision input"
    (test-case "row model is well formed"
      (let (row (.o (:: @ (.get AssessmentRequiredSupport proto))
                     obligation: "obligation/test" supported?: #t blocker: #f))
        (check-equal? (assessment-required-support? row) #t)))
    (test-case "exact admission and both relations close declared support only"
      (let* ((snapshot (bound-cut claim relations))
             (host (make-host (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot)))
             (complete
              (assurance-host-required-support host claim (list admission)))
             (missing (assurance-host-required-support host claim '()))
             (copied
              (assurance-host-required-support
               host claim (list (.o (:: @ admission))))))
        (check-equal? (assurance-required-support? complete) #t)
        (check-equal? (.ref complete 'complete?) #t)
        (check-equal? (.ref complete 'claim-revision) "r1")
        (check-equal? (.ref complete 'subject) "software/release")
        (check-equal? (.ref complete 'predicate) "ready")
        (check-equal? (.ref complete 'scope) "repository")
        (check-equal? (.ref complete 'release-authorized?) #f)
        (let (witness (car (.ref complete 'witnesses)))
          (check-equal? (.ref witness 'obligation) "obligation/test")
          (check-equal? (.ref witness 'evidence) "evidence/test")
          (check-equal? (.ref witness 'admission) (.ref admission 'identity))
          (check-equal? (.ref witness 'relation) "relation/discharge")
          (check-equal? (.ref witness 'outcome) "outcome/test")
          (check-equal? (.ref witness 'outcome-digest)
                        ((.get assurance-module-scope verifier-outcome-digest)
                         (reported-outcome snapshot)))
          (check-equal? (.ref witness 'declared-evidence-kind) 'native-test)
          (check-equal? (.ref witness 'capability) 'gerbil-test)
          (check-equal? (.ref witness 'scope) "repository")
          (check-equal? (.ref witness 'producer) "gxtest")
          (check-equal? (.ref witness 'tool-version) "v19")
          (check-equal? (.ref witness 'input-artifacts) '("artifact/source"))
          (check-equal? (.ref witness 'expires-at) 20))
        (check-equal? (.ref copied 'witnesses) '())
        (check-equal? (.ref missing 'witnesses) '())
        (check-equal?
         (assurance-required-support?
          (.o (:: @ complete) release-authorized?: #t)) #f)
        (check-equal? (first-blocker missing) 'admission-missing)
        (check-equal? (first-blocker copied) 'admission-missing)))

    (test-case "only an owner-recorded attempt survives admission"
      (let* ((snapshot (bound-cut claim relations))
             (outcome (reported-outcome snapshot))
             (outcome-digest (.get assurance-module-scope verifier-outcome-digest))
             (recorded-digest #f)
             (host
              (assurance-verification-host
               "host/recorded-execution"
               (lambda (subject-value issued-at expires-at inputs) #t)
               (lambda () 11) 9 (lambda () snapshot)
               source-reader: (lambda (identity)
                                (and (equal? identity "artifact/source") source-bytes))
               execution-reader: (lambda (identity)
                                   (and (equal? identity "outcome/test")
                                        recorded-digest))))
             (obligation-value (bound-obligation snapshot))
             (current? (.get assurance-module-scope host-admission-current?)))
        (check-equal? (assurance-host-admit host obligation-value evidence outcome) #f)
        (set! recorded-digest (outcome-digest outcome))
        ;; This field does not affect the ordinary native-test evidence binding.
        (check-equal?
         (assurance-host-admit
          host obligation-value evidence
          (.o (:: @ outcome) accountable-authority: "substituted authority"))
         #f)
        (let (admission (assurance-host-admit host obligation-value evidence outcome))
          (check-equal? (current? host admission) #t)
          (check-equal?
           (.ref (assurance-host-required-support host claim (list admission))
                 'complete?) #t)
          (set! recorded-digest #f)
          (check-equal? (current? host admission) #f)
          (set! recorded-digest (outcome-digest outcome))
          (check-equal? (current? host admission) #f)
          (check-equal?
           (first-blocker (assurance-host-required-support host claim (list admission)))
           'admission-invalid))))

    (test-case "undeclared and disconnected requirements stay blocked"
      (let* ((snapshot (bound-cut claim relations))
             (host (make-host (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot)))
             (two-required
              (.o (:: @ claim)
                  support-requirements:
                  '("obligation/test" "obligation/independent")))
             (two-cut (bound-cut two-required relations))
             (two-host (make-host (lambda () two-cut)))
             (assessment
              (assurance-host-required-support
               two-host two-required (list admission)))
             (no-link-cut (bound-cut claim (list evidence-link)))
             (no-link-host (make-host (lambda () no-link-cut)))
             (no-link-admission
              (assurance-host-admit
               no-link-host (bound-obligation no-link-cut) evidence
               (reported-outcome no-link-cut)))
             (disconnected
              (assurance-host-required-support
               no-link-host claim (list no-link-admission))))
        (check-equal? (.ref assessment 'complete?) #f)
        (check-equal?
         (.ref (cadr (.ref assessment 'requirements)) 'blocker)
         'obligation-missing)
        (check-equal? (first-blocker disconnected) 'support-link-missing)))

    (test-case "assumption closure is not inferred from verifier admission"
      (let* ((assumed
              (.o (:: @ claim) assumptions: '("assumption/toolchain")))
             (snapshot (bound-cut assumed relations))
             (host (make-host (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot)))
             (assessment
              (assurance-host-required-support host assumed (list admission))))
        (check-equal? (.ref assessment 'complete?) #f)
        (check-equal? (.ref (assumption-result assessment) 'blocker) 'assumption-missing)
        (check-equal? (length (.ref assessment 'witnesses)) 1)
        (check-equal?
         (if (memq 'assumptions-unresolved (.ref assessment 'blockers)) #t #f)
         #t)))

    (test-case "explicit scoped review qualifies the premise while its admission is current"
      (let-values (((host conditional admission) (review-condition "maintainer")))
        (let* ((assessment (assurance-host-required-support host conditional (list admission)))
               (condition (assumption-result assessment)))
          (check-equal? (.ref assessment 'complete?) #t)
          (check-equal? (.ref assessment 'release-authorized?) #f)
          (check-equal? (.ref condition 'owner) "maintainer")
          (check-equal? (.ref condition 'obligation) "obligation/test")
          (check-equal? (.ref condition 'admission) (.ref admission 'identity))
          (check-equal? (.ref condition 'blocker) #f))
        (assurance-host-revoke-admission! host admission)
        (let (reopened (assurance-host-required-support host conditional (list admission)))
          (check-equal? (.ref reopened 'complete?) #f)
          (check-equal? (.ref (assumption-result reopened) 'blocker) 'review-missing))))

    (test-case "review metadata alone cannot qualify a premise"
      (for-each
       (lambda (scenario)
         (let-values (((host conditional admission) ((car scenario))))
           (let (assessment (assurance-host-required-support host conditional (list admission)))
             (check-equal? (length (.ref assessment 'witnesses)) 1)
             (check-equal? (.ref assessment 'complete?) #f)
             (check-equal? (.ref (assumption-result assessment) 'blocker) (cdr scenario)))))
       (list (cons (lambda () (review-condition "unrelated-reviewer")) 'review-missing)
             (cons (lambda () (review-condition "maintainer" recorded?: #f)) 'review-missing)
             (cons (lambda () (review-condition "maintainer" linked?: #f)) 'review-missing)
             (cons (lambda () (review-condition "maintainer" scope: "elsewhere")) 'scope-mismatch)
             (cons (lambda () (review-condition "maintainer" expiry: "2026-12-31"))
                   'validity-unqualified))))

    (test-case "a changed proposition cannot inherit support by claim identity"
      (let* ((snapshot (bound-cut claim relations))
             (host (make-host (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot)))
             (rewritten (.o (:: @ claim) predicate: "unconditionally ready"))
             (unbound
              (assurance-host-required-support host rewritten (list admission))))
        (check-equal? (.ref unbound 'complete?) #f)
        (check-equal? (first-blocker unbound) 'claim-not-current)
        (check-equal? (.ref (car (.ref unbound 'requirements)) 'supported?) #f)
        (check-equal? (.ref unbound 'witnesses) '())
        (set! snapshot (bound-cut rewritten relations))
        (let (reopened
              (assurance-host-required-support host rewritten (list admission)))
          (check-equal? (.ref reopened 'complete?) #f)
          (check-equal? (first-blocker reopened) 'admission-invalid)
          (check-equal? (.ref reopened 'witnesses) '()))))

    (test-case "source movement after witness lookup reopens every affected row"
      (let* ((snapshot (bound-cut claim relations))
             (changed-cut
              (bound-cut (.o (:: @ claim) predicate: "ready after revision")
                         relations))
             (outcome (reported-outcome snapshot))
             (recorded ((.get assurance-module-scope verifier-outcome-digest)
                        outcome))
             (move-on-read? #f)
             (host
              (assurance-verification-host
               "host/moving-cut" (lambda (subject now until inputs) #t)
               (lambda () 11) 9 (lambda () snapshot)
               source-reader: (lambda (identity) source-bytes)
               execution-reader: (lambda (identity)
                                   (when move-on-read? (set! snapshot changed-cut))
                                   (and (equal? identity "outcome/test") recorded))))
             (admission (assurance-host-admit host (bound-obligation snapshot)
                                               evidence outcome)))
        (check-equal? (.ref (assurance-host-required-support host claim (list admission))
                            'complete?) #t)
        (set! move-on-read? #t)
        (let (reopened (assurance-host-required-support host claim (list admission)))
          (check-equal? (.ref reopened 'complete?) #f)
          (check-equal? (first-blocker reopened) 'source-changed)
          (check-equal? (.ref (car (.ref reopened 'requirements)) 'supported?) #f)
          (check-equal? (.ref reopened 'witnesses) '()))))

    (test-case "foreign and historical challenges remain visible without a current evidence binding"
      (for-each
       (lambda (scenario)
         (let* ((counterexample
                 (assurance-counterexample "counterexample/replay" (car scenario)
                                           (caddr scenario) digest-b subject: (cadr scenario)
                                           challenges: "claim/release" evidence: "evidence/test"
                                           details-digest: digest-b))
                (edge (assurance-relation "relation/challenge" 'assurance 'defeats
                                          "counterexample/replay" "claim/release" 'observed))
                (snapshot (bound-cut claim (cons edge relations) (list counterexample)))
                (host (make-host (lambda () snapshot)))
                (assessment (assurance-host-required-support host claim '()))
                (challenge (car (.ref assessment 'challenges))))
           (check-equal? (.ref assessment 'complete?) #f)
           (check-equal? (first-blocker assessment) 'admission-missing)
           (check-equal? (.ref challenge 'evidence) "evidence/test")
           (check-equal? (.ref challenge 'evidence-digest) #f)
           (check-equal? (.ref challenge 'obligation) #f)))
       '(("r1" "different-subject" supported)
         ("r0" "software/release" supported)
         ("r1" "software/release" stale))))

    (test-case "residual acceptance records a separate reviewed decision and leaves the claim open"
      (let-values (((host admission rewrite!) (residual-case "maintainer")))
        (check-equal? (not (not admission)) #t)
        (let* ((assessment (assurance-host-required-support host claim (list admission)))
               (disposition (car (.ref assessment 'residual-dispositions))))
          (check-equal? (.ref assessment 'complete?) #f)
          (check-equal? (.ref assessment 'release-authorized?) #f)
          (check-equal? (.ref assessment 'witnesses) '())
          (check-equal? (first-blocker assessment) 'admission-missing)
          (check-equal? (.ref disposition 'obligation) "obligation/test")
          (check-equal? (.ref disposition 'decision) "decision/residual")
          (check-equal? (.ref disposition 'admission) (.ref admission 'identity)))
        (check-equal? (.ref (assurance-host-required-support host claim (list (.o (:: @ admission))))
                            'residual-dispositions) '())
        (rewrite!)
        (check-equal? (.ref (assurance-host-required-support host claim (list admission))
                            'residual-dispositions) '())))

    (test-case "a foreign reviewer, denied decision or substituted record cannot accept the risk"
      (for-each
       (lambda (make-case)
         (let-values (((host admission _) (make-case)))
           (check-equal? (not (not admission)) #t)
           (check-equal? (.ref (assurance-host-required-support host claim (list admission))
                               'residual-dispositions) '())))
       (list (lambda () (residual-case "other-reviewer"))
             (lambda () (residual-case "maintainer" outcome: 'deny))
             (lambda () (residual-case "maintainer" bind-decision?: #f)))))

    (test-case "expiry and revocation reopen required support"
      (let* ((now 11)
             (snapshot (bound-cut claim relations))
             (host
              (assurance-verification-host
               "host/required-support-expiry"
               (lambda (subject-value issued-at expires-at) #t)
               (lambda () now) 9 (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot))))
        (check-equal?
         (.ref (assurance-host-required-support host claim (list admission))
               'complete?) #t)
        (set! now 20)
        (let (expired (assurance-host-required-support host claim (list admission)))
          (check-equal? (first-blocker expired) 'admission-invalid)
          (check-equal? (.ref expired 'witnesses) '())))
      (let* ((snapshot (bound-cut claim relations))
             (host (make-host (lambda () snapshot)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot) evidence
               (reported-outcome snapshot))))
        (assurance-host-revoke-admission! host admission)
        (check-equal?
         (first-blocker
          (assurance-host-required-support host claim (list admission)))
         'admission-missing)))))
