;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .o .ref)
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
         #f)))))
