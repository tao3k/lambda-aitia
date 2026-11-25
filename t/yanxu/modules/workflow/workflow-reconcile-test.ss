;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; RFC 0008 Qualification Suite:
;;; Native gerbil-ascent + gerbil-poo + FunFlow CAS DAG + GraphEngine
;;; Obligation-Fixpoint Reconciliation for Lambda Aitia GitOps/SDLC.
;;; Strictly typed (zero `Any`) and consumes ONLY the public Yuanxu Module interface.

(import :std/test
        (only-in :std/error Error?)
        (only-in :clan/poo/object .o .get .ref)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))

(export aitia-workflow-reconcile-test)

(def wf (.get lambda-aitia.init.exports modules workflow))

(def test-cut
  (.o project: "tao3k/lambda-aitia"
      workspace: "default"
      change: "sywptlmp"
      operation: "op-1"
      commit: "48364a5d95c4c6ca854cda6320e76f07f65f797b"
      tree: "tree-1"
      parents: '("835a5e62b8deb3caa9ecf89748660aef458a6393")))

(def test-naming
  (.o project-key: "AITIA"
      types: '("build" "chore" "ci" "docs" "feat" "fix" "refactor" "test")
      primary-language: "en"
      language-sources: '("README.org")
      scopes: (list (.o name: "gitops" paths: '("justfile" "modules/gitops" ".agents/aita")))
      references: (list (.o identity: "RFC-0008"
                            source: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
                            element: "ascent-obligation-funflow"))))

(def test-sources
  (list (.o path: "README.org" text: "* Lambda Aitia\nEnglish project readme.\n" cut: test-cut)
        (.o path: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
            text: "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"
            cut: test-cut)))

(def valid-proposal
  (.o identity: "AITIA-RFC-0008"
      reference: "RFC-0008"
      language: "en"
      language-source: "README.org"
      type: "feat"
      scope: "gitops"
      summary: "Wire native ASCENT and FunFlow"
      rationale: "Drive GitOps obligations through ASCENT reconciliation and FunFlow CAS DAGs."))

(def aitia-workflow-reconcile-test
  (test-suite "Lambda Aitia RFC 0008 native ASCENT + FunFlow workflow reconciliation"

    (test-case "1. POO prototype composition extends workflow domain without a custom DSL"
      (let* ((base (.get wf gitops-commit-domain))
             (custom (.o (:: @ base)
                         domain-id: 'de/custom-gitops-commit
                         default-max-branches: 3)))
        (check-equal? ((.get wf domain?) base) #t)
        (check-equal? ((.get wf domain?) custom) #t)
        (check-equal? (.get custom domain-id) 'de/custom-gitops-commit)
        (check-equal? (.get custom raw-tool-calls-allowed?) #f)
        (check-equal? (.get custom action-authorized?) #f)))

    (test-case "2. Deterministic-first FunFlow frontier batches disjoint checks with 0 LLM calls and stops at human audit gate"
      (let* ((g0 ((.get wf gitops-commit-graph)
                  test-naming test-cut test-sources '("justfile") (list valid-proposal)
                  approval-live?: #f))
             (f0 ((.get wf reconcile-frontier) g0))
             (plan (.get f0 funflow-plan)))
        (check-equal? (.get f0 frontier-mode) 'dispatch-deterministic-funflow)
        (check-equal? (.get f0 ready-synthesis-holes) '())
        (check-equal? (.get f0 action-authorized?) #f)
        (check-equal? (.ref plan 'valid?) #t)
        (check-equal? (.ref plan 'subagents-spawned) 0)
        (check-equal? (length (.ref plan 'parallel-batch)) 2)
        (let* ((rep ((.get wf reconcile)
                     g0
                     oracle-fn: (lambda (_h _ctx _hyps)
                                  (error "LLM oracle MUST NOT run when deterministic frontier discharges!"))))
               (final (.ref rep 'final-frontier))
               (discharged-ids (map (lambda (o) (.ref o 'obligation-id))
                                    (.ref final 'discharged-obligations)))
               (blocked-ids (map (lambda (o) (.ref o 'obligation-id))
                                 (.ref final 'blocked-on-human-obligations))))
          (check-equal? (.ref rep 'quiescent?) #t)
          (check-equal? (.ref rep 'total-llm-calls) 0)
          (check-equal? (.ref rep 'total-det-tasks) 3)
          (check (and (member "SWE-083" discharged-ids) #t) => #t)
          (check (and (member "SWE-084" discharged-ids) #t) => #t)
          (check (and (member "gitops.commit-semantics" discharged-ids) #t) => #t)
          (check (and (member "gitops.commit-review-approved" blocked-ids) #t) => #t)
          (check (and (member "gitops.commit-applied" blocked-ids) #t) => #t))))

    (test-case "3. Unscoped path opens controlled SynthesisHole, rejects raw ReAct tool calls, and evaluates competing branches"
      (let* ((g0 ((.get wf gitops-commit-graph)
                  test-naming test-cut test-sources '(".github/workflows/ci.yml") (list valid-proposal)
                  approval-live?: #f))
             (raw-res ((.get wf admit-proposal)
                       g0
                       ((.get wf raw-tool-call) 'bash '("git commit -am bypass"))))
             (branches
              ((.get wf competing-branches)
               (list (.o bind-these: #f
                         branch-id: 'branch-register-ci-scope
                         description: "Register .github/workflows in gitops scope in project.json"
                         supports-hypotheses: '("hyp:scope-registration-missing")
                         contradicts-hypotheses: '()
                         open-questions: '("Does CI governance share gitops approval policy?"))
                     (.o bind-these: #f
                         branch-id: 'branch-separate-ci-scope
                         description: "Declare a separate ci-infra scope for .github/workflows"
                         supports-hypotheses: '("hyp:separate-scope-required")
                         contradicts-hypotheses: '()
                         open-questions: '("Which reviewers own ci-infra?")))))
             (branch-res ((.get wf admit-proposal) g0 branches))
             (req-type (.get wf patch-request-type))
             (ev-type (.get wf patch-evidence-type)))
        (check-equal? (.get raw-res admitted?) #f)
        (check-equal? (.get raw-res reason) 'raw-single-step-tool-call-forbidden)
        (check-equal? (.get raw-res action-authorized?) #f)
        (check-equal? (.get branch-res admitted?) #t)
        (check-equal? (.get branch-res action-authorized?) #f)
        (check-equal? (.ref (.get branch-res branch-matrix) 'branch-count) 2)
        (check-equal? (.ref (.get branch-res branch-matrix) 'hypothesis-count) 2)
        ;; Negative control: mismatched input payload is rejected by strict POO FunFlow edge contract
        (check-exception
         ((.get wf pure-task-node)
          "task:bad-typed-patch" "gitops.commit-semantics" "ev:gitops-commit-semantics"
          'bad-typed-patch req-type ev-type
          (lambda (req) req)
          (.o (wrong-field := "not-a-patch-request")))
         Error?)
        ;; Positive control: strongly typed FunFlow patch task discharges semantics while human gate holds!
        (let* ((patch-task
                ((.get wf pure-task-node)
                 "task:synthesized-scope-patch"
                 "gitops.commit-semantics"
                 "ev:gitops-commit-semantics"
                 'synthesized-scope-patch
                 req-type
                 ev-type
                 (lambda (req)
                   (.o (kind := 'synthesized-patch)
                       (action := (.get req action))
                       (targets := (.get req targets))))
                 (.o (action := 'register-scope) (targets := '(".github/workflows")))
                 required-evidence-ids: '("ev:SWE-083" "ev:SWE-084")
                 read-footprint: '(project-config)
                 write-footprint: '(project-config-proposal)
                 effect-class: 'pure-cas))
               (oracle-calls (box 0))
               (rep ((.get wf reconcile)
                     g0
                     oracle-fn: (lambda (hole _ctx hyps)
                                  (set-box! oracle-calls (+ 1 (unbox oracle-calls)))
                                  (check-equal? (.ref hole 'hole-id) "hole:gitops-commit-narration-or-scope")
                                  (check-equal? (length hyps) 2)
                                  ((.get wf dag-patch) (list patch-task)))))
               (final (.ref rep 'final-frontier))
               (discharged-ids (map (lambda (o) (.ref o 'obligation-id))
                                    (.ref final 'discharged-obligations))))
          (check-equal? (unbox oracle-calls) 1)
          (check-equal? (.ref rep 'total-llm-calls) 1)
          (check-equal? (.ref final 'epistemic-competition-status) 'open-competition)
          (check (and (member "gitops.commit-semantics" discharged-ids) #t) => #t)
          (check-equal? (member "gitops.commit-applied" discharged-ids) #f))))

    (test-case "4. Human approval unblocks FencedEffect and cut retraction selectively invalidates dependent evidence"
      (let* ((g0 ((.get wf gitops-commit-graph)
                  test-naming test-cut test-sources '("justfile") (list valid-proposal)
                  approval-live?: #t))
             (rep ((.get wf reconcile) g0))
             (final (.ref rep 'final-frontier))
             (g-with-unrelated
              ((.get wf with-evidence)
               (.ref rep 'graph)
               ((.get wf evidence-fact)
                "ev:unrelated-adr" (.o (kind := 'adr-reference) (id := "ADR-0009"))
                cut: 1
                premise-ids: '("premise:adr-0009")
                origin-tier: 'observed-fact)))
             (g-retracted ((.get wf retract-premise)
                           g-with-unrelated
                           (.get g0 cut-premise)
                           new-cut: 2))
             (live-ids (map (lambda (e) (.ref e 'evidence-id))
                            ((.get wf live-evidence) g-retracted)))
             (f-after ((.get wf reconcile-frontier) g-retracted)))
        (check-equal? (.ref rep 'quiescent?) #t)
        (check-equal? (.ref rep 'total-llm-calls) 0)
        (check-equal? (length (.ref final 'discharged-obligations)) 5)
        (check-equal? (length (.ref final 'unsatisfied-obligations)) 0)
        (check (and (member "ev:unrelated-adr" live-ids) #t) => #t)
        (check-equal? (member "ev:SWE-083" live-ids) #f)
        (check-equal? (member "ev:gitops-commit-receipt" live-ids) #f)
        (check-equal? (.get f-after frontier-mode) 'dispatch-deterministic-funflow)
        (check-equal? (length (.get f-after unsatisfied-obligations)) 5)))))
