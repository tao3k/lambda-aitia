;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/error Error?)
        (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface)

(export assurance-kernel-test)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def artifact
  (assurance-artifact "artifact/source" "r1" 'supported digest-a
                      owner: "lambda-aitia" media-kind: 'scheme-source
                      provenance: '("source/repository")))
(def claim
  (assurance-claim "claim/release" "r1" 'unknown digest-b
                   subject: "software/release" predicate: "release-ready"
                   assumptions: '("assumption/toolchain")
                   support-requirements: '("obligation/verify")
                   scope: "repository" valid-from: "2026-09-17"))
(def obligation
  (assurance-obligation
   "obligation/verify" "r1" 'unknown digest-a
   subject: "software/release" claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: 'gerbil-test scope: "repository"))
(def evidence
  (assurance-evidence
   "evidence/test" "r1" 'supported digest-b
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   input-artifacts: '("artifact/source") obligation: "obligation/verify"
   subject: "software/release" scope: "repository"
   valid-from: "2026-09-17" admission-state: 'admitted))
(def decision
  (assurance-decision
   "decision/release" "r1" 'unknown digest-a
   subject: "software/release" snapshot: "snapshot/software"
   policy: "policy/release" authority: "maintainer" outcome: 'unknown))
(def effect
  (assurance-effect
   "effect/deploy" "r1" 'unknown digest-b
   subject: "software/release" decision: "decision/release"
   effect-kind: 'deploy effect-state: 'blocked))
(def dependency
  (assurance-relation "relation/depends" 'structural 'depends-on
                      "claim/release" "artifact/source" 'declared))
(def discharge
  (assurance-relation "relation/discharges" 'assurance 'discharges
                      "evidence/test" "obligation/verify" 'observed))
(def obligation-support
  (assurance-relation "relation/obligation-support" 'assurance 'supports
                      "obligation/verify" "claim/release" 'declared))
(def decision-dependency
  (assurance-relation "relation/decision-dependency" 'structural 'depends-on
                      "decision/release" "claim/release" 'declared))
(def authorization
  (assurance-relation "relation/authorization" 'authority 'authorizes
                      "decision/release" "effect/deploy" 'declared))

(def (software-snapshot nodes relations (unresolved '()))
  (assurance-snapshot
   "snapshot/software" "r1" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
   "event-cut/1" "policy/release" "r1" nodes relations
   evidence-identities: '("evidence/test") unresolved: unresolved))
(def full-software-snapshot
  (software-snapshot
   (list artifact claim obligation evidence decision effect)
   (list dependency discharge obligation-support
         decision-dependency authorization)))

(def assurance-kernel-test
  (test-suite "Aitia POO-native assurance kernel"
    (test-case "nominal node identity is not granted by matching slots"
      (check-equal? (assurance-artifact? artifact) #t)
      (check-equal? (assurance-claim? artifact) #f)
      (check-equal?
       (assurance-artifact?
        (.o identity: "artifact/source" kind: 'artifact revision: "r1"
            state: 'supported content-digest: digest-a))
       #f)
      (check-equal? (assurance-artifact? (.o (:: @ artifact) kind: 'claim)) #f)
      (check-exception
       (assurance-artifact "artifact/source" "" 'supported digest-a
                           owner: "lambda-aitia" media-kind: 'scheme-source)
       Error?)
      (check-exception
       (assurance-evidence
        "evidence/bad" "r1" 'supported digest-a
        producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
        input-artifacts: '("artifact/source") obligation: "obligation/verify"
        subject: "software/release" scope: ""
        valid-from: "2026-09-17" admission-state: 'admitted)
       Error?))

    (test-case "relation kinds cannot cross their owned plane"
      (check-equal? (assurance-relation? dependency) #t)
      (check-exception
       (assurance-relation "bad" 'causal 'depends-on
                           "claim/release" "artifact/source" 'declared)
       Error?)
      (check-equal?
       (assurance-relation? (.o (:: @ dependency) plane: 'authority)) #f))

    (test-case "canonical snapshots are stable under input permutation"
      (let ((left
             full-software-snapshot)
            (right
             (software-snapshot
              (list effect decision evidence obligation claim artifact)
              (list authorization decision-dependency obligation-support
                    discharge dependency))))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'state) 'unknown)
        (check-equal?
         (map (lambda (node) (.ref node 'identity)) (.ref left 'nodes))
         '("artifact/source" "claim/release" "decision/release"
           "effect/deploy" "evidence/test" "obligation/verify"))))

    (test-case "unequal duplicate identity is conflicted, never overwritten"
      (let ((snapshot
             (software-snapshot
              (list artifact
                    (assurance-artifact
                     "artifact/source" "r2" 'supported digest-b
                     owner: "lambda-aitia" media-kind: 'scheme-source))
              '())))
        (check-equal? (.ref snapshot 'state) 'conflicted)
        (check-equal? (.ref snapshot 'conflicts) '("artifact/source"))))

    (test-case "missing relation endpoints remain an unknown frontier"
      (let ((snapshot
             (software-snapshot (list claim) (list dependency))))
        (check-equal? (.ref snapshot 'state) 'unknown)
        (check-equal? (.ref snapshot 'unresolved) '("artifact/source"))))

    (test-case "alternate evidence and temporal order grant no support"
      (check-equal?
       (assurance-support-admissible? discharge evidence obligation) #t)
      (check-equal?
       (assurance-support-admissible?
        discharge (.o (:: @ evidence) state: 'hypothesized) obligation)
       #f)
      (check-equal?
       (assurance-support-admissible?
        (.o (:: @ discharge) modality: 'counterfactual)
        evidence obligation)
       #f)
      (check-equal?
       (assurance-support-admissible?
        (assurance-relation "relation/precedes" 'causal 'precedes
                            "evidence/test" "obligation/verify" 'observed)
       evidence obligation)
       #f))

    (test-case "change invalidation is deterministic and never grants authority"
      (let* ((receipt
              (assurance-invalidate
               "invalidation/requirement-r2" full-software-snapshot
               '("artifact/source"))))
        (check-equal? (assurance-invalidation-receipt? receipt) #t)
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'impacted)
         '("artifact/source" "claim/release" "decision/release"
           "effect/deploy" "evidence/test" "obligation/verify"))
        (check-equal? (assurance-invalidation-receipt-ref
                       receipt 'invalidated-evidence)
                      '("evidence/test"))
        (check-equal? (assurance-invalidation-receipt-ref
                       receipt 'required-obligations)
                      '("obligation/verify"))
        (check-equal? (assurance-invalidation-receipt-ref
                       receipt 'invalidated-decisions)
                      '("decision/release"))
        (check-equal? (assurance-invalidation-receipt-ref receipt 'blocked-effects)
                      '("effect/deploy"))
        (check-equal? (assurance-invalidation-receipt-ref receipt 'temporal-proven?) #f)
        (check-equal? (assurance-invalidation-receipt-ref receipt 'release-authorized?) #f)
        (check-equal? (assurance-invalidation-receipt-ref receipt 'runtime-executed?) #f)))))
