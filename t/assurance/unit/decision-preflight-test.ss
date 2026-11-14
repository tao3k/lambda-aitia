;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import
        (only-in "../../../modules/assurance/cedar-preflight.ss"
                 assurance-host-cedar-request
                 assurance-host-cedar-source-admission
                 assurance-host-cedar-request-current?)
        :std/test :std/error
        (only-in :clan/poo/object .o .ref)
        (only-in :agentic-ai-lab/modules/authorization/providers/cedar/objects
                 agentic-ai-lab-cedar-runtime-handoff
                 agentic-ai-lab-cedar-authorization-request?
                 agentic-ai-lab-cedar-authorization-request->runtime)
        (only-in :lambda-aitia/modules/assurance/config Config)
        (only-in :clan/poo/object .get))

(export decision-preflight-test make-cedar-delivery-fixture)

;;; Use the built Assurance exports in both the unit suite and Cedar recovery fixture.
(def assurance-module-scope Config)
(def assurance-artifact (.get assurance-module-scope artifact))
(def assurance-bind-obligation-to-snapshot (.get assurance-module-scope bind-obligation))
(def assurance-claim (.get assurance-module-scope claim))
(def assurance-decision (.get assurance-module-scope decision))
(def assurance-decision-preflight? (.get assurance-module-scope decision-preflight?))
(def assurance-evidence (.get assurance-module-scope evidence))
(def assurance-host-admission-current? (.get assurance-module-scope host-admission-current?))
(def assurance-host-admit (.get assurance-module-scope host-admit))
(def assurance-host-decision-preflight-current? (.get assurance-module-scope host-preflight-current?))
(def assurance-host-preflight-decision (.get assurance-module-scope host-preflight))
(def assurance-host-revoke-admission! (.get assurance-module-scope host-revoke-admission!))
(def assurance-host-revoke-decision-preflight! (.get assurance-module-scope host-revoke-preflight!))
(def assurance-obligation (.get assurance-module-scope obligation))
(def assurance-relation (.get assurance-module-scope relation))
(def assurance-snapshot (.get assurance-module-scope snapshot))
(def assurance-verification-host (.get assurance-module-scope verification-host))
(def assurance-verifier-input (.get assurance-module-scope verifier-input))
(def assurance-verifier-outcome (.get assurance-module-scope verifier-outcome))

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def release-subject "Job::\"release\"")
(def release-authority "User::\"maintainer\"")
(def artifact
  (assurance-artifact "artifact/source" "r1" 'supported digest-a
                      owner: "maintainer" media-kind: 'scheme-source))
(def claim
  (assurance-claim "claim/release" "r1" 'unknown digest-b
                   subject: release-subject predicate: "ready"
                   support-requirements: '("obligation/test")
                   scope: "repository" valid-from: "2026-09-23"))
(def obligation
  (assurance-obligation
   "obligation/test" "r1" 'unknown digest-a
   subject: release-subject claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: 'gerbil-test scope: "repository"))
(def evidence
  (assurance-evidence
   "evidence/test" "r1" 'supported digest-b
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   input-artifacts: '("artifact/source") obligation: "obligation/test"
   subject: release-subject scope: "repository"
   valid-from: "2026-09-23" admission-state: 'candidate))
(def decision
  (assurance-decision
   "decision/release" "r1" 'unknown digest-a
   subject: release-subject snapshot: "snapshot/software"
   policy: "policy/release" authority: release-authority outcome: 'unknown))
(def evidence-link
  (assurance-relation "relation/discharge" 'assurance 'discharges
                      "evidence/test" "obligation/test" 'observed))
(def requirement-link
  (assurance-relation "relation/requirement" 'assurance 'supports
                      "obligation/test" "claim/release" 'declared))
(def decision-link
  (assurance-relation "relation/decision-dependency" 'structural 'depends-on
                      "decision/release" "claim/release" 'declared))
(def relations (list evidence-link requirement-link decision-link))

(def (construct obligation-value relation-values fact-cut-value)
  (assurance-snapshot
   "snapshot/software" "r1" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
   fact-cut-value "policy/release" "r1"
   (list artifact claim obligation-value evidence decision) relation-values))
(def (bound-cut relation-values)
  (let (draft (construct obligation relation-values "event-cut/1"))
    (construct (assurance-bind-obligation-to-snapshot obligation draft)
               relation-values "event-cut/1")))
(def (bound-obligation snapshot-value)
  (let loop ((nodes (.ref snapshot-value 'nodes)))
    (and (pair? nodes)
         (if (equal? (.ref (car nodes) 'identity) "obligation/test")
           (car nodes)
           (loop (cdr nodes))))))
(def (reported-outcome snapshot-value)
  (assurance-verifier-outcome
   "outcome/test" 'succeeded
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   obligation: "obligation/test" subject: release-subject
   scope: "repository" snapshot-revision: "r1"
   snapshot-context-digest: (.ref snapshot-value 'context-digest)
   inputs: (list (assurance-verifier-input artifact))
   output-digest: digest-b))
(def (make-host source governance-reader: (governance-reader #f))
  (assurance-verification-host
   "host/decision-preflight"
   (lambda (subject-value issued-at expires-at) #t)
   (lambda () 11) 9 source governance-reader: governance-reader))
(def handoff
  (agentic-ai-lab-cedar-runtime-handoff
   1 #u8(1 2 3) digest-a digest-a digest-b digest-b))

(def (make-cedar-delivery-fixture governance-reader)
  (let* ((snapshot-value (bound-cut relations))
         (host (make-host (lambda () snapshot-value) governance-reader: governance-reader))
         (admission (assurance-host-admit
                     host (bound-obligation snapshot-value) evidence (reported-outcome snapshot-value)))
         (preflight (assurance-host-preflight-decision host decision claim (list admission))))
    (values host (assurance-host-cedar-request host preflight "Action::\"release\"" digest-a handoff))))

(def decision-preflight-test
  (test-suite "Host Decision preflight is not authorization"
    (test-case "exact undecided Decision and support issue one Host preflight"
      (let* ((snapshot-value (bound-cut relations))
             (host (make-host (lambda () snapshot-value)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot-value) evidence
               (reported-outcome snapshot-value)))
             (preflight
              (assurance-host-preflight-decision
               host decision claim (list admission)))
             (other-host (make-host (lambda () snapshot-value))))
        (check-equal? (assurance-decision-preflight? preflight) #t)
        (check-equal? (.ref preflight 'release-authorized?) #f)
        (check-equal?
         (assurance-decision-preflight?
          (.o (:: @ preflight) release-authorized?: #t)) #f)
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #t)
        (check-equal?
         (assurance-host-decision-preflight-current?
          host (.o (:: @ preflight))) #f)
        (check-equal?
         (assurance-host-decision-preflight-current?
          other-host preflight) #f)
        (check-equal?
         (assurance-host-preflight-decision
          host (.o (:: @ decision) outcome: 'allow)
          claim (list admission)) #f)
        (check-equal?
         (assurance-host-preflight-decision host decision claim '()) #f)
        (assurance-host-revoke-admission! host admission)
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)))

    (test-case "missing Decision dependency cannot preflight"
      (let* ((snapshot-value
              (bound-cut (list evidence-link requirement-link)))
             (host (make-host (lambda () snapshot-value)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot-value) evidence
               (reported-outcome snapshot-value))))
        (check-equal?
         (assurance-host-preflight-decision
          host decision claim (list admission)) #f)))

    (test-case "only a current Host preflight projects an inert Cedar request"
      (let* ((snapshot-value (bound-cut relations))
             (host (make-host (lambda () snapshot-value)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot-value) evidence
               (reported-outcome snapshot-value)))
             (preflight
              (assurance-host-preflight-decision
               host decision claim (list admission)))
             (request
              (assurance-host-cedar-request
               host preflight "Release" digest-a handoff))
             (other-host (make-host (lambda () snapshot-value)))
             (runtime-value
              (agentic-ai-lab-cedar-authorization-request->runtime request))
             (context-value (hash-get runtime-value "context")))
        (check-equal? (agentic-ai-lab-cedar-authorization-request? request) #t)
        (check-equal? (assurance-host-cedar-request-current? host request) #t)
        (check-equal?
         (assurance-host-cedar-request-current?
          host (.o (:: @ request))) #f)
        (check-equal?
         (assurance-host-cedar-request-current?
          host (.o (:: @ request) action: "Deploy")) #f)
        (check-equal?
         (assurance-host-cedar-request-current? other-host request) #f)
        (check-equal? (hash-get runtime-value "principal") release-authority)
        (check-equal? (hash-get runtime-value "resource") release-subject)
        (check-equal? (hash-get context-value "aitia_preflight")
                      (.ref preflight 'identity))
        (check-equal? (hash-get context-value "aitia_policy") "policy/release")
        (check-equal? (hash-get context-value "aitia_preflight_only") #t)
        (check-equal? (hash-get context-value "agentic_ai_lab_preflight_only") #t)
        (check-equal?
         (assurance-host-cedar-request
          host (.o (:: @ preflight)) "Release" digest-a handoff) #f)
        (check-exception
         (assurance-host-cedar-request
          host preflight "Release" digest-a (.o)) Error?)
        (assurance-host-revoke-decision-preflight! host preflight)
        (check-equal?
         (assurance-host-cedar-request-current? host request) #f)
        (check-equal?
         (assurance-host-cedar-request
          host preflight "Release" digest-a handoff) #f)))

    (test-case "Cedar source lookup requires a separate live Governance admission"
      (let* ((snapshot-value (bound-cut relations))
             (approval #f)
             (key #f)
             (host (make-host (lambda () snapshot-value)
                     governance-reader:
                     (lambda (candidate original proposal)
                       (unless key (set! key candidate))
                       (and (equal? key candidate) approval))))
             (admission (assurance-host-admit
                         host (bound-obligation snapshot-value) evidence
                         (reported-outcome snapshot-value)))
             (preflight (assurance-host-preflight-decision host decision claim (list admission)))
             (request (assurance-host-cedar-request host preflight "Release" digest-a handoff))
             (policy-context (.o approved: #t blocked: #f)))
        (let-values (((proposal lookup)
                      (assurance-host-cedar-source-admission host request policy-context)))
          (check-equal? proposal #f)
          (check-equal? lookup #f))
        (set! approval digest-b)
        (let-values (((proposal lookup)
                      (assurance-host-cedar-source-admission host request policy-context)))
          (check-equal? (assurance-host-cedar-request-current? host proposal) #f)
          (let* ((projected (agentic-ai-lab-cedar-authorization-request->runtime proposal))
                 (context (hash-get projected "context"))
                 (initial (lookup)))
            (check-equal? (hash-get context "agentic_ai_lab_preflight_only") #t)
            (check-equal? (hash-get context "approved") #t)
            (check-equal? (hash-key? context "aitia_policy") #f)
            (check-equal? (hash-get projected "intent_digest") digest-a)
            (check-equal? (string? initial) #t)
            (let-values (((substitute resolve)
                          (assurance-host-cedar-source-admission
                           host request (.o approved: #f blocked: #f))))
              (check-equal? substitute #f)
              (check-equal? resolve #f))
            (let-values (((copy resolve)
                          (assurance-host-cedar-source-admission
                           host (.o (:: @ request)) policy-context)))
              (check-equal? copy #f)
              (check-equal? resolve #f))
            (set! approval #f)
            (check-equal? (lookup) #f)
            (set! approval digest-b)
            (check-equal? (lookup) #f)
            (let-values (((fresh resolve)
                          (assurance-host-cedar-source-admission host request policy-context)))
              (check-equal? (agentic-ai-lab-cedar-authorization-request? fresh) #t)
              (check-equal? (equal? (resolve) initial) #f)
              (assurance-host-revoke-admission! host admission)
              (check-equal? (resolve) #f))))))

    (test-case "source change and rollback cannot revive a preflight"
      (let* ((current (bound-cut relations))
             (host (make-host (lambda () current)))
             (admission
              (assurance-host-admit
               host (bound-obligation current) evidence
               (reported-outcome current)))
             (preflight
              (assurance-host-preflight-decision
               host decision claim (list admission)))
             (request
              (assurance-host-cedar-request
               host preflight "Release" digest-a handoff))
             (old-cut current))
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #t)
        (check-equal?
         (assurance-host-cedar-request-current? host request) #t)
        (set! current
              (construct (bound-obligation old-cut) relations "event-cut/2"))
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)
        (check-equal?
         (assurance-host-cedar-request-current? host request) #f)
        (set! current old-cut)
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)
        (check-equal?
         (assurance-host-cedar-request-current? host request) #f)))

    (test-case "explicit preflight revocation is separate from evidence"
      (let* ((snapshot-value (bound-cut relations))
             (host (make-host (lambda () snapshot-value)))
             (admission
              (assurance-host-admit
               host (bound-obligation snapshot-value) evidence
               (reported-outcome snapshot-value)))
             (preflight
              (assurance-host-preflight-decision
               host decision claim (list admission))))
        (assurance-host-revoke-decision-preflight! host preflight)
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)
        (check-equal?
         (assurance-host-admission-current? host admission) #t)))))
