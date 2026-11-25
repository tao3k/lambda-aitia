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

    (test-case "1. POO prototype composition extends workflow domain and config.ss case profiles without a custom DSL"
      (let* ((base (.get wf gitops-commit-domain))
             (custom (.o (:: @ base)
                         domain-id: 'de/custom-gitops-commit
                         default-max-branches: 3))
             (case-prof (.get wf profiles gitops-commit))
             (custom-case (.o (:: @ case-prof)
                              case-id: 'de/case/custom-review
                              state-budget: 16)))
        (check-equal? ((.get wf domain?) base) #t)
        (check-equal? ((.get wf domain?) custom) #t)
        (check-equal? ((.get wf domain?) case-prof) #t)
        (check-equal? (.get custom domain-id) 'de/custom-gitops-commit)
        (check-equal? (.get custom raw-tool-calls-allowed?) #f)
        (check-equal? (.get custom action-authorized?) #f)
        (check-equal? (.get case-prof case-id) 'aitia/case/gitops-commit)
        (check-equal? (.get custom-case case-id) 'de/case/custom-review)
        (check-equal? (.get custom-case allow-fenced-in-competition?) #f)))

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
        (check-equal? (length (.get f-after unsatisfied-obligations)) 5)))

    (test-case "5. Native ASCENT Finite-Choice forces closed 'deduction (overriding open offers) and branches with provenance on unscoped paths"
      ;; Clean single-scope cut + hallucinated open offer: closed singleton wins via forced 'deduction!
      (let* ((g-clean ((.get wf gitops-commit-graph)
                       test-naming test-cut test-sources '("justfile") (list valid-proposal)
                       candidate-offers: '(hallucinated-scope)
                       approval-live?: #f))
             (sol-clean (.get g-clean choice-solution))
             (w-clean (car (.get sol-clean worlds))))
        (check-equal? (.get sol-clean choice-status) 'unique-deduction)
        (check-equal? (.get sol-clean world-count) 1)
        (check-equal? (.get sol-clean action-authorized?) #f)
        (check-equal? (.get w-clean scope-decision) 'gitops)
        (check-equal? (.get w-clean dispatch-decision) 'human-audit-gate)
        (check-equal? (.get w-clean scope-derivation-kind) 'deduction)
        (check-equal? (.get w-clean dispatch-derivation-kind) 'deduction)
        (check (pair? (.get w-clean scope-provenance)) => #t)
        (check (pair? (.get w-clean dispatch-provenance)) => #t))
      ;; Unscoped cut + hallucinated open offer: closed 2-way disjunction restricts to exactly 2 competing worlds!
      (let* ((g-unscoped ((.get wf gitops-commit-graph)
                          test-naming test-cut test-sources '(".github/workflows/ci.yml") (list valid-proposal)
                          candidate-offers: '(bypass-all-scopes)
                          approval-live?: #f))
             (sol-unscoped (.get g-unscoped choice-solution))
             (worlds (.get sol-unscoped worlds))
             (scopes (map (lambda (w) (.get w scope-decision)) worlds)))
        (check-equal? (.get sol-unscoped choice-status) 'competing-worlds)
        (check-equal? (.get sol-unscoped world-count) 2)
        (check (and (member 'extend-existing-scope scopes) #t) => #t)
        (check (and (member 'declare-new-scope scopes) #t) => #t)
        (check-equal? (member 'bypass-all-scopes scopes) #f)
        (for-each (lambda (w)
                    (check-equal? (.get w scope-derivation-kind) 'branch)
                    (check-equal? (.get w dispatch-decision) 'epistemic-competition)
                    (check (pair? (.get w scope-provenance)) => #t)
                    (check-equal? (.get w action-authorized?) #f))
                  worlds)))

    (test-case "6. Finite-Choice empty closed rule prunes refuted worlds and detects unsatisfiable contradictions fail-closed"
      ;; Refuting one of the two competing scope hypotheses leaves only the surviving world
      (let* ((g-pruned ((.get wf gitops-commit-graph)
                        test-naming test-cut test-sources '(".github/workflows/ci.yml") (list valid-proposal)
                        forbidden-scopes: '(extend-existing-scope)))
             (sol-pruned (.get g-pruned choice-solution)))
        (check-equal? (.get sol-pruned world-count) 1)
        (check-equal? (.get (car (.get sol-pruned worlds)) scope-decision) 'declare-new-scope))
      ;; Refuting both competing hypotheses prunes all worlds -> 'unsatisfiable fail-closed!
      (let* ((g-unsat ((.get wf gitops-commit-graph)
                       test-naming test-cut test-sources '(".github/workflows/ci.yml") (list valid-proposal)
                       forbidden-scopes: '(extend-existing-scope declare-new-scope)))
             (sol-unsat (.get g-unsat choice-solution))
             (hyp-ids (map (lambda (h) (.ref h 'hypothesis-id)) (.ref g-unsat 'hypotheses))))
        (check-equal? (.get sol-unsat choice-status) 'unsatisfiable)
        (check-equal? (.get sol-unsat world-count) 0)
        (check (and (member "hyp:choice-space-unsatisfiable" hyp-ids) #t) => #t)))

    (test-case "7. Declarative POO ChoiceFlowPlan enforces static branch completeness, shares FunFlow CAS prefixes ONCE, and blocks FencedEffect across competing worlds"
      (let* ((g-unscoped ((.get wf gitops-commit-graph)
                          test-naming test-cut test-sources '(".github/workflows/ci.yml") (list valid-proposal)
                          approval-live?: #t))
             (choice-sol (.get g-unscoped choice-solution))
             (runner ((.get wf make-pure-runner)))
             (req-type (.get wf patch-request-type))
             (ev-type (.get wf patch-evidence-type))
             (shared-calls (box 0))
             (probe-calls (box 0))
             (fenced-calls (box 0))
             (shared-prefix-task
              ((.get wf pure-task-node)
               "task:shared-sysml-prefix"
               "SWE-083"
               "ev:shared-sysml-prefix"
               'shared-sysml-prefix
               req-type
               ev-type
               (lambda (req)
                 (set-box! shared-calls (+ 1 (unbox shared-calls)))
                 (.o (kind := 'synthesized-patch)
                     (action := (.get req action))
                     (targets := (.get req targets))))
               (.o (action := 'inspect-sysml-tree) (targets := '(".github/workflows/ci.yml")))
               read-footprint: '(sysml-model)
               write-footprint: '()
               effect-class: 'pure-cas))
             (make-probe
              (lambda (sdec)
                ((.get wf pure-task-node)
                 (string-append "task:probe:" (symbol->string sdec))
                 "gitops.commit-semantics"
                 (string-append "ev:probe:" (symbol->string sdec))
                 (string->symbol (string-append "probe-" (symbol->string sdec)))
                 req-type
                 ev-type
                 (lambda (req)
                   (set-box! probe-calls (+ 1 (unbox probe-calls)))
                   (.o (kind := 'synthesized-patch)
                       (action := (.get req action))
                       (targets := (.get req targets))))
                 (.o (action := sdec) (targets := '(".github/workflows/ci.yml")))
                 read-footprint: '(sysml-model)
                 write-footprint: '()
                 effect-class: 'pure-cas)))
             (fenced-apply-task
              ((.get wf pure-task-node)
               "task:fenced-apply"
               "gitops.commit-applied"
               "ev:gitops-commit-receipt"
               'fenced-commit-apply
               req-type
               ev-type
               (lambda (req)
                 (set-box! fenced-calls (+ 1 (unbox fenced-calls)))
                 (.o (kind := 'synthesized-patch)
                     (action := (.get req action))
                     (targets := (.get req targets))))
               (.o (action := 'apply-commit) (targets := '(".github/workflows/ci.yml")))
               read-footprint: '(sysml-model)
               write-footprint: '(jj-commit-history)
               effect-class: 'fenced-effect))
             ;; Negative control 1: incomplete POO ChoiceFlowPlan fails closed with 0 executions!
             (incomplete-plan
              ((.get wf choice-flow-plan)
               (.o (extend-existing-scope := (list (make-probe 'extend-existing-scope))))
               choice-key: 'scope-decision
               shared-prefix: (list shared-prefix-task)))
             (incomplete-res
              ((.get wf execute-choice-worlds) choice-sol runner incomplete-plan approval-live?: #t))
             ;; Complete declarative POO ChoiceFlowPlan (zero opaque routing callback!)
             (complete-plan
              ((.get wf choice-flow-plan)
               (.o (extend-existing-scope := (list (make-probe 'extend-existing-scope)))
                   (declare-new-scope := (list (make-probe 'declare-new-scope))))
               choice-key: 'scope-decision
               shared-prefix: (list shared-prefix-task)
               fenced-tail: (list fenced-apply-task)))
             (exec
              ((.get wf execute-choice-worlds) choice-sol runner complete-plan approval-live?: #t)))
        ;; Incomplete plan failed closed BEFORE running shared-prefix!
        (check-equal? (.get incomplete-res admitted?) #f)
        (check-equal? (.get incomplete-res reason) 'incomplete-choice-flow-branches)
        (check-equal? (.get incomplete-res missing-branches) '(declare-new-scope))
        (check-equal? (.get incomplete-res total-executions) 0)
        ;; Negative control 2: FencedEffect is forbidden inside shared-prefix
        (check-exception
         ((.get wf choice-flow-plan)
          (.o (extend-existing-scope := '()))
          shared-prefix: (list fenced-apply-task))
         Error?)
        ;; Complete plan: shared prefix executed ONCE, second world served from FunFlow CAS!
        (check-equal? (.get exec admitted?) #t)
        (check-equal? (.get exec choice-status) 'competing-worlds)
        (check-equal? (.get exec world-count) 2)
        (check-equal? (unbox shared-calls) 1)
        (check-equal? (unbox probe-calls) 2)
        (check-equal? (.get exec total-executions) 3)
        (check-equal? (.get exec total-cas-hits) 1)
        ;; FencedEffect strictly blocked in ALL competing worlds even with approval-live?: #t!
        (check-equal? (unbox fenced-calls) 0)
        (check-equal? (.get exec fenced-blocked-count) 2)
        (check-equal? (.get exec action-authorized?) #f)
        (let ((w0 (car (.get exec worlds)))
              (w1 (cadr (.get exec worlds))))
          (check-equal? (.get w0 cas-hits) 0)
          (check-equal? (.get w1 cas-hits) 1)
          (check (string? (.get w0 dag-digest)) => #t)
          (check-equal? (.get (car (.get w0 fenced-blocked-tasks)) reason)
                        'fenced-effect-blocked-in-competing-worlds))))

    (test-case "8. ChoiceFlowPlan pre-execution FunFlow DAG Tarjan SCC check rejects cycles fail-closed with 0 executions"
      (let* ((g-clean ((.get wf gitops-commit-graph)
                       test-naming test-cut test-sources '("justfile") (list valid-proposal)
                       approval-live?: #f))
             (choice-sol (.get g-clean choice-solution))
             (runner ((.get wf make-pure-runner)))
             (req-type (.get wf patch-request-type))
             (ev-type (.get wf patch-evidence-type))
             (ran-calls (box 0))
             ;; Mutual evidence cycle: task-a requires ev:b, task-b requires ev:a -> Tarjan SCC cycle!
             (task-a ((.get wf pure-task-node)
                      "task:cycle-a" "SWE-083" "ev:cycle-a" 'cycle-a
                      req-type ev-type
                      (lambda (req)
                        (set-box! ran-calls (+ 1 (unbox ran-calls)))
                        (.o (kind := 'synthesized-patch) (action := 'a) (targets := '())))
                      (.o (action := 'a) (targets := '()))
                      required-evidence-ids: '("ev:cycle-b")
                      effect-class: 'pure-cas))
             (task-b ((.get wf pure-task-node)
                      "task:cycle-b" "SWE-084" "ev:cycle-b" 'cycle-b
                      req-type ev-type
                      (lambda (req)
                        (set-box! ran-calls (+ 1 (unbox ran-calls)))
                        (.o (kind := 'synthesized-patch) (action := 'b) (targets := '())))
                      (.o (action := 'b) (targets := '()))
                      required-evidence-ids: '("ev:cycle-a")
                      effect-class: 'pure-cas))
             (cyclic-plan
              ((.get wf choice-flow-plan)
               (.o (gitops := (list task-a task-b)))
               choice-key: 'scope-decision))
             (res ((.get wf execute-choice-worlds) choice-sol runner cyclic-plan)))
        (check-equal? (.get res admitted?) #f)
        (check-equal? (.get res reason) 'funflow-dag-cycle-detected)
        (check-equal? (.get res total-executions) 0)
        (check-equal? (unbox ran-calls) 0)))

    (test-case "9. SdlcLifecycleCaseProfile solves competing design and RFC 0004 retirement choices with provenance and shared CAS"
      (let* ((sdlc-prof (.get wf profiles sdlc-lifecycle))
             (sol ((.get sdlc-prof solve-choices)
                   "change:rfc-0004-retire"
                   '(design-event-sourced design-direct-cutover design-legacy-keep)
                   verified?: #t
                   retirement-clear?: #t
                   approval-live?: #f
                   refuted-designs: '(design-legacy-keep)))
             (worlds (.get sol worlds))
             (designs (map (lambda (w) (.get w design-decision)) worlds))
             (runner ((.get wf make-pure-runner)))
             (req-type (.get wf patch-request-type))
             (ev-type (.get wf patch-evidence-type))
             (shared-calls (box 0))
             (shared-audit
              ((.get wf pure-task-node)
               "task:sdlc-retirement-audit" "sdlc.retirement-impact-audited" "ev:retirement-audit"
               'sdlc-retirement-audit req-type ev-type
               (lambda (req)
                 (set-box! shared-calls (+ 1 (unbox shared-calls)))
                 (.o (kind := 'synthesized-patch) (action := (.get req action)) (targets := '())))
               (.o (action := 'audit-retirement) (targets := '()))
               effect-class: 'pure-cas))
             (make-design-check
              (lambda (d)
                ((.get wf pure-task-node)
                 (string-append "task:check:" (symbol->string d))
                 "sdlc.design-alternatives-assessed"
                 (string-append "ev:check:" (symbol->string d))
                 d req-type ev-type
                 (lambda (req)
                   (.o (kind := 'synthesized-patch) (action := (.get req action)) (targets := '())))
                 (.o (action := d) (targets := '()))
                 effect-class: 'pure-cas)))
             (plan ((.get sdlc-prof build-choice-plan)
                    (.o (design-event-sourced := (list (make-design-check 'design-event-sourced)))
                        (design-direct-cutover := (list (make-design-check 'design-direct-cutover))))
                    choice-key: (.get sdlc-prof choice-key)
                    shared-prefix: (list shared-audit)))
             (exec ((.get sdlc-prof execute-plan) sol runner plan approval-live?: #f)))
        (check-equal? (.get sdlc-prof case-id) 'aitia/case/sdlc-lifecycle)
        ;; Refuted design pruned; 2 surviving competing designs with provenance!
        (check-equal? (.get sol choice-status) 'competing-worlds)
        (check-equal? (.get sol world-count) 2)
        (check (and (member 'design-event-sourced designs) #t) => #t)
        (check (and (member 'design-direct-cutover designs) #t) => #t)
        (check-equal? (member 'design-legacy-keep designs) #f)
        (check (pair? (.get (car worlds) design-provenance)) => #t)
        ;; Shared retirement audit runs ONCE across both competing design worlds!
        (check-equal? (.get exec admitted?) #t)
        (check-equal? (unbox shared-calls) 1)
        (check-equal? (.get exec total-cas-hits) 1)
        (check-equal? (.get exec total-executions) 3)
        (check-equal? (.get exec action-authorized?) #f)))

    (test-case "10. Incremental ASCENT Session propagates monotone evidence appends and atomic premise retractions across cuts"
      (let* ((sess ((.get wf open-obligation-session)
                    '(SWE-083 SWE-084 gitops.commit-semantics gitops.commit-review-approved gitops.commit-applied)
                    '((gitops.commit-semantics . SWE-083)
                      (gitops.commit-semantics . SWE-084)
                      (gitops.commit-review-approved . gitops.commit-semantics)
                      (gitops.commit-applied . gitops.commit-review-approved))
                    '((SWE-083 . ev:SWE-083)
                      (SWE-084 . ev:SWE-084)
                      (gitops.commit-semantics . ev:gitops-commit-semantics)
                      (gitops.commit-review-approved . ev:gitops-human-approval)
                      (gitops.commit-applied . ev:gitops-commit-receipt))
                    live-evidence: '()
                    active-defeaters: '(gitops.commit-review-approved)))
             (s0 ((.get wf session-snapshot) sess))
             (s1 ((.get wf session-append-evidence!) sess 'ev:SWE-083))
             (s2 ((.get wf session-append-evidence!) sess 'ev:SWE-084))
             (s3 ((.get wf session-append-evidence!) sess 'ev:gitops-commit-semantics))
             (s4 ((.get wf session-retract-evidence!) sess '(ev:SWE-083))))
        ;; Initially 0 discharged, all 5 unsatisfied
        (check-equal? (.get s0 discharged) '())
        (check-equal? (length (.get s0 unsatisfied)) 5)
        ;; Monotone append discharges SWE-083, SWE-084, then gitops.commit-semantics
        (check (and (member 'SWE-083 (.get s1 discharged)) #t) => #t)
        (check (and (member 'SWE-084 (.get s2 discharged)) #t) => #t)
        (check (and (member 'gitops.commit-semantics (.get s3 discharged)) #t) => #t)
        (check (and (member 'gitops.commit-review-approved (.get s3 unsatisfied)) #t) => #t)
        (check (and (member 'gitops.commit-applied (.get s3 unsatisfied)) #t) => #t)
        ;; Transactional retraction of ev:SWE-083 transitively re-opens semantics while preserving SWE-084!
        (check-equal? (member 'SWE-083 (.get s4 discharged)) #f)
        (check-equal? (member 'gitops.commit-semantics (.get s4 discharged)) #f)
        (check (and (member 'SWE-084 (.get s4 discharged)) #t) => #t)
        (check-equal? (.get s4 action-authorized?) #f)))))
