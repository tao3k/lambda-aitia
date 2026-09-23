;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/error Error?)
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .ref)
        (only-in :poo-flow/src/module-system/contribution/verification
                 poo-flow-verification-adapter poo-flow-verify)
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
(def reverse-dependency
  (assurance-relation "relation/reverse-dependency" 'structural 'implements
                      "artifact/source" "claim/release" 'declared))

(def (verification-obligation id capability)
  (assurance-obligation
   id "r1" 'unknown digest-a
   subject: "software/release" claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: capability scope: "repository"))
(def (verification-support id)
  (assurance-relation
   (string-append "relation/support/" id) 'assurance 'supports
   id "claim/release" 'declared))
(def (verification-dependency source target)
  (assurance-relation
   (string-append "relation/depends/" source "/" target)
   'structural 'depends-on source target 'declared))
(def (verification-snapshot obligations relations)
  (software-snapshot
   (append (list artifact claim evidence) obligations)
   (append (list dependency) relations)))

(def (software-snapshot nodes relations (unresolved '()) (revision "r1"))
  (def (construct values)
    (assurance-snapshot
     "snapshot/software" revision "graph/software"
     '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
     "event-cut/1" "policy/release" "r1" values relations
     evidence-identities: '("evidence/test") unresolved: unresolved))
  (let* ((candidate (construct nodes))
         (bound-nodes
          (map (lambda (node)
                 (if (and (assurance-obligation? node)
                          (string=? (.ref node 'snapshot)
                                    (.ref candidate 'identity))
                          (not (.ref node 'snapshot-revision))
                          (not (.ref node 'snapshot-context-digest)))
                   (assurance-bind-obligation-to-snapshot node candidate)
                   node))
               nodes)))
    (construct bound-nodes)))
(def full-software-snapshot
  (software-snapshot
   (list artifact claim obligation evidence decision effect)
   (list dependency discharge obligation-support
         decision-dependency authorization)))
(def current-obligation
  (find (lambda (node)
          (and (assurance-obligation? node)
               (equal? (.ref node 'identity) "obligation/verify")))
        (.ref full-software-snapshot 'nodes)))
(def support-outcome
  (assurance-verifier-outcome
   "outcome/kernel" 'succeeded
   producer: "gxtest" tool: "gerbil-test" tool-version: "v19"
   obligation: "obligation/verify" subject: "software/release"
   scope: "repository"
   snapshot-revision: (.ref full-software-snapshot 'revision)
   snapshot-context-digest: (.ref full-software-snapshot 'context-digest)
   inputs: (list (assurance-verifier-input artifact))
   output-digest: digest-b))
(def support-adapter
  (poo-flow-verification-adapter
   "test/kernel-support" (lambda (subject-value now-value until-value) #t)
   assurance-verification-subject-snapshot))
(def support-receipt
  (poo-flow-verify
   support-adapter
   (assurance-verification-subject
    full-software-snapshot current-obligation evidence support-outcome)
   10 20))
(def (kernel-support? relation-value evidence-value)
  (assurance-support-admissible?
   relation-value evidence-value current-obligation full-software-snapshot
   support-outcome support-adapter support-receipt 11))

(def replacement-claim
  (assurance-claim
   "claim/release" "r2" 'unknown digest-b
   subject: "software/release" predicate: "release-ready-v2"
   assumptions: '("assumption/toolchain")
   support-requirements: '("obligation/verify-next")
   scope: "repository" valid-from: "2026-09-17"))
(def replacement-candidate
  (assurance-obligation
   "obligation/verify-next" "r2" 'unknown digest-a
   subject: "software/release" claim: "claim/release"
   snapshot: "snapshot/software" evidence-kind: 'native-test
   capability: 'gerbil-test scope: "repository"))
(def replacement-support
  (assurance-relation
   "relation/replacement-support" 'assurance 'supports
   "obligation/verify-next" "claim/release" 'declared))
(def (replacement-draft nodes relations)
  (assurance-snapshot
   "snapshot/software" "r2" "graph/software"
   '(("artifact/source" . "r1")) '(("claim/release" . "r2"))
   "event-cut/1" "policy/release" "r1"
   nodes relations))

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
      (check-equal?
       (assurance-relation?
        (assurance-relation
         "relation/composes" 'structural 'composes
         "claim/composite" "claim/component-a" 'declared))
       #t)
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
           "effect/deploy" "evidence/test" "obligation/verify"))
        (let ((left-receipt
               (assurance-invalidate
                "invalidation/permutation-left" left '("artifact/source")))
              (right-receipt
               (assurance-invalidate
                "invalidation/permutation-right" right '("artifact/source"))))
          (check-equal?
           (assurance-invalidation-receipt-ref left-receipt 'impacted)
           (assurance-invalidation-receipt-ref right-receipt 'impacted))
          (check-equal?
           (assurance-invalidation-receipt-ref left-receipt 'witnesses)
           (assurance-invalidation-receipt-ref right-receipt 'witnesses)))))

    (test-case "all revision and evidence bindings are canonical"
      (let ((left
             (assurance-snapshot
              "snapshot/bindings" "r1" "graph/software"
              '(("z" . "r2") ("a" . "r1"))
              '(("claim/z" . "r2") ("claim/a" . "r1"))
              "event-cut/1" "policy/release" "r1" '() '()
              evidence-identities: '("evidence/z" "evidence/a")))
            (right
             (assurance-snapshot
              "snapshot/bindings" "r1" "graph/software"
              '(("a" . "r1") ("z" . "r2"))
              '(("claim/a" . "r1") ("claim/z" . "r2"))
              "event-cut/1" "policy/release" "r1" '() '()
              evidence-identities: '("evidence/a" "evidence/z"))))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'source-revisions)
                      '(("a" . "r1") ("z" . "r2")))
        (check-equal? (.ref left 'evidence-identities)
                      '("evidence/a" "evidence/z"))))

    (test-case "conflicting revision bindings fail closed"
      (let (snapshot
            (assurance-snapshot
             "snapshot/conflict" "r1" "graph/software"
             '(("artifact/source" . "r1") ("artifact/source" . "r2"))
             '() "event-cut/1" "policy/release" "r1" '() '()))
        (check-equal? (.ref snapshot 'state) 'conflicted)
        (check-equal? (.ref snapshot 'conflicts) '("artifact/source"))))

    (test-case "snapshot bindings resolve exact node kinds and revisions"
      (let ((missing
             (assurance-snapshot
              "snapshot/missing-binding" "r1" "graph/software"
              '(("artifact/missing" . "r1")) '()
              "event-cut/1" "policy/release" "r1" '() '()))
            (wrong-revision
             (assurance-snapshot
              "snapshot/wrong-revision" "r1" "graph/software"
              '(("artifact/source" . "r2")) '()
              "event-cut/1" "policy/release" "r1" (list artifact) '()))
            (wrong-kind
             (assurance-snapshot
              "snapshot/wrong-kind" "r1" "graph/software"
              '(("claim/release" . "r1")) '()
              "event-cut/1" "policy/release" "r1" (list claim) '())))
        (check-equal? (.ref missing 'state) 'unknown)
        (check-equal? (.ref missing 'unresolved) '("artifact/missing"))
        (check-equal? (.ref wrong-revision 'state) 'conflicted)
        (check-equal? (.ref wrong-revision 'conflicts) '("artifact/source"))
        (check-equal? (.ref wrong-kind 'state) 'conflicted)
        (check-equal? (.ref wrong-kind 'conflicts) '("claim/release"))))

    (test-case "snapshot evidence identities require admitted evidence nodes"
      (let ((missing
             (assurance-snapshot
              "snapshot/missing-evidence" "r1" "graph/software"
              '() '() "event-cut/1" "policy/release" "r1" '() '()
              evidence-identities: '("evidence/missing")))
            (candidate
             (assurance-snapshot
              "snapshot/candidate-evidence" "r1" "graph/software"
              '() '() "event-cut/1" "policy/release" "r1"
              (list (.o (:: @ evidence) admission-state: 'candidate)) '()
              evidence-identities: '("evidence/test"))))
        (check-equal? (.ref missing 'state) 'unknown)
        (check-equal? (.ref missing 'unresolved) '("evidence/missing"))
        (check-equal? (.ref candidate 'state) 'conflicted)
        (check-equal? (.ref candidate 'conflicts) '("evidence/test"))))

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

    (test-case "missing relation endpoints and declared evidence remain unknown"
      (let ((snapshot
             (software-snapshot (list claim) (list dependency))))
        (check-equal? (.ref snapshot 'state) 'unknown)
        (check-equal? (.ref snapshot 'unresolved)
                      '("artifact/source" "evidence/test"))
        (let (receipt
              (assurance-invalidate
               "invalidation/dangling" snapshot '("claim/release")))
          (check-equal?
           (assurance-invalidation-receipt-ref receipt 'impacted)
           '("claim/release"))
          (check-equal?
           (assurance-invalidation-receipt-ref receipt 'unresolved)
           '("artifact/source" "evidence/test")))))

    (test-case "alternate evidence and temporal order grant no support"
      (check-equal?
       (kernel-support? discharge evidence) #t)
      (check-equal?
       (kernel-support?
        discharge (.o (:: @ evidence) state: 'hypothesized))
       #f)
      (check-equal?
       (kernel-support?
        (.o (:: @ discharge) modality: 'counterfactual)
        evidence)
       #f)
      (check-equal?
       (kernel-support?
        (assurance-relation "relation/precedes" 'causal 'precedes
                            "evidence/test" "obligation/verify" 'observed)
       evidence)
       #f))

    (test-case "candidate or mismatched evidence cannot discharge an obligation"
      (check-equal?
       (kernel-support?
        discharge (.o (:: @ evidence) admission-state: 'candidate))
       #f)
      (check-equal?
       (kernel-support?
        discharge (.o (:: @ evidence) obligation: "obligation/other"))
       #f)
      (check-equal?
       (kernel-support?
        discharge (.o (:: @ evidence) revision: "r2"))
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
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'witnesses)
         '(("artifact/source" ("artifact/source") ())
           ("claim/release"
            ("artifact/source" "claim/release") ("depends-on"))
           ("decision/release"
            ("artifact/source" "claim/release" "decision/release")
            ("depends-on" "depends-on"))
           ("effect/deploy"
            ("artifact/source" "claim/release" "decision/release"
             "effect/deploy")
            ("depends-on" "depends-on" "authorizes"))
           ("evidence/test"
            ("artifact/source" "claim/release" "obligation/verify"
             "evidence/test")
            ("depends-on" "supports" "discharges"))
           ("obligation/verify"
            ("artifact/source" "claim/release" "obligation/verify")
            ("depends-on" "supports"))))
        (check-equal? (assurance-invalidation-receipt-ref
                       receipt 'cyclic-components) '())
        (check-equal? (assurance-invalidation-receipt-ref receipt 'temporal-proven?) #f)
        (check-equal? (assurance-invalidation-receipt-ref receipt 'release-authorized?) #f)
        (check-equal? (assurance-invalidation-receipt-ref receipt 'runtime-executed?) #f)))

    (test-case "causal relations never participate in structural invalidation"
      (let* ((causal
              (assurance-relation "relation/causal" 'causal 'enables
                                  "artifact/source" "effect/deploy" 'declared))
             (snapshot
              (software-snapshot (list artifact effect) (list causal)))
             (receipt
              (assurance-invalidate "invalidation/causal" snapshot
                                    '("artifact/source"))))
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'impacted)
         '("artifact/source"))))

    (test-case "unknown change identities remain an unresolved frontier"
      (let (receipt
            (assurance-invalidate
             "invalidation/unknown-change" full-software-snapshot
             '("artifact/missing")))
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'changed)
         '("artifact/missing"))
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'impacted) '())
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'unresolved)
         '("artifact/missing"))
        (check-equal?
         (assurance-invalidation-receipt-ref receipt 'release-authorized?) #f)))

    (test-case "fixed-snapshot invalidation is monotone"
      (let ((claim-change
             (assurance-invalidate
              "invalidation/claim" full-software-snapshot
              '("claim/release")))
            (artifact-change
             (assurance-invalidate
              "invalidation/artifact" full-software-snapshot
              '("artifact/source"))))
        (check-equal?
         (assurance-invalidation-receipt-ref claim-change 'impacted)
         '("claim/release" "decision/release" "effect/deploy"
           "evidence/test" "obligation/verify"))
        (check-equal?
         (assurance-invalidation-receipt-ref artifact-change 'impacted)
         (cons "artifact/source"
               (assurance-invalidation-receipt-ref claim-change 'impacted)))))

    (test-case "verification selection is pure and permutation-stable"
      (let* ((policy
             (assurance-verification-policy
               "policy/release" "r1" '(lean gerbil-test gerbil-test)))
             (permuted-policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test lean)))
             (permuted
              (software-snapshot
               (list effect decision evidence obligation claim artifact)
               (list authorization decision-dependency obligation-support
                     discharge dependency)))
             (left
              (assurance-plan-verification
               "plan/release" full-software-snapshot
               '("artifact/source") policy))
             (right
              (assurance-plan-verification
               "plan/release" permuted
               '("artifact/source") permuted-policy)))
        (check-equal? (assurance-verification-policy? policy) #t)
        (check-equal? (.ref policy 'capabilities) '(gerbil-test lean))
        (check-equal? (assurance-verification-plan? left) #t)
        (check-equal? (.ref left 'schema) "lambda-aitia.planning-result")
        (check-equal?
         (.ref obligation 'snapshot-context-digest) #f)
        (check-equal?
         (.ref (car (filter assurance-obligation?
                            (.ref full-software-snapshot 'nodes)))
               'snapshot-context-digest)
         (.ref full-software-snapshot 'context-digest))
        (check-equal? (.ref left 'selected-obligations)
                      '("obligation/verify"))
        (check-equal? (.ref left 'blocked-obligations) '())
        (check-equal?
         (assurance-verification-request? (car (.ref left 'requests))) #t)
        (check-equal? (.ref (car (.ref left 'requests)) 'capability)
                      'gerbil-test)
        (check-equal? (.ref (car (.ref left 'requests)) 'selected?) #t)
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'verifier-executed?) #f)
        (check-equal? (.ref left 'release-authorized?) #f)
        (check-equal? (.ref left 'runtime-executed?) #f)
        (check-equal? (.ref left 'blocked-effects) '("effect/deploy"))
        (check-equal? (car (.ref left 'witnesses))
                      '("artifact/source" ("artifact/source") ()))
        (check-equal?
         (assurance-verification-request?
          (.o (:: @ (car (.ref left 'requests)))
              blocker: 'capability-unavailable))
         #f)
        (check-equal?
         (assurance-verification-plan?
         (.o (:: @ left) release-authorized?: #t))
         #f)))

    (test-case "replacement requirements never silently rebind an old obligation"
      (let* ((target
              (software-snapshot
               (list artifact claim evidence) (list dependency) '() "r2"))
             (permuted-source
              (software-snapshot
               (list effect decision evidence obligation claim artifact)
               (list authorization decision-dependency obligation-support
                     discharge dependency)))
             (left
              (assurance-derive-replacement-requirements
               "replacement/source" full-software-snapshot target
               '("artifact/source")))
             (right
              (assurance-derive-replacement-requirements
               "replacement/source" permuted-source target
               '("artifact/source")))
             (requirement (car (.ref left 'requirements)))
             (unchanged
              (assurance-derive-replacement-requirements
               "replacement/unchanged" full-software-snapshot
               full-software-snapshot '("artifact/source")))
             (unknown-change
              (assurance-derive-replacement-requirements
               "replacement/unknown-change" full-software-snapshot
               target '("artifact/source" "artifact/unknown")))
             (unknown-only
              (assurance-derive-replacement-requirements
               "replacement/unknown-only" full-software-snapshot
               target '("artifact/unknown")))
             (stale-source
              (software-snapshot
               (list artifact claim evidence decision effect
                     (assurance-obligation
                      "obligation/verify" "r1" 'unknown digest-a
                      subject: "software/release" claim: "claim/release"
                      snapshot: "snapshot/software" evidence-kind: 'native-test
                      capability: 'gerbil-test scope: "repository"
                      snapshot-revision: "r0"
                      snapshot-context-digest: digest-a))
               (list dependency discharge obligation-support
                     decision-dependency authorization)))
             (stale
              (assurance-derive-replacement-requirements
               "replacement/stale-source" stale-source target
               '("artifact/source"))))
        (check-equal? (assurance-replacement-derivation? left) #t)
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (length (.ref left 'requirements)) 1)
        (check-equal? (assurance-replacement-requirement? requirement) #t)
        (check-equal? (.ref requirement 'source-obligation)
                      "obligation/verify")
        (check-equal? (.ref requirement 'evidence-kind) 'native-test)
        (check-equal? (.ref requirement 'blocker) #f)
        (check-equal? (car (.ref left 'witnesses))
                      '("artifact/source" ("artifact/source") ()))
        (check-equal? (.ref (car (.ref unchanged 'requirements)) 'blocker)
                      'target-unchanged)
        (check-equal?
         (.ref (car (.ref unknown-change 'requirements)) 'blocker)
         'change-unresolved)
        (check-equal? (.ref unknown-only 'requirements) '())
        (check-equal? (.ref unknown-only 'unresolved)
                      '("artifact/unknown"))
        (check-equal? (.ref (car (.ref stale 'requirements)) 'blocker)
                      'stale-source)
        (check-equal? (.ref left 'verifier-executed?) #f)
        (check-equal? (.ref left 'release-authorized?) #f)
        (check-equal?
         (filter assurance-obligation? (.ref target 'nodes)) '())))

    (test-case "revised claims and unknown targets block automatic replacement"
      (let* ((revised-claim
              (assurance-claim
               "claim/release" "r2" 'unknown digest-a
               subject: "software/release" predicate: "release-ready-v2"
               assumptions: '("assumption/toolchain")
               support-requirements: '("obligation/verify")
               scope: "repository" valid-from: "2026-09-17"))
             (changed-claim-target
              (assurance-snapshot
               "snapshot/software" "r2" "graph/software"
               '(("artifact/source" . "r1")) '(("claim/release" . "r2"))
               "event-cut/1" "policy/release" "r1"
               (list artifact revised-claim)
               (list dependency)))
             (unknown-target
              (software-snapshot
               (list artifact claim evidence) (list dependency)
               '("artifact/unresolved") "r2"))
             (foreign-target
              (assurance-snapshot
               "snapshot/other" "r2" "graph/software"
               '(("artifact/source" . "r1")) '(("claim/release" . "r1"))
               "event-cut/1" "policy/release" "r1"
               (list artifact claim) (list dependency)))
             (changed-claim
              (assurance-derive-replacement-requirements
               "replacement/changed-claim" full-software-snapshot
               changed-claim-target '("artifact/source")))
             (unknown
              (assurance-derive-replacement-requirements
               "replacement/unknown" full-software-snapshot
               unknown-target '("artifact/source")))
             (foreign
              (assurance-derive-replacement-requirements
               "replacement/foreign" full-software-snapshot
               foreign-target '("artifact/source"))))
        (check-equal?
         (.ref (car (.ref changed-claim 'requirements)) 'blocker)
         'claim-changed)
        (check-equal?
         (.ref (car (.ref unknown 'requirements)) 'blocker)
         'target-unresolved)
        (check-equal?
         (.ref (car (.ref foreign 'requirements)) 'blocker)
         'target-identity-changed)))

    (test-case "an explicit fresh replacement binds without promoting old evidence"
      (let* ((draft
              (replacement-draft
               (list artifact replacement-claim replacement-candidate)
               (list dependency replacement-support)))
             (permuted-draft
              (replacement-draft
               (list replacement-candidate artifact replacement-claim)
               (list replacement-support dependency)))
             (derivation
              (assurance-derive-replacement-requirements
               "replacement/explicit" full-software-snapshot draft
               '("artifact/source")))
             (permuted-derivation
              (assurance-derive-replacement-requirements
               "replacement/explicit" full-software-snapshot permuted-draft
               '("artifact/source"))))
        (check-equal? (.ref (car (.ref derivation 'requirements)) 'blocker)
                      'claim-changed)
        (let-values (((final receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/declaration" full-software-snapshot
                       draft derivation "obligation/verify"
                       "obligation/verify-next"))
                     ((permuted-final permuted-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/declaration" full-software-snapshot
                       permuted-draft permuted-derivation
                       "obligation/verify" "obligation/verify-next")))
          (let ((bound
                 (find (lambda (node)
                         (equal? (.ref node 'identity)
                                 "obligation/verify-next"))
                       (.ref final 'nodes))))
            (check-equal? (assurance-replacement-declaration-receipt? receipt)
                          #t)
            (check-equal? (.ref receipt 'blocker) #f)
            (check-equal? (.ref bound 'snapshot-revision) "r2")
            (check-equal? (.ref bound 'snapshot-context-digest)
                          (.ref final 'context-digest))
            (check-equal? (.ref replacement-candidate 'snapshot-revision) #f)
            (check-equal? (.ref receipt 'final-snapshot-digest)
                          (.ref final 'digest))
            (check-equal? (.ref receipt 'verifier-executed?) #f)
            (check-equal? (.ref receipt 'release-authorized?) #f)
            (check-equal? (.ref final 'digest) (.ref permuted-final 'digest))
            (check-equal? (.ref receipt 'digest)
                          (.ref permuted-receipt 'digest))
            (check-equal?
             (assurance-replacement-declaration-receipt?
              (.o (:: @ receipt) release-authorized?: #t))
             #f)))))

    (test-case "replacement declaration rejects missing and hypothetical links"
      (let* ((draft
              (replacement-draft
               (list artifact replacement-claim replacement-candidate)
               (list dependency replacement-support)))
             (derivation
              (assurance-derive-replacement-requirements
               "replacement/negative" full-software-snapshot draft
               '("artifact/source")))
             (missing-link
              (replacement-draft
               (list artifact replacement-claim replacement-candidate)
               (list dependency)))
             (hypothetical-link
              (replacement-draft
               (list artifact replacement-claim replacement-candidate)
               (list dependency
                     (.o (:: @ replacement-support)
                         modality: 'hypothesized))))
             (foreign-claim
              (replacement-draft
               (list artifact replacement-claim
                     (.o (:: @ replacement-candidate)
                         claim: "claim/foreign"))
               (list dependency replacement-support)))
             (forged-draft (.o (:: @ draft) digest: digest-a)))
        (let-values (((missing-final missing-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/missing" full-software-snapshot
                       missing-link
                       (assurance-derive-replacement-requirements
                        "replacement/missing-derivation"
                        full-software-snapshot missing-link
                        '("artifact/source"))
                       "obligation/verify" "obligation/verify-next"))
                     ((hypothetical-final hypothetical-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/hypothetical" full-software-snapshot
                       hypothetical-link
                       (assurance-derive-replacement-requirements
                        "replacement/hypothetical-derivation"
                        full-software-snapshot hypothetical-link
                        '("artifact/source"))
                       "obligation/verify" "obligation/verify-next"))
                     ((stale-final stale-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/stale" full-software-snapshot
                       hypothetical-link derivation
                       "obligation/verify" "obligation/verify-next"))
                     ((foreign-final foreign-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/foreign-claim" full-software-snapshot
                       foreign-claim
                       (assurance-derive-replacement-requirements
                        "replacement/foreign-claim-derivation"
                        full-software-snapshot foreign-claim
                        '("artifact/source"))
                       "obligation/verify" "obligation/verify-next"))
                     ((forged-final forged-receipt)
                      (assurance-declare-replacement-obligation
                       "replacement/forged" full-software-snapshot
                       forged-draft
                       (assurance-derive-replacement-requirements
                        "replacement/forged-derivation"
                        full-software-snapshot forged-draft
                        '("artifact/source"))
                       "obligation/verify" "obligation/verify-next")))
          (check-equal? missing-final #f)
          (check-equal? (.ref missing-receipt 'blocker) 'support-link-missing)
          (check-equal? hypothetical-final #f)
          (check-equal? (.ref hypothetical-receipt 'blocker)
                        'support-link-hypothetical)
          (check-equal? stale-final #f)
          (check-equal? (.ref stale-receipt 'blocker)
                        'derivation-mismatch)
          (check-equal? foreign-final #f)
          (check-equal? (.ref foreign-receipt 'blocker)
                        'candidate-claim-mismatch)
          (check-equal? forged-final #f)
          (check-equal? (.ref forged-receipt 'blocker)
                        'derivation-mismatch))))

    (test-case "verification obligations have a closed evidence-kind vocabulary"
      (check-equal?
       +assurance-evidence-kinds+
       '(proof model-check replay unit-test integration-test native-test
         static-analysis authorization-differential human-review))
      (for-each
       (lambda (kind)
         (check-equal?
          (assurance-obligation?
           (assurance-obligation
            "obligation/kind" "r1" 'unknown digest-a
            subject: "software/release" claim: "claim/release"
            snapshot: "snapshot/software" evidence-kind: kind
            capability: 'verifier scope: "repository"))
          #t))
       +assurance-evidence-kinds+)
      (check-exception
       (assurance-obligation
        "obligation/invalid-kind" "r1" 'unknown digest-a
        subject: "software/release" claim: "claim/release"
        snapshot: "snapshot/software" evidence-kind: 'arbitrary-pass
        capability: 'verifier scope: "repository")
       Error?))

    (test-case "verifier choices explain matching and rejected declarations"
      (let* ((policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (plan
              (assurance-plan-verification
               "plan/verifier-choice" full-software-snapshot
               '("artifact/source") policy))
             (kind-mismatch
              (assurance-verifier-candidate
               "candidate/a" "r1" 0 '(proof) 'gerbil-test))
             (capability-mismatch
              (assurance-verifier-candidate
               "candidate/b" "r1" 1 '(native-test) 'lean))
             (chosen
              (assurance-verifier-candidate
               "candidate/z" "r1" 2 '(native-test unit-test) 'gerbil-test))
             (alternative
              (assurance-verifier-candidate
               "candidate/c" "r1" 3 '(native-test) 'gerbil-test))
             (catalog
              (list alternative kind-mismatch chosen capability-mismatch))
             (left
              (assurance-explain-verifier-choices
               "choices/release" plan catalog))
             (right
              (assurance-explain-verifier-choices
               "choices/release" plan (reverse catalog)))
             (revised
              (assurance-explain-verifier-choices
               "choices/release" plan
               (list alternative kind-mismatch capability-mismatch
                     (assurance-verifier-candidate
                      "candidate/z" "r2" 2 '(native-test unit-test)
                      'gerbil-test))))
             (missing
              (assurance-explain-verifier-choices
               "choices/missing" plan (list kind-mismatch)))
             (blocked-plan
              (assurance-plan-verification
               "plan/no-verifier" full-software-snapshot
               '("artifact/source")
               (assurance-verification-policy
                "policy/release" "r1" '())))
             (blocked
              (assurance-explain-verifier-choices
               "choices/blocked" blocked-plan (list chosen))))
        (check-equal? (assurance-verifier-choice-receipt? left) #t)
        (check-equal? (map (lambda (candidate) (.ref candidate 'identity))
                           (.ref left 'candidates))
                      '("candidate/a" "candidate/b" "candidate/z"
                        "candidate/c"))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (equal? (.ref left 'digest) (.ref revised 'digest))
                      #f)
        (check-equal? (map (lambda (choice) (.ref choice 'reason))
                           (.ref left 'choices))
                      '(evidence-kind-unsupported capability-mismatch
                        chosen lower-priority))
        (check-equal? (map (lambda (choice) (.ref choice 'selected?))
                           (.ref left 'choices))
                      '(#f #f #t #f))
        (check-equal? (.ref left 'unassigned-obligations) '())
        (check-equal? (.ref missing 'unassigned-obligations)
                      '("obligation/verify"))
        (check-equal? (.ref (car (.ref blocked 'choices)) 'reason)
                      'request-blocked)
        (check-equal? (.ref blocked 'unassigned-obligations) '())
        (check-equal? (.ref left 'verifier-executed?) #f)
        (check-equal? (.ref left 'release-authorized?) #f)
        (check-exception
         (assurance-explain-verifier-choices
          "choices/duplicate" plan (list chosen chosen))
         Error?)
        (check-exception
         (assurance-verifier-candidate
          "candidate/unknown" "r1" 0 '(arbitrary-pass) 'gerbil-test)
         Error?)))

    (test-case "component support never supplies a composition obligation"
      (let* ((component-a
              (assurance-claim
               "claim/component-a" "r1" 'supported digest-a
               subject: "software/component-a" predicate: "ready"
               scope: "repository" valid-from: "2026-09-17"))
             (component-b
              (assurance-claim
               "claim/component-b" "r1" 'supported digest-a
               subject: "software/component-b" predicate: "ready"
               scope: "repository" valid-from: "2026-09-17"))
             (composite
              (assurance-claim
               "claim/composite" "r1" 'unknown digest-b
               subject: "software/composite" predicate: "composition-safe"
               support-requirements: '("obligation/composition")
               scope: "repository" valid-from: "2026-09-17"))
             (candidate-obligation
              (assurance-obligation
               "obligation/composition" "r1" 'unknown digest-a
               subject: "software/composite" claim: "claim/composite"
               snapshot: "snapshot/composition"
               evidence-kind: 'integration-test
               capability: 'composition-test scope: "repository"))
             (components
              (list (assurance-relation
                     "relation/composes/a" 'structural 'composes
                     "claim/composite" "claim/component-a" 'declared)
                    (assurance-relation
                     "relation/composes/b" 'structural 'composes
                     "claim/composite" "claim/component-b" 'declared)))
             (direct-support
              (assurance-relation
               "relation/support/composition" 'assurance 'supports
               "obligation/composition" "claim/composite" 'declared)))
        (def (construct nodes relations)
          (assurance-snapshot
           "snapshot/composition" "r1" "graph/composition"
           '() '(("claim/component-a" . "r1")
                 ("claim/component-b" . "r1")
                 ("claim/composite" . "r1"))
           "event-cut/1" "policy/composition" "r1"
           nodes relations))
        (let* ((missing-snapshot
                (construct (list component-a component-b composite)
                           components))
               (missing
                (assurance-derive-composition-requirements
                 "composition/missing" missing-snapshot))
               (permuted
                (assurance-derive-composition-requirements
                 "composition/missing"
                 (construct (list composite component-b component-a)
                            (reverse components))))
               (candidate
                (construct
                 (list component-a component-b composite candidate-obligation)
                 (cons direct-support components)))
               (stale-obligation
                (assurance-obligation
                 "obligation/composition" "r1" 'unknown digest-a
                 subject: "software/composite" claim: "claim/composite"
                 snapshot: "snapshot/composition"
                 evidence-kind: 'integration-test
                 capability: 'composition-test scope: "repository"
                 snapshot-revision: "r0"
                 snapshot-context-digest: digest-a))
               (stale
                (assurance-derive-composition-requirements
                 "composition/stale"
                 (construct
                  (list component-a component-b composite stale-obligation)
                  (cons direct-support components))))
               (bound-obligation
                (assurance-bind-obligation-to-snapshot
                 candidate-obligation candidate))
               (bound-snapshot
                (construct
                 (list component-a component-b composite bound-obligation)
                 (cons direct-support components)))
               (declared
                (assurance-derive-composition-requirements
                 "composition/declared" bound-snapshot))
               (changed
                (assurance-invalidate
                 "composition/changed" bound-snapshot
                 '("claim/component-a"))))
          (check-equal? (assurance-composition-derivation? missing) #t)
          (check-equal? (.ref missing 'digest) (.ref permuted 'digest))
          (check-equal?
           (.ref (car (.ref missing 'requirements)) 'component-claims)
           '("claim/component-a" "claim/component-b"))
          (check-equal?
           (.ref (car (.ref missing 'requirements)) 'blocker)
           'missing-direct-obligation)
          (check-equal?
           (.ref (car (.ref stale 'requirements)) 'direct-obligations)
           '("obligation/composition"))
          (check-equal?
           (.ref (car (.ref stale 'requirements)) 'current-obligations) '())
          (check-equal?
           (.ref (car (.ref stale 'requirements)) 'blocker)
           'stale-direct-obligation)
          (check-equal?
           (.ref (car (.ref declared 'requirements)) 'direct-obligations)
           '("obligation/composition"))
          (check-equal?
           (.ref (car (.ref declared 'requirements)) 'current-obligations)
           '("obligation/composition"))
          (check-equal?
           (.ref (car (.ref declared 'requirements)) 'blocker) #f)
          (check-equal? (.ref declared 'verifier-executed?) #f)
          (check-equal? (.ref declared 'release-authorized?) #f)
          (check-equal?
           (assurance-invalidation-receipt-ref changed 'required-obligations)
           '("obligation/composition")))))

    (test-case "POO Graph orders affected prerequisites before dependents"
      (let* ((a (verification-obligation "obligation/a" 'gerbil-test))
             (b (verification-obligation "obligation/b" 'gerbil-test))
             (c (verification-obligation "obligation/c" 'gerbil-test))
             (relations
              (list (verification-support "obligation/a")
                    (verification-support "obligation/b")
                    (verification-support "obligation/c")
                    (verification-dependency "obligation/a" "obligation/b")
                    (verification-dependency "obligation/b" "obligation/c")))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (left
              (assurance-plan-verification
               "plan/ordered"
               (verification-snapshot (list a b c) relations)
               '("artifact/source") policy))
             (right
              (assurance-plan-verification
               "plan/ordered"
               (verification-snapshot (list c a b) (reverse relations))
               '("artifact/source") policy)))
        (check-equal? (.ref left 'selected-obligations)
                      '("obligation/c" "obligation/b" "obligation/a"))
        (check-equal? (.ref left 'blocked-obligations) '())
        (check-equal? (.ref left 'cycle-path) '())
        (check-equal? (.ref left 'cyclic-components) '())
        (check-equal? (.ref (car (.ref left 'requests)) 'dependencies) '())
        (check-equal? (.ref (cadr (.ref left 'requests)) 'dependencies)
                      '("obligation/c"))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'verifier-executed?) #f)))

    (test-case "an unplanned prerequisite blocks its dependent"
      (let* ((a (verification-obligation "obligation/a" 'gerbil-test))
             (b (verification-obligation "obligation/b" 'gerbil-test))
             (snapshot
              (verification-snapshot
               (list a b)
               (list (verification-support "obligation/a")
                     (verification-dependency "obligation/a" "obligation/b"))))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (plan
              (assurance-plan-verification
               "plan/unplanned" snapshot '("artifact/source") policy)))
        (check-equal? (.ref plan 'selected-obligations) '())
        (check-equal? (.ref plan 'blocked-obligations) '("obligation/a"))
        (check-equal? (.ref (car (.ref plan 'requests)) 'dependencies)
                      '("obligation/b"))
        (check-equal? (.ref (car (.ref plan 'requests)) 'blocker)
                      'dependency-unplanned)))

    (test-case "a blocked prerequisite propagates along POO Graph reachability"
      (let* ((a (verification-obligation "obligation/a" 'gerbil-test))
             (b (verification-obligation "obligation/b" 'lean))
             (snapshot
              (verification-snapshot
               (list a b)
               (list (verification-support "obligation/a")
                     (verification-support "obligation/b")
                     (verification-dependency "obligation/a" "obligation/b"))))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (plan
              (assurance-plan-verification
               "plan/blocked-prerequisite" snapshot
               '("artifact/source") policy)))
        (check-equal? (.ref plan 'selected-obligations) '())
        (check-equal? (.ref plan 'blocked-obligations)
                      '("obligation/b" "obligation/a"))
        (check-equal? (.ref (car (.ref plan 'requests)) 'blocker)
                      'capability-unavailable)
        (check-equal? (.ref (cadr (.ref plan 'requests)) 'blocker)
                      'dependency-blocked)))

    (test-case "a dependency cycle blocks its SCC but preserves an independent branch"
      (let* ((a (verification-obligation "obligation/a" 'gerbil-test))
             (b (verification-obligation "obligation/b" 'gerbil-test))
             (c (verification-obligation "obligation/c" 'gerbil-test))
             (d (verification-obligation "obligation/d" 'gerbil-test))
             (snapshot
              (verification-snapshot
               (list a b c d)
               (list (verification-support "obligation/a")
                     (verification-support "obligation/b")
                     (verification-support "obligation/c")
                     (verification-support "obligation/d")
                     (verification-dependency "obligation/a" "obligation/b")
                     (verification-dependency "obligation/b" "obligation/a")
                     (verification-dependency "obligation/d" "obligation/a"))))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (plan
              (assurance-plan-verification
               "plan/cycle" snapshot '("artifact/source") policy)))
        (check-equal? (.ref plan 'selected-obligations) '("obligation/c"))
        (check-equal? (.ref plan 'blocked-obligations)
                      '("obligation/a" "obligation/b" "obligation/d"))
        (check-equal? (.ref plan 'cycle-path)
                      '("obligation/a" "obligation/b" "obligation/a"))
        (check-equal? (.ref plan 'cyclic-components)
                      '(("obligation/a" "obligation/b")))
        (check-equal? (map (lambda (request) (.ref request 'blocker))
                           (.ref plan 'requests))
                      '(#f dependency-cycle dependency-cycle
                           dependency-blocked))))

    (test-case "every independent dependency cycle is explained"
      (let* ((ids '("obligation/a" "obligation/b" "obligation/c"
                    "obligation/d" "obligation/e" "obligation/f"
                    "obligation/g"))
             (nodes (map (lambda (id)
                           (verification-obligation id 'gerbil-test))
                         ids))
             (relations
              (append
               (map verification-support ids)
               (list (verification-dependency "obligation/a" "obligation/b")
                     (verification-dependency "obligation/b" "obligation/a")
                     (verification-dependency "obligation/d" "obligation/a")
                     (verification-dependency "obligation/e" "obligation/f")
                     (verification-dependency "obligation/f" "obligation/e")
                     (verification-dependency "obligation/g" "obligation/e"))))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (left
              (assurance-plan-verification
               "plan/two-cycles"
               (verification-snapshot nodes relations)
               '("artifact/source") policy))
             (right
              (assurance-plan-verification
               "plan/two-cycles"
               (verification-snapshot (reverse nodes) (reverse relations))
               '("artifact/source") policy)))
        (check-equal? (.ref left 'selected-obligations) '("obligation/c"))
        (check-equal? (.ref left 'blocked-obligations)
                      '("obligation/a" "obligation/b" "obligation/d"
                        "obligation/e" "obligation/f" "obligation/g"))
        (check-equal? (.ref left 'cyclic-components)
                      '(("obligation/a" "obligation/b")
                        ("obligation/e" "obligation/f")))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'cyclic-components)
                      (.ref right 'cyclic-components))))

    (test-case "missing capability remains an explained blocked obligation"
      (let* ((policy
              (assurance-verification-policy "policy/release" "r1" '()))
             (plan
              (assurance-plan-verification
               "plan/no-capability" full-software-snapshot
               '("artifact/source") policy)))
        (check-equal? (.ref plan 'selected-obligations) '())
        (check-equal? (.ref plan 'blocked-obligations)
                      '("obligation/verify"))
        (check-equal? (.ref (car (.ref plan 'requests)) 'blocker)
                      'capability-unavailable)
        (check-equal? (.ref plan 'release-authorized?) #f)))

    (test-case "unresolved inputs and old obligation snapshots fail closed"
      (let* ((policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (unresolved-snapshot
              (software-snapshot
               (list artifact claim obligation evidence decision effect)
               (list dependency discharge obligation-support
                     decision-dependency authorization)
               '("artifact/missing")))
             (unresolved-plan
              (assurance-plan-verification
               "plan/unresolved" unresolved-snapshot
               '("artifact/source") policy))
             (old-obligation
              (.o (:: @ obligation) snapshot: "snapshot/old"))
             (old-snapshot
              (software-snapshot
               (list artifact claim old-obligation evidence decision effect)
               (list dependency discharge obligation-support
                     decision-dependency authorization)))
             (old-plan
              (assurance-plan-verification
               "plan/old" old-snapshot '("artifact/source") policy)))
        (check-equal? (.ref unresolved-plan 'selected-obligations) '())
        (check-equal? (.ref unresolved-plan 'unresolved)
                      '("artifact/missing"))
        (check-equal?
         (.ref (car (.ref unresolved-plan 'requests)) 'blocker)
         'unresolved-frontier)
        (check-equal? (.ref old-plan 'selected-obligations) '())
        (check-equal? (.ref (car (.ref old-plan 'requests)) 'blocker)
                      'stale-obligation)))

    (test-case "same-identity snapshot revisions and contents cannot reuse old obligations"
      (let* ((policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (nodes (.ref full-software-snapshot 'nodes))
             (relations (.ref full-software-snapshot 'relations))
             (new-revision
              (software-snapshot nodes relations '() "r2"))
             (changed-content
              (software-snapshot
               (map (lambda (node)
                      (if (equal? (.ref node 'identity) "claim/release")
                        (.o (:: @ node) predicate: "release-ready-v2")
                        node))
                    nodes)
               relations))
             (revision-plan
              (assurance-plan-verification
               "plan/new-revision" new-revision
               '("artifact/source") policy))
             (content-plan
              (assurance-plan-verification
               "plan/changed-content" changed-content
               '("artifact/source") policy)))
        (check-equal? (.ref new-revision 'identity)
                      (.ref full-software-snapshot 'identity))
        (check-equal? (.ref changed-content 'revision)
                      (.ref full-software-snapshot 'revision))
        (check-equal? (.ref revision-plan 'selected-obligations) '())
        (check-equal? (.ref content-plan 'selected-obligations) '())
        (check-equal? (.ref (car (.ref revision-plan 'requests)) 'blocker)
                      'stale-obligation)
        (check-equal? (.ref (car (.ref content-plan 'requests)) 'blocker)
                      'stale-obligation)
        (check-equal? (.ref revision-plan 'verifier-executed?) #f)
        (check-equal? (.ref content-plan 'release-authorized?) #f)
        (check-exception
         (assurance-bind-obligation-to-snapshot
          (car (filter assurance-obligation? nodes)) new-revision)
         Error?)))

    (test-case "conflicted snapshot remains distinct from unknown frontier"
      (let* ((snapshot
              (assurance-snapshot
               "snapshot/software" "r1" "graph/software"
               '(("artifact/source" . "r2"))
               '(("claim/release" . "r1"))
               "event-cut/1" "policy/release" "r1"
               (list artifact claim obligation evidence decision effect)
               (list dependency discharge obligation-support
                     decision-dependency authorization)
               evidence-identities: '("evidence/test")))
             (policy
              (assurance-verification-policy
               "policy/release" "r1" '(gerbil-test)))
             (plan
              (assurance-plan-verification
               "plan/conflict" snapshot '("artifact/source") policy)))
        (check-equal? (.ref plan 'conflicts) '("artifact/source"))
        (check-equal? (.ref plan 'unresolved) '())
        (check-equal? (.ref plan 'selected-obligations) '())
        (check-equal? (.ref (car (.ref plan 'requests)) 'blocker)
                      'conflicted-snapshot)))

    (test-case "verification policy cannot silently change snapshot authority"
      (check-exception
       (assurance-verification-policy "policy/release" "r1" '("gerbil-test"))
       Error?)
      (check-exception
       (assurance-plan-verification
        "plan/wrong-policy" full-software-snapshot
        '("artifact/source")
        (assurance-verification-policy
         "policy/other" "r1" '(gerbil-test)))
       Error?))

    (test-case "structural cycles have deterministic SCCs and witnesses"
      (let* ((snapshot
              (software-snapshot
               (list artifact claim)
               (list dependency reverse-dependency)))
             (left
              (assurance-invalidate
               "invalidation/cycle-left" snapshot '("artifact/source")))
             (right
              (assurance-invalidate
               "invalidation/cycle-right" snapshot '("artifact/source"))))
        (check-equal?
         (assurance-invalidation-receipt-ref left 'impacted)
         '("artifact/source" "claim/release"))
        (check-equal?
         (assurance-invalidation-receipt-ref left 'cyclic-components)
         '(("artifact/source" "claim/release")))
        (check-equal?
         (assurance-invalidation-receipt-ref left 'witnesses)
         (assurance-invalidation-receipt-ref right 'witnesses))
        (check-equal?
         (assurance-invalidation-receipt-ref left 'strong-components)
         (assurance-invalidation-receipt-ref right 'strong-components))))))
