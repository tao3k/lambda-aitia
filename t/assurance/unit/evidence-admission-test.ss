;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/error Error?)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify
                 poo-flow-revoke-verification!)
        :poo-flow/lambda-aitia/modules/assurance/interface)

(export evidence-admission-test)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def artifact
  (assurance-artifact "artifact/source" "r1" 'supported digest-a
                      owner: "maintainer" media-kind: 'scheme-source))
(def claim
  (assurance-claim "claim/release" "r1" 'unknown digest-b
                   subject: "software/release" predicate: "release-ready"
                   scope: "repository" valid-from: "2026-09-23"))
(def obligation
  (assurance-obligation
   "obligation/test" "r1" 'unknown digest-a
   subject: "software/release" claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: 'gerbil-test scope: "repository"))
(def (make-snapshot artifact-value obligation-value (revision "r1"))
  (assurance-snapshot
   "snapshot/software" revision "graph/software"
   (list (cons "artifact/source" (.ref artifact-value 'revision)))
   '(("claim/release" . "r1"))
   "event-cut/1" "policy/release" "r1"
   (list artifact-value claim obligation-value) '()))
(def draft (make-snapshot artifact obligation))
(def bound-obligation (assurance-bind-obligation-to-snapshot obligation draft))
(def snapshot (make-snapshot artifact bound-obligation))
(def outcome
  (assurance-verifier-outcome
   "outcome/test" 'succeeded
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   obligation: "obligation/test" subject: "software/release"
   scope: "repository" snapshot-revision: "r1"
   snapshot-context-digest: (.ref snapshot 'context-digest)
   inputs: (list (assurance-verifier-input artifact))
   output-digest: digest-b))
(def trusted-evidence
  (assurance-evidence
   "evidence/test" "r1" 'supported digest-b
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   input-artifacts: '("artifact/source") obligation: "obligation/test"
   subject: "software/release" scope: "repository"
   valid-from: "2026-09-23" admission-state: 'admitted))
(def trusted-discharge
  (assurance-relation "relation/discharge" 'assurance 'discharges
                      "evidence/test" "obligation/test" 'observed))
(def (make-trusted-snapshot obligation-value)
  (assurance-snapshot
   "snapshot/software" "r1" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
   "event-cut/1" "policy/release" "r1"
   (list artifact claim obligation-value trusted-evidence)
   (list trusted-discharge)
   evidence-identities: '("evidence/test")))
(def trusted-draft (make-trusted-snapshot obligation))
(def trusted-obligation
  (assurance-bind-obligation-to-snapshot obligation trusted-draft))
(def trusted-snapshot (make-trusted-snapshot trusted-obligation))
(def trusted-outcome
  (.o (:: @ outcome)
      snapshot-context-digest: (.ref trusted-snapshot 'context-digest)))
(def trusted-adapter
  (poo-flow-verification-adapter
   "host/native-test"
   (lambda (subject-value now until)
     (and (eq? (.ref (.ref subject-value 'outcome) 'status) 'succeeded)
          (equal? (.ref (.ref subject-value 'evidence) 'content-digest)
                  digest-b)))
   assurance-verification-subject-snapshot))
(def trusted-subject
  (assurance-verification-subject
   trusted-snapshot trusted-obligation trusted-evidence trusted-outcome))
(def trusted-receipt
  (poo-flow-verify trusted-adapter trusted-subject 10 20))
(def untrusted-adapter
  (poo-flow-verification-adapter
   "other/native-test"
   (lambda (subject-value now until) #t)
   assurance-verification-subject-snapshot))
(def (verified-support relation-value evidence-value obligation-value
                       snapshot-value outcome-value receipt-value now-value)
  (assurance-support-sealed-under-adapter?
   relation-value evidence-value obligation-value snapshot-value outcome-value
   trusted-adapter receipt-value now-value))
(def (blocker snapshot-value obligation-value outcome-value)
  (.ref (assurance-evaluate-evidence-admission
         snapshot-value obligation-value outcome-value)
        'blocker))

(def evidence-admission-test
  (test-suite "evidence admission eligibility"
    (test-case "bound success is eligible but does not admit or authorize"
      (let (receipt
            (assurance-evaluate-evidence-admission
             snapshot bound-obligation outcome))
        (check-equal? (assurance-evidence-admission-receipt? receipt) #t)
        (check-equal? (.ref receipt 'eligible?) #t)
        (check-equal? (.ref receipt 'verifier-executed?) #f)
        (check-equal? (.ref receipt 'release-authorized?) #f)
        (check-equal? (.ref receipt 'snapshot-digest) (.ref snapshot 'digest))
        (check-equal?
         (.ref receipt 'digest)
         (.ref (assurance-evaluate-evidence-admission
                snapshot bound-obligation outcome)
               'digest))
        (check-equal?
         (equal? (.ref receipt 'digest)
                 (.ref (assurance-evaluate-evidence-admission
                        snapshot bound-obligation
                        (.o (:: @ outcome) output-digest: digest-a))
                       'digest))
         #f)))

    (test-case "non-success statuses are typed, not green"
      (for-each
       (lambda (reported-status)
         (check-equal?
          (blocker snapshot bound-obligation
                   (.o (:: @ outcome) status: reported-status))
          'outcome-not-successful))
       '(failed timed-out unavailable indeterminate)))

    (test-case "green exit without output and bound inputs is rejected"
      (check-equal?
       (blocker snapshot bound-obligation
                (.o (:: @ outcome) output-digest: #f))
       'missing-output)
      (check-equal?
       (blocker snapshot bound-obligation
                (.o (:: @ outcome) inputs: '()))
       'missing-inputs)
      (check-equal?
       (blocker snapshot bound-obligation
                (.o (:: @ outcome)
                    inputs: (list (assurance-verifier-input artifact)
                                  (assurance-verifier-input artifact))))
       'duplicate-inputs))

    (test-case "changed source revision and digest invalidate old result"
      (let* ((new-artifact
              (.o (:: @ artifact) revision: "r2" content-digest: digest-b))
             (new-draft (make-snapshot new-artifact obligation "r2"))
             (new-obligation
              (assurance-bind-obligation-to-snapshot obligation new-draft))
             (new-snapshot (make-snapshot new-artifact new-obligation "r2")))
        (check-equal?
         (blocker new-snapshot bound-obligation outcome)
         'stale-obligation)
        (check-equal?
         (blocker new-snapshot new-obligation
                  (.o (:: @ outcome)
                      snapshot-revision: "r2"
                      snapshot-context-digest:
                      (.ref new-snapshot 'context-digest)))
         'input-binding-mismatch)))

    (test-case "same revision with changed artifact digest is not reusable"
      (let* ((new-artifact (.o (:: @ artifact) content-digest: digest-b))
             (new-draft (make-snapshot new-artifact obligation))
             (new-obligation
              (assurance-bind-obligation-to-snapshot obligation new-draft))
             (new-snapshot (make-snapshot new-artifact new-obligation)))
        (check-equal?
         (blocker new-snapshot new-obligation outcome)
         'outcome-binding-mismatch)
        (check-equal?
         (blocker new-snapshot new-obligation
                  (.o (:: @ outcome)
                      snapshot-context-digest:
                      (.ref new-snapshot 'context-digest)))
         'input-binding-mismatch)))

    (test-case "same revision with forged obligation semantics is stale"
      (check-equal?
       (blocker snapshot
                (.o (:: @ bound-obligation) subject: "software/other")
                outcome)
       'stale-obligation))

    (test-case "conflicting snapshot never accepts a reported success"
      (let (conflicted
            (assurance-snapshot
             "snapshot/software" "r1" "graph/software"
             '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
             "event-cut/1" "policy/release" "r1"
             (list artifact
                   (.o (:: @ artifact) content-digest: digest-b)
                   claim bound-obligation)
             '()))
        (check-equal?
         (blocker conflicted bound-obligation outcome)
         'snapshot-conflicted)))

    (test-case "outcome cannot retarget subject, scope or snapshot"
      (check-equal?
       (blocker snapshot bound-obligation
                (.o (:: @ outcome) subject: "software/other"))
       'outcome-binding-mismatch)
      (check-equal?
       (blocker snapshot bound-obligation
                (.o (:: @ outcome) snapshot-revision: "r0"))
       'outcome-binding-mismatch))

    (test-case "human review names authority and exact scope"
      (let* ((human-obligation
              (.o (:: @ obligation) evidence-kind: 'human-review))
             (human-draft (make-snapshot artifact human-obligation))
             (human-bound
              (assurance-bind-obligation-to-snapshot human-obligation human-draft))
             (human-snapshot (make-snapshot artifact human-bound))
             (human-outcome
              (.o (:: @ outcome)
                  snapshot-context-digest:
                  (.ref human-snapshot 'context-digest))))
        (check-equal?
         (blocker human-snapshot human-bound human-outcome)
         'human-authority-missing)
        (check-equal?
         (blocker human-snapshot human-bound
                  (.o (:: @ human-outcome)
                      accountable-authority: "maintainer"
                      review-scope: "repository"))
         #f)))

    (test-case "support requires a sealed execution receipt"
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome #f 11)
       #f)
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome trusted-receipt 11)
       #t))

    (test-case "copied seal and presentation mutation cannot forge support"
      (check-equal?
       (assurance-support-sealed-under-adapter?
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome
        (.o identity: "host/native-test"
            admits?: (lambda (receipt-value subject-value now-value) #t))
        trusted-receipt 11)
       #f)
      (check-equal?
       (assurance-support-sealed-under-adapter?
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome
        (.o (:: @ trusted-adapter)) trusted-receipt 11)
       #f)
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome
        (.o (:: @ trusted-receipt)) 11)
       #f)
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        (.o (:: @ trusted-snapshot) state: 'supported)
        trusted-outcome trusted-receipt 11)
       #f)
      (check-equal?
       (verified-support
        trusted-discharge
        (.o (:: @ trusted-evidence) tool-version: "v20")
        trusted-obligation trusted-snapshot trusted-outcome
        trusted-receipt 11)
       #f)
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot
        (.o (:: @ trusted-outcome) tool-version: "v20")
        trusted-receipt 11)
       #f)
      (check-equal?
       (assurance-support-sealed-under-adapter?
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome untrusted-adapter
       trusted-receipt 11)
       #f))

    (test-case "configured Host owns adapter, clock and revocation"
      (let* ((now 11)
             (host
              (assurance-verification-host
               "host/assurance-test"
               (lambda (subject-value issued-at expires-at)
                 (and (eq? (.ref (.ref subject-value 'outcome) 'status)
                           'succeeded)
                      (equal? (.ref (.ref subject-value 'evidence)
                                    'content-digest)
                              digest-b)))
               (lambda () now) 9))
             (receipt
              (assurance-host-verify
               host trusted-snapshot trusted-obligation trusted-evidence
               trusted-outcome)))
        (check-equal? (if receipt #t #f) #t)
        (check-equal?
         (assurance-host-verify
          host trusted-snapshot trusted-obligation
          (.o (:: @ trusted-evidence) tool-version: "v20")
          trusted-outcome)
         #f)
        (check-equal?
         (assurance-host-sealed-support?
          host trusted-discharge trusted-evidence trusted-obligation
         trusted-snapshot trusted-outcome receipt)
         #t)
        (check-exception
         (assurance-host-sealed-support?
          (.o (:: @ host)) trusted-discharge trusted-evidence
          trusted-obligation trusted-snapshot trusted-outcome receipt)
         Error?)
        (check-exception
         (assurance-host-sealed-support?
          (.o identity: "host/assurance-test")
          trusted-discharge trusted-evidence trusted-obligation
          trusted-snapshot trusted-outcome receipt)
         Error?)
        (check-equal?
         (assurance-host-verify
          host trusted-snapshot trusted-obligation trusted-evidence
          (.o (:: @ trusted-outcome) status: 'failed))
         #f)
        (set! now 20)
        (check-equal?
         (assurance-host-sealed-support?
          host trusted-discharge trusted-evidence trusted-obligation
          trusted-snapshot trusted-outcome receipt)
         #f)
        (set! now 11)
        (check-exception
         (assurance-host-sealed-support?
          host trusted-discharge trusted-evidence trusted-obligation
          trusted-snapshot trusted-outcome receipt)
         Error?))
      (let* ((host
              (assurance-verification-host
               "host/revocation-test"
               (lambda (subject-value issued-at expires-at) #t)
               (lambda () 11) 9))
             (receipt
              (assurance-host-verify
               host trusted-snapshot trusted-obligation trusted-evidence
               trusted-outcome)))
        (check-equal?
         (assurance-host-sealed-support?
          host trusted-discharge trusted-evidence trusted-obligation
          trusted-snapshot trusted-outcome receipt)
         #t)
        (assurance-host-revoke! host receipt)
        (check-equal?
         (assurance-host-sealed-support?
          host trusted-discharge trusted-evidence trusted-obligation
         trusted-snapshot trusted-outcome receipt)
         #f)))

    (test-case "configured verifier refusal never issues a seal"
      (let (host
            (assurance-verification-host
             "host/refusal-test"
             (lambda (subject-value issued-at expires-at) #f)
             (lambda () 11) 9))
        (check-equal?
         (assurance-host-verify
          host trusted-snapshot trusted-obligation trusted-evidence
          trusted-outcome)
         #f)))

    (test-case "expiry and revocation remove verified support"
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome trusted-receipt 20)
       #f)
      (poo-flow-revoke-verification! trusted-adapter trusted-receipt)
      (check-equal?
       (verified-support
        trusted-discharge trusted-evidence trusted-obligation
        trusted-snapshot trusted-outcome trusted-receipt 11)
       #f))))
