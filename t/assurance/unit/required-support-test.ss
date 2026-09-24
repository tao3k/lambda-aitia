;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow/src/module-system/contribution/model
                 poo-flow-model-prototype)
        :poo-flow/lambda-aitia/modules/assurance/interface)

(export required-support-test)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
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

(def (construct claim-value obligation-value relation-values)
  (assurance-snapshot
   "snapshot/software" "r1" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
   "event-cut/1" "policy/release" "r1"
   (list artifact claim-value obligation-value evidence) relation-values))
(def (bound-cut claim-value relation-values)
  (let (draft (construct claim-value obligation relation-values))
    (construct claim-value
               (assurance-bind-obligation-to-snapshot obligation draft)
               relation-values)))
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

(def required-support-test
  (test-suite "Host required support is an inert Decision input"
    (test-case "row model is well formed"
      (let (row (.o (:: @ (poo-flow-model-prototype AssessmentRequiredSupport))
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
        (check-equal? (.ref complete 'release-authorized?) #f)
        (check-equal?
         (assurance-required-support?
          (.o (:: @ complete) release-authorized?: #t)) #f)
        (check-equal? (first-blocker missing) 'admission-missing)
        (check-equal? (first-blocker copied) 'admission-missing)))

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
        (check-equal?
         (if (memq 'assumptions-unresolved (.ref assessment 'blockers)) #t #f)
         #t)))

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
        (check-equal?
         (first-blocker
          (assurance-host-required-support host claim (list admission)))
         'admission-invalid))
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
