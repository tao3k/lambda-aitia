;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Integration proof for ADR 0009 / RFC 0006 three-layer dependency inversion
;;; and ROADMAP Phase 8 second-regime generalization:
;;; - A user Project composes DE-shaped POO engineering definitions and a custom
;;;   non-NASA ReplayProfile with AITIA's domain-neutral Assurance kernel.
;;; - AITIA never imports DE; DE definitions enter purely as POO values.
;;; - User-project evidence never transfers to AITIA framework self-checks.
;;; - Cross-language Rust+Python composition requires its own direct obligation.
(import :std/test
        (only-in :clan/poo/object .get .o .cc)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))

(export de-project-composition-test)

(def assurance (.get (.get lambda-aitia.init.exports modules) assurance))

;; A DE-style external engineering profile supplied by a user Project (no NASA
;; or GitHub dependency; pure POO value injection).
(def DeRustResourceReplayProfile
  (.o identity: "de/rust-resource-lifecycle"
      source-prefix: "services/rust-worker/"
      paths: '("services/rust-worker/src/pool.rs"
               "services/rust-worker/tests/cancellation.rs")
      cases: '(("bounded-drain-check"
                "tests/cancellation.rs::drain_completes_under_budget"
                "passed" #f))
      deployment-claim: "claim/de-rust-worker-bounded-drain"
      deployment-snapshot: "de/rust-worker/deployment"
      deployment-predicate: "All spawned worker tasks drain within the declared shutdown budget"
      provider-assumption: "assumption/de-tokio-runtime-fair-poll"
      provider-assumption-premise: '(runtime-polls-cancellation-tokens-before-drop)
      conditions:
      '(("bounded-drain-check" integration-test rust-worker-drain
          "Verify graceful task drain under cancellation and timeout.")
        ("runtime-fairness-review" human-review assumption-review
          "Review executor cancellation fairness assumption."))))

(def de-project-composition-test
  (test-suite "DE dependency inversion and second-regime generalization"
    (test-case "Assurance replay-profile admits a Project-injected non-NASA POO profile"
      (let* ((resolve-profile (.get assurance replay-profile))
             (resolved (resolve-profile DeRustResourceReplayProfile))
             (matches? (.get assurance replay-observation-matches?))
             (assess-deployment (.get assurance assess-replay-deployment))
             (deployment (assess-deployment
                          DeRustResourceReplayProfile
                          "user-project/rust-worker"
                          "op-1" "rev-1"
                          "services/rust-worker/tests/cancellation.rs::drain_completes_under_budget"))
             (assessment (.get deployment assessment)))
        (check-equal? (.get resolved identity) "de/rust-resource-lifecycle")
        (check-equal? (matches? DeRustResourceReplayProfile
                                "services/rust-worker/tests/cancellation.rs::drain_completes_under_budget"
                                "bounded-drain-check" 'passed #f)
                      #t)
        ;; Deployment assessment stays incomplete and never authorizes release
        ;; until independent Host evidence discharges every declared condition.
        (check-equal? (.get assessment complete?) #f)
        (check-equal? (.get assessment release-authorized?) #f)
        (check-equal? (length (.get deployment conditions)) 2)))

    (test-case "Framework self-checks and user-project claims stay isolated across invalidation"
      (let* ((digest (.get assurance digest))
             (artifact (.get assurance artifact))
             (claim (.get assurance claim))
             (obligation (.get assurance obligation))
             (relation (.get assurance relation))
             (snapshot-fn (.get assurance snapshot))
             (bind-ob (.get assurance bind-obligation))
             (invalidate (.get assurance invalidate))
             (derive-comp (.get assurance derive-composition))
             (d-rust (digest '(rust-worker-src v1)))
             (d-py (digest '(python-bridge-src v1)))
             (d-fw (digest '(aitia-runtime-src v1)))
             (d-comp (digest '(ffi-composition-claim v1)))
             (a-rust (artifact "art/rust-worker" "r1" 'supported d-rust
                               owner: "user-project" media-kind: 'source))
             (a-py (artifact "art/python-bridge" "r1" 'supported d-py
                             owner: "user-project" media-kind: 'source))
             (a-fw (artifact "art/aitia-executor" "r1" 'supported d-fw
                             owner: "lambda-aitia" media-kind: 'source))
             (c-rust (claim "claim/rust-drain" "r1" 'unknown d-rust
                            subject: "user-project/rust-worker"
                            predicate: "Rust worker drains within budget"
                            scope: "services/rust-worker" valid-from: "op-1"
                            support-requirements: '("ob/rust-drain")))
             (c-py (claim "claim/python-cleanup" "r1" 'unknown d-py
                          subject: "user-project/python-bridge"
                          predicate: "Python context managers close on cancel"
                          scope: "services/python-bridge" valid-from: "op-1"
                          support-requirements: '("ob/python-cleanup")))
             (c-ffi (claim "claim/rust-python-ffi" "r1" 'unknown d-comp
                           subject: "user-project/ffi"
                           predicate: "Cross-language FFI lifetime and cancellation safety"
                           scope: "services/ffi" valid-from: "op-1"))
             (c-fw (claim "claim/aitia-executor-drain" "r1" 'unknown d-fw
                          subject: "lambda-aitia/executor"
                          predicate: "AITIA framework executor drains subprocesses"
                          scope: "rust/crates/aitia-runtime" valid-from: "op-1"
                          support-requirements: '("ob/fw-drain")))
             (ob-rust (obligation "ob/rust-drain" "r1" 'unknown d-rust
                                  subject: "user-project/rust-worker" claim: "claim/rust-drain"
                                  snapshot: "snap/de-case" evidence-kind: 'integration-test
                                  capability: 'cargo-test scope: "services/rust-worker"))
             (ob-py (obligation "ob/python-cleanup" "r1" 'unknown d-py
                                subject: "user-project/python-bridge" claim: "claim/python-cleanup"
                                snapshot: "snap/de-case" evidence-kind: 'replay
                                capability: 'pytest scope: "services/python-bridge"))
             (ob-fw (obligation "ob/fw-drain" "r1" 'unknown d-fw
                                subject: "lambda-aitia/executor" claim: "claim/aitia-executor-drain"
                                snapshot: "snap/de-case" evidence-kind: 'integration-test
                                capability: 'cargo-test scope: "rust/crates/aitia-runtime"))
             (rels (list (relation "rel/rust-src" 'structural 'depends-on "claim/rust-drain" "art/rust-worker" 'declared)
                         (relation "rel/py-src" 'structural 'depends-on "claim/python-cleanup" "art/python-bridge" 'declared)
                         (relation "rel/fw-src" 'structural 'depends-on "claim/aitia-executor-drain" "art/aitia-executor" 'declared)
                         (relation "rel/ob-rust" 'assurance 'supports "ob/rust-drain" "claim/rust-drain" 'declared)
                         (relation "rel/ob-py" 'assurance 'supports "ob/python-cleanup" "claim/python-cleanup" 'declared)
                         (relation "rel/ob-fw" 'assurance 'supports "ob/fw-drain" "claim/aitia-executor-drain" 'declared)
                         (relation "rel/ffi-rust" 'structural 'composes "claim/rust-python-ffi" "claim/rust-drain" 'declared)
                         (relation "rel/ffi-py" 'structural 'composes "claim/rust-python-ffi" "claim/python-cleanup" 'declared)))
             (make-snap (lambda (obs)
                          (snapshot-fn "snap/de-case" "cut-1" "graph/de-case"
                                       '(("art/rust-worker" . "r1")
                                         ("art/python-bridge" . "r1")
                                         ("art/aitia-executor" . "r1"))
                                       '(("claim/rust-drain" . "r1")
                                         ("claim/python-cleanup" . "r1")
                                         ("claim/rust-python-ffi" . "r1")
                                         ("claim/aitia-executor-drain" . "r1"))
                                       "op-1" "de/multi-language-policy" d-comp
                                       (append (list a-rust a-py a-fw c-rust c-py c-ffi c-fw) obs)
                                       rels)))
             (draft (make-snap (list ob-rust ob-py ob-fw)))
             (snap (make-snap (map (lambda (ob) (bind-ob ob draft)) (list ob-rust ob-py ob-fw))))
             (receipt (invalidate "inv/de-python-change" snap '("art/python-bridge")))
             (ref (.get assurance invalidation-receipt-ref))
             (impacted (ref receipt 'impacted))
             (comp (derive-comp "comp/de-ffi" snap))
             (req (car (.get comp requirements))))
        ;; Changing the Python project source impacts the Python claim and the
        ;; composite FFI claim, NOT the unrelated AITIA framework executor claim.
        (check (and (member "claim/python-cleanup" impacted) #t) => #t)
        (check (and (member "claim/rust-python-ffi" impacted) #t) => #t)
        (check (member "claim/aitia-executor-drain" impacted) => #f)
        (check-equal? (ref receipt 'release-authorized?) #f)
        ;; Component obligations alone cannot discharge the composite FFI claim:
        ;; derive-composition demands an independent direct obligation on claim/rust-python-ffi.
        (check-equal? (.get comp release-authorized?) #f)
        (check-equal? (length (.get comp requirements)) 1)
        (check-equal? (.get req composition-claim) "claim/rust-python-ffi")
        (check-equal? (.get req direct-obligations) '())
        (check (symbol? (.get req blocker)) => #t)))))
