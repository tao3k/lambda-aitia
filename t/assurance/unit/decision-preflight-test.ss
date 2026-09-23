;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface)

(export decision-preflight-test)

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
(def decision
  (assurance-decision
   "decision/release" "r1" 'unknown digest-a
   subject: "software/release" snapshot: "snapshot/software"
   policy: "policy/release" authority: "maintainer" outcome: 'unknown))
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
   obligation: "obligation/test" subject: "software/release"
   scope: "repository" snapshot-revision: "r1"
   snapshot-context-digest: (.ref snapshot-value 'context-digest)
   inputs: (list (assurance-verifier-input artifact))
   output-digest: digest-b))
(def (make-host source)
  (assurance-verification-host
   "host/decision-preflight"
   (lambda (subject-value issued-at expires-at) #t)
   (lambda () 11) 9 source))

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
             (old-cut current))
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #t)
        (set! current
              (construct (bound-obligation old-cut) relations "event-cut/2"))
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)
        (set! current old-cut)
        (check-equal?
         (assurance-host-decision-preflight-current? host preflight) #f)))

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
