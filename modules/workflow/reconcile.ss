;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: compiled sibling module bridging Lambda Aitia's native
;;; gerbil-ascent GitOps semantics directly onto Agentic AI Lab's
;;; `modules/graph-engine` (`obligation-graph`, `ascent-reconciler`,
;;; `dag-frontier-scheduler`) and `modules/funflow` (`durable-dag`, `cas-store`,
;;; `governed-runner`, leaf `control-plane/*`).
;;;
;;; Strictly typed: ZERO `Any` / `Fun Any <- Any`. Every FunFlow capability
;;; declares concrete POO input/output Record contracts validated on every edge.

(import (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :clan/poo/type Fun validate)
        (only-in :std/list/list every filter find)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/task
                 make-pure-task)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/flow
                 flow? task-flow flow-arr flow-then flow-fanout flow-input-contract)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/runner
                 make-runner)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/strategy
                 make-local-eager-strategy)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/control-plane/runtime-adapter
                 make-request-only-adapter)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/cas-store
                 make-funflow-cas-store)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/durable-dag
                 ParallelFrontierStrategy.)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/governed-runner
                 make-governed-funflow-runner governed-funflow-run)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/obligation-graph
                 make-obligation make-hypothesis make-evidence-fact
                 make-deterministic-task-node deterministic-task-node?
                 make-synthesis-hole make-obligation-graph obligation-graph?
                 obligation-graph-premise-digest
                 obligation-graph-with-evidence obligation-graph-with-tasks
                 obligation-graph-live-evidence
                 obligation-graph-mark-task-completed
                 obligation-graph-mark-hole-attempted
                 obligation-graph-record-branch-matrix
                 obligation-graph-add-human-inbox
                 obligation-graph-apply-event)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/ascent-reconciler
                 ascent-reconcile-frontier)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/dag-frontier-scheduler
                 plan-funflow-c4-frontier)
        (only-in "../gitops/commit-semantics.ss" gitops-commit-semantics)
        (only-in "../gitops/commit-evidence.ss" gitops-commit-evidence)
        (only-in "./choice.ss"
                 workflow-solve-gitops-choices
                 workflow-solve-sdlc-choices
                 workflow-choice-hypotheses
                 workflow-choice-arrow-entry
                 workflow-choice-flow-plan
                 workflow-execute-choice-worlds
                 workflow-converge-choice-worlds
                 workflow-open-obligation-session
                 workflow-session-snapshot
                 workflow-session-append-evidence!
                 workflow-session-retract-evidence!)
        (only-in "./types.ss"
                 WorkflowEffectClass WorkflowOriginTier WorkflowTypeDescriptor
                 GitOpsCutRequest GitOpsCutEvidence
                 GitOpsConfigRequest GitOpsConfigEvidence
                 GitOpsSemanticsRequest GitOpsSemanticsEvidence
                 GitOpsApplyRequest GitOpsApplyEvidence))

(export workflow-make-pure-runner
        workflow-flow-arr
        workflow-flow-then
        workflow-flow-fanout
        workflow-arrow-task-node
        workflow-choice-arrow-entry
        workflow-pure-task-node
        workflow-evidence-fact
        workflow-with-evidence
        workflow-live-evidence
        workflow-dag-patch
        workflow-competing-branches
        workflow-raw-tool-call
        workflow-solve-gitops-choices
        workflow-solve-sdlc-choices
        workflow-choice-flow-plan
        workflow-execute-choice-worlds
        workflow-converge-choice-worlds
        workflow-open-obligation-session
        workflow-session-snapshot
        workflow-session-append-evidence!
        workflow-session-retract-evidence!
        workflow-gitops-commit-graph
        workflow-reconcile-frontier
        workflow-admit-proposal
        workflow-reconcile-step
        workflow-reconcile
        workflow-reconcile-events
        workflow-retract-premise
        workflow-plan-protocol-step)

(def +cut-observe-sig+ (Fun GitOpsCutEvidence <- GitOpsCutRequest))
(def +config-audit-sig+ (Fun GitOpsConfigEvidence <- GitOpsConfigRequest))
(def +semantics-assess-sig+ (Fun GitOpsSemanticsEvidence <- GitOpsSemanticsRequest))
(def +apply-commit-sig+ (Fun GitOpsApplyEvidence <- GitOpsApplyRequest))

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (workflow-make-pure-runner
      env-digest: (env-digest "sha256:lambda-aitia-workflow-v1")
      source-cut: (source-cut "cut-1"))
  (make-governed-funflow-runner
   (make-runner (make-local-eager-strategy) (make-request-only-adapter))
   cas-store: (make-funflow-cas-store)
   env-digest: env-digest
   source-cut: source-cut))

(def (make-typed-capability-flow name signature proc)
  (task-flow name (make-pure-task name signature proc)))

;;; Native FunFlow Arrow combinators with strict POO Type descriptors (zero `Any`).
(def (workflow-flow-arr name input-type output-type proc)
  (validate WorkflowTypeDescriptor input-type)
  (validate WorkflowTypeDescriptor output-type)
  (flow-arr name (Fun output-type <- input-type) proc))

(def (workflow-flow-then name left right)
  (flow-then name left right))

(def (workflow-flow-fanout name left right)
  (flow-fanout name left right))

;;; Wrap ANY native FunFlow `flow?` Arrow (sequential `flow-then`, parallel
;;; `flow-fanout`, `flow-arr`, `flow-map`) directly as a DeterministicTaskNode.
(def (workflow-arrow-task-node
      task-id obligation-id produces-evidence-id arrow input
      required-evidence-ids: (required-evidence-ids '())
      premise-ids: (premise-ids '())
      read-footprint: (read-footprint '())
      write-footprint: (write-footprint '())
      effect-class: (effect-class 'pure-cas))
  (unless (flow? arrow)
    (error "workflow-arrow-task-node expects a native FunFlow flow? Arrow" arrow))
  (validate WorkflowEffectClass effect-class)
  (validate (flow-input-contract arrow) input)
  (make-deterministic-task-node
   task-id obligation-id produces-evidence-id
   arrow
   input
   required-evidence-ids: required-evidence-ids
   premise-ids: premise-ids
   read-footprint: read-footprint
   write-footprint: write-footprint
   effect-class: effect-class))

;;; Construct a strongly typed FunFlow deterministic task node.
;;; Both `input-type` and `output-type` must be explicit POO Type descriptors,
;;; and `input` is validated against `input-type` before entering the DAG.
(def (workflow-pure-task-node
      task-id obligation-id produces-evidence-id flow-name
      input-type output-type proc input
      required-evidence-ids: (required-evidence-ids '())
      premise-ids: (premise-ids '())
      read-footprint: (read-footprint '())
      write-footprint: (write-footprint '())
      effect-class: (effect-class 'pure-cas))
  (validate WorkflowTypeDescriptor input-type)
  (validate WorkflowTypeDescriptor output-type)
  (validate WorkflowEffectClass effect-class)
  (validate input-type input)
  (let ((sig (Fun output-type <- input-type)))
    (make-deterministic-task-node
     task-id obligation-id produces-evidence-id
     (make-typed-capability-flow flow-name sig proc)
     input
     required-evidence-ids: required-evidence-ids
     premise-ids: premise-ids
     read-footprint: read-footprint
     write-footprint: write-footprint
     effect-class: effect-class)))

(def (workflow-evidence-fact
      evidence-id payload
      cut: (cut 1)
      premise-ids: (premise-ids '())
      origin-tier: (origin-tier 'observed-fact))
  (validate WorkflowOriginTier origin-tier)
  (make-evidence-fact
   evidence-id payload cut: cut premise-ids: premise-ids origin-tier: origin-tier))

(def (workflow-with-evidence graph fact)
  (obligation-graph-with-evidence graph fact))

(def (workflow-live-evidence graph)
  (obligation-graph-live-evidence graph))

(def (workflow-dag-patch tasks)
  (.o (kind := 'typed-funflow-dag-patch)
      (tasks := tasks)))

(def (workflow-competing-branches branches)
  (.o (kind := 'bounded-competing-branches)
      (branches := branches)))

(def (workflow-raw-tool-call tool-name args)
  (.o (kind := 'raw-single-step-tool-call)
      (tool-name := tool-name)
      (args := args)))

(def (observation-for-obligation observations obligation-id)
  (find (lambda (obs)
          (and (object? obs)
               (.slot? obs 'obligation)
               (equal? (.get obs obligation) obligation-id)
               (eq? (.get obs outcome) 'passed)))
        observations))

;;; Build an immutable Lab `ObligationGraph.` directly from Lambda Aitia's
;;; two-stage native `gerbil-ascent` pipeline:
;;;   Stage 1: stratified `gitops-commit-semantics` + `gitops-commit-evidence`
;;;   Stage 2: Lean-verified `relational-choice-program` (`workflow-solve-gitops-choices`)
(def (workflow-gitops-commit-graph
      naming cut sources paths proposals
      graph-id: (graph-id "aitia.gitops-commit")
      cut-index: (cut-index 1)
      observations: (observations '())
      approval-live?: (approval-live? #f)
      cedar-grant-live?: (cedar-grant-live? #t)
      candidate-offers: (candidate-offers '())
      forbidden-scopes: (forbidden-scopes '())
      state-budget: (state-budget 32)
      extra-hypotheses: (extra-hypotheses '())
      extra-tasks: (extra-tasks '()))
  (let* ((commit-id (.get cut commit))
         (cut-premise (string-append "premise:cut:" commit-id))
         (semantics (gitops-commit-semantics naming cut sources paths proposals))
         (choice-solution (workflow-solve-gitops-choices
                           semantics cut
                           approval-live?: approval-live?
                           candidate-offers: candidate-offers
                           forbidden-scopes: forbidden-scopes
                           state-budget: state-budget))
         (evidence-view (gitops-commit-evidence cut '("SWE-083" "SWE-084") observations))
         (swe-83-ok? (and (observation-for-obligation observations "SWE-083") #t))
         (swe-84-ok? (and (observation-for-obligation observations "SWE-084") #t))
         (eligible-rows (.get semantics eligible))
         (eligible? (and (pair? eligible-rows)
                         (null? (.get semantics open))
                         (null? (.get semantics unscoped-paths))))
         (live-evidence
          (append
           (if swe-83-ok?
             (list (make-evidence-fact
                    "ev:SWE-083"
                    (.o (kind := 'observed-cut) (commit := commit-id) (paths := paths))
                    cut: cut-index
                    premise-ids: (list cut-premise)
                    origin-tier: 'observed-fact))
             '())
           (if swe-84-ok?
             (list (make-evidence-fact
                    "ev:SWE-084"
                    (.o (kind := 'audited-config) (commit := commit-id))
                    cut: cut-index
                    premise-ids: (list cut-premise)
                    origin-tier: 'observed-fact))
             '())
           (if approval-live?
             (list (make-evidence-fact
                    "ev:gitops-human-approval"
                    (.o (kind := 'signed-commit-approval) (commit := commit-id))
                    cut: cut-index
                    premise-ids: (list cut-premise)
                    origin-tier: 'human-decision))
             '())))
         (obligations
          (list
           (make-obligation
            "SWE-083"
            title: "Record complete working-copy change inventory at current cut"
            required-evidence-ids: '("ev:SWE-083")
            premise-ids: (list cut-premise))
           (make-obligation
            "SWE-084"
            title: "Audit recorded project and VCS configuration at current cut"
            required-evidence-ids: '("ev:SWE-084")
            premise-ids: (list cut-premise))
           (make-obligation
            "gitops.commit-semantics"
            title: "Ground commit title, scope, reference, and language via native ASCENT"
            required-evidence-ids: '("ev:gitops-commit-semantics")
            depends-on: '("SWE-083" "SWE-084")
            premise-ids: (list cut-premise))
           (make-obligation
            "gitops.commit-review-approved"
            title: "Human audit decision bound to current cut and rendered preview"
            required-evidence-ids: '("ev:gitops-human-approval")
            depends-on: '("gitops.commit-semantics")
            active-defeaters: (if approval-live? '() '(missing-signed-commit-approval))
            premise-ids: (list cut-premise))
           (make-obligation
            "gitops.commit-applied"
            title: "Apply reviewed commit through fenced durable admission"
            required-evidence-ids: '("ev:gitops-commit-receipt")
            depends-on: '("gitops.commit-review-approved")
            active-defeaters: (if approval-live? '() '(fenced-effect-requires-human-approval))
            premise-ids: (list cut-premise))))
         (det-tasks
          (append
           (list
            (make-deterministic-task-node
             "task:jj-observe-cut"
             "SWE-083"
             "ev:SWE-083"
             (make-typed-capability-flow 'jj-observe-cut +cut-observe-sig+
               (lambda (req)
                 (.o (kind := 'observed-cut)
                     (commit := (.get req commit))
                     (paths := (.get req paths)))))
             (.o (commit := commit-id) (paths := paths))
             premise-ids: (list cut-premise)
             read-footprint: '(workspace-tree)
             write-footprint: '()
             effect-class: 'verified-epistemic)
            (make-deterministic-task-node
             "task:jj-config-audit"
             "SWE-084"
             "ev:SWE-084"
             (make-typed-capability-flow 'jj-config-audit +config-audit-sig+
               (lambda (req)
                 (.o (kind := 'audited-config)
                     (commit := (.get req commit)))))
             (.o (commit := commit-id))
             premise-ids: (list cut-premise)
             read-footprint: '(jj-configuration)
             write-footprint: '()
             effect-class: 'verified-epistemic))
           (if eligible?
             (list
              (make-deterministic-task-node
               "task:gitops-assess-semantics"
               "gitops.commit-semantics"
               "ev:gitops-commit-semantics"
               (make-typed-capability-flow 'gitops-assess-semantics +semantics-assess-sig+
                 (lambda (req)
                   (.o (kind := 'semantics-eligible)
                       (commit := (.get req commit))
                       (eligible := (.get req eligible)))))
               (.o (commit := commit-id) (eligible := eligible-rows))
               required-evidence-ids: '("ev:SWE-083" "ev:SWE-084")
               premise-ids: (list cut-premise)
               read-footprint: '(commit-semantics)
               write-footprint: '()
               effect-class: 'pure-cas))
             '())
           (if approval-live?
             (list
              (make-deterministic-task-node
               "task:gitops-apply-commit"
               "gitops.commit-applied"
               "ev:gitops-commit-receipt"
               (make-typed-capability-flow 'gitops-apply-commit +apply-commit-sig+
                 (lambda (req)
                   (.o (kind := 'commit-applied-receipt)
                       (commit := (.get req commit)))))
               (.o (commit := commit-id))
               required-evidence-ids: '("ev:gitops-human-approval" "ev:gitops-commit-semantics")
               premise-ids: (list cut-premise)
               read-footprint: '(commit-semantics approval-journal)
               write-footprint: '(jj-commit-history)
               effect-class: 'fenced-effect
               idempotency-key: (string-append "idem:gitops-apply:" commit-id)))
             '())
           extra-tasks))
         (synthesis-holes
          (list
           (make-synthesis-hole
            "hole:gitops-commit-narration-or-scope"
            "gitops.commit-semantics"
            description: "Propose a bounded TypedFunflowDagPatch or BoundedCompetingBranches to resolve unscoped paths or incomplete commit narration."
            premise-ids: (list cut-premise)
            max-branches: 4)))
         (hypotheses (append (workflow-choice-hypotheses choice-solution) extra-hypotheses)))
    (.o (:: @ (make-obligation-graph
               graph-id
               cut: cut-index
               obligations: obligations
               hypotheses: hypotheses
               evidence: live-evidence
               det-tasks: det-tasks
               synthesis-holes: synthesis-holes
               cedar-grant-live?: cedar-grant-live?))
        (semantics-assessment := semantics)
        (choice-solution := choice-solution)
        (evidence-assessment := evidence-view)
        (cut-premise := cut-premise))))

;;; Compute BOTH the native ASCENT obligation fixed-point frontier AND the
;;; C4 FunFlow parallel frontier plan in one pure call (`action-authorized?: #f`).
(def (workflow-reconcile-frontier
      graph
      strategy: (strategy #f)
      completed-cas: (completed-cas #f))
  (unless (obligation-graph? graph)
    (error "workflow-reconcile-frontier expects an ObligationGraph" graph))
  (let* ((strat (or strategy ParallelFrontierStrategy.))
         (frontier (ascent-reconcile-frontier graph))
         (ready-tasks (.ref frontier 'ready-deterministic-tasks))
         (funflow-plan
          (if (pair? ready-tasks)
            (plan-funflow-c4-frontier graph
                                      ready-tasks
                                      strategy: strat
                                      completed-cas: completed-cas)
            #f)))
    (.o (schema := "lambda-aitia.workflow-frontier.v1")
        (frontier := frontier)
        (funflow-plan := funflow-plan)
        (choice-solution := (opt-ref graph 'choice-solution #f))
        (frontier-mode := (.ref frontier 'frontier-mode))
        (quiescent? := (.ref frontier 'quiescent?))
        (discharged-obligations := (.ref frontier 'discharged-obligations))
        (unsatisfied-obligations := (.ref frontier 'unsatisfied-obligations))
        (blocked-on-human-obligations := (.ref frontier 'blocked-on-human-obligations))
        (ready-deterministic-tasks := ready-tasks)
        (ready-synthesis-holes := (.ref frontier 'ready-synthesis-holes))
        (refuted-hypotheses := (.ref frontier 'refuted-hypotheses))
        (unrefuted-hypotheses := (.ref frontier 'unrefuted-hypotheses))
        (epistemic-competition-status := (.ref frontier 'epistemic-competition-status))
        (action-authorized? := #f))))

;;; Evaluate EVERY bounded POO branch against EVERY active hypothesis in the
;;; graph, preserving contradictions, defeaters, and open questions without
;;; collapsing or granting authority (`action-authorized?: #f`).
(def (evaluate-branch-matrix branches hypotheses)
  (let ((rows
         (map (lambda (br)
                (let* ((bid (.ref br 'branch-id))
                       (supports (opt-ref br 'supports-hypotheses '()))
                       (contradicts (opt-ref br 'contradicts-hypotheses '()))
                       (open-qs (opt-ref br 'open-questions '()))
                       (assessments
                        (map (lambda (h)
                               (let ((hid (.ref h 'hypothesis-id)))
                                 (.o (hypothesis-id := hid)
                                     (relation := (cond
                                                   ((member hid contradicts) 'contradicts)
                                                   ((member hid supports) 'consistent-with)
                                                   (else 'undetermined)))
                                     (active-defeaters := (.ref h 'active-defeaters))
                                     (open-questions := (append (.ref h 'open-questions) open-qs)))))
                             hypotheses)))
                  (.o (branch-id := bid)
                      (description := (opt-ref br 'description ""))
                      (hypothesis-assessments := assessments)
                      (action-authorized? := #f))))
              branches)))
    (.o (kind := 'lambda-aitia.workflow.competing-branch-matrix.v1)
        (branch-count := (length branches))
        (hypothesis-count := (length hypotheses))
        (rows := rows)
        (action-authorized? := #f))))

;;; Fail-closed oracle proposal admission + full competing-branch matrix against
;;; EVERY active hypothesis in the ObligationGraph (`action-authorized?: #f`).
(def (workflow-admit-proposal graph proposal max-branches: (max-branches 4))
  (unless (obligation-graph? graph)
    (error "workflow-admit-proposal expects an ObligationGraph" graph))
  (let ((pkind (opt-ref proposal 'kind #f)))
    (cond
     ((eq? pkind 'raw-single-step-tool-call)
      (.o (schema := "lambda-aitia.workflow-proposal-admission.v1")
          (admitted? := #f)
          (reason := 'raw-single-step-tool-call-forbidden)
          (proposal-kind := pkind)
          (branch-matrix := #f)
          (action-authorized? := #f)))
     ((eq? pkind 'typed-funflow-dag-patch)
      (let* ((tasks (opt-ref proposal 'tasks '()))
             (ok? (and (pair? tasks)
                       (every (lambda (t)
                                (and (deterministic-task-node? t)
                                     (flow? (.ref t 'flow))))
                              tasks))))
        (.o (schema := "lambda-aitia.workflow-proposal-admission.v1")
            (admitted? := ok?)
            (reason := (if ok? 'typed-funflow-dag-patch-admitted 'invalid-funflow-dag-patch-contract))
            (proposal-kind := pkind)
            (branch-matrix := #f)
            (action-authorized? := #f))))
     ((eq? pkind 'bounded-competing-branches)
      (let* ((branches (opt-ref proposal 'branches '()))
             (ok? (and (pair? branches)
                       (<= (length branches) max-branches)
                       (every (lambda (b) (and (object? b) (.slot? b 'branch-id))) branches)))
             (matrix (and ok? (evaluate-branch-matrix branches (.ref graph 'hypotheses)))))
        (.o (schema := "lambda-aitia.workflow-proposal-admission.v1")
            (admitted? := ok?)
            (reason := (if ok? 'bounded-competing-branches-admitted 'unbounded-or-empty-competing-branches))
            (proposal-kind := pkind)
            (branch-matrix := matrix)
            (action-authorized? := #f))))
     (else
      (.o (schema := "lambda-aitia.workflow-proposal-admission.v1")
          (admitted? := #f)
          (reason := 'unknown-oracle-proposal-kind)
          (proposal-kind := pkind)
          (branch-matrix := #f)
          (action-authorized? := #f))))))

(def (execute-deterministic-task runner graph task)
  (let* ((tid (.ref task 'task-id))
         (ob-id (.ref task 'obligation-id))
         (ev-id (.ref task 'produces-evidence-id))
         (pdig (obligation-graph-premise-digest graph ob-id (.ref task 'premise-ids)))
         (res (governed-funflow-run
               runner
               (.ref task 'flow)
               (.ref task 'input)
               idempotency-key: (opt-ref task 'idempotency-key #f)
               idempotency-commits: (opt-ref task 'idempotency-commits '())
               sandbox-override: (opt-ref task 'sandbox-profile #f)
               env-digest-override: (opt-ref task 'env-digest #f)))
         (ev (make-evidence-fact
              ev-id
              (.ref res 'value)
              cut: (.ref graph 'cut)
              premise-ids: (.ref task 'premise-ids)
              origin-tier: 'observed-fact))
         (g1 (obligation-graph-with-evidence graph ev)))
    (obligation-graph-mark-task-completed g1 tid pdig)))

;;; Single incremental ASCENT + FunFlow reconciliation step (`reconcile-once` semantics).
(def (workflow-reconcile-step
      graph
      oracle-fn: (oracle-fn #f)
      funflow-runner: (funflow-runner #f)
      dag-strategy: (dag-strategy #f)
      completed-cas: (completed-cas #f))
  (let* ((strat (or dag-strategy ParallelFrontierStrategy.))
         (runner (or funflow-runner (workflow-make-pure-runner)))
         (frontier (ascent-reconcile-frontier graph))
         (mode (.ref frontier 'frontier-mode)))
    (cond
     ((eq? mode 'quiescent-fixed-point)
      (.o (graph := graph)
          (frontier := frontier)
          (mode := mode)
          (quiescent? := #t)
          (llm-calls-used := 0)
          (det-tasks-executed := 0)
          (action-authorized? := #f)))
     ((eq? mode 'blocked-on-governance)
      (let ((g1 (obligation-graph-add-human-inbox
                 graph
                 (.o (kind := 'governance-blocked)
                     (cut := (.ref graph 'cut))
                     (obligations := (.ref frontier 'blocked-on-human-obligations))))))
        (.o (graph := g1)
            (frontier := frontier)
            (mode := mode)
            (quiescent? := #t)
            (llm-calls-used := 0)
            (det-tasks-executed := 0)
            (action-authorized? := #f))))
     ((eq? mode 'dispatch-deterministic-funflow)
      (let* ((ready-tasks (.ref frontier 'ready-deterministic-tasks))
             (plan (plan-funflow-c4-frontier graph
                                             ready-tasks
                                             strategy: strat
                                             completed-cas: completed-cas))
             (batch (if (.ref plan 'valid?) (.ref plan 'parallel-batch) '()))
             (next-graph
              (let loop ((ts batch) (g graph))
                (if (null? ts)
                  g
                  (loop (cdr ts) (execute-deterministic-task runner g (car ts)))))))
        (.o (graph := next-graph)
            (frontier := frontier)
            (funflow-plan := plan)
            (mode := mode)
            (quiescent? := (null? batch))
            (llm-calls-used := 0)
            (det-tasks-executed := (length batch))
            (action-authorized? := #f))))
     ((eq? mode 'invoke-typed-synthesis-oracle)
      (let* ((hole (car (.ref frontier 'ready-synthesis-holes)))
             (g-marked (obligation-graph-mark-hole-attempted graph hole))
             (hyps (.ref frontier 'unrefuted-hypotheses)))
        (if (not (procedure? oracle-fn))
          (let ((g-inbox (obligation-graph-add-human-inbox
                          g-marked
                          (.o (kind := 'synthesis-hole-no-oracle)
                              (hole-id := (.ref hole 'hole-id))))))
            (.o (graph := g-inbox)
                (frontier := frontier)
                (mode := mode)
                (quiescent? := #f)
                (llm-calls-used := 0)
                (det-tasks-executed := 0)
                (action-authorized? := #f)))
          (let* ((proposal (oracle-fn hole frontier hyps))
                 (checked (and proposal
                               (workflow-admit-proposal
                                g-marked proposal
                                max-branches: (opt-ref hole 'max-branches 4)))))
            (cond
             ((not (and checked (.get checked admitted?)))
              (let ((g-inbox (obligation-graph-add-human-inbox
                              g-marked
                              (.o (kind := 'oracle-proposal-rejected)
                                  (hole-id := (.ref hole 'hole-id))
                                  (reason := (if checked (.get checked reason) 'oracle-returned-empty))))))
                (.o (graph := g-inbox)
                    (frontier := frontier)
                    (mode := mode)
                    (quiescent? := #f)
                    (llm-calls-used := 1)
                    (det-tasks-executed := 0)
                    (proposal-admission := checked)
                    (action-authorized? := #f))))
             ((eq? (.get checked proposal-kind) 'typed-funflow-dag-patch)
              (let ((g-patched (obligation-graph-with-tasks g-marked (.ref proposal 'tasks))))
                (.o (graph := g-patched)
                    (frontier := frontier)
                    (mode := mode)
                    (quiescent? := #f)
                    (llm-calls-used := 1)
                    (det-tasks-executed := 0)
                    (proposal-admission := checked)
                    (action-authorized? := #f))))
             (else
              (let ((g-matrix (obligation-graph-record-branch-matrix
                               g-marked (.get checked branch-matrix))))
                (.o (graph := g-matrix)
                    (frontier := frontier)
                    (mode := mode)
                    (quiescent? := #f)
                    (llm-calls-used := 1)
                    (det-tasks-executed := 0)
                    (proposal-admission := checked)
                    (action-authorized? := #f)))))))))
     (else
      (error "unknown ASCENT frontier mode" mode)))))

;;; Converge an ObligationGraph to fixed-point quiescence with bounded steps.
(def (workflow-reconcile
      graph
      oracle-fn: (oracle-fn #f)
      funflow-runner: (funflow-runner #f)
      dag-strategy: (dag-strategy #f)
      completed-cas: (completed-cas #f))
  (let ((runner (or funflow-runner (workflow-make-pure-runner)))
        (max-steps (opt-ref graph 'max-reconcile-steps 32)))
    (let loop ((g graph) (steps 0) (llm-calls 0) (det-tasks 0))
      (if (>= steps max-steps)
        (.o (graph := g)
            (final-frontier := (ascent-reconcile-frontier g))
            (quiescent? := #f)
            (steps := steps)
            (total-llm-calls := llm-calls)
            (total-det-tasks := det-tasks)
            (action-authorized? := #f))
        (let ((step (workflow-reconcile-step
                     g
                     oracle-fn: oracle-fn
                     funflow-runner: runner
                     dag-strategy: dag-strategy
                     completed-cas: completed-cas)))
          (if (.get step quiescent?)
            (.o (graph := (.get step graph))
                (final-frontier := (ascent-reconcile-frontier (.get step graph)))
                (quiescent? := #t)
                (steps := (+ steps 1))
                (total-llm-calls := (+ llm-calls (.get step llm-calls-used)))
                (total-det-tasks := (+ det-tasks (.get step det-tasks-executed)))
                (action-authorized? := #f))
            (loop (.get step graph)
                  (+ steps 1)
                  (+ llm-calls (.get step llm-calls-used))
                  (+ det-tasks (.get step det-tasks-executed)))))))))

;;; Event-driven incremental reconciliation over bitemporal events.
(def (workflow-reconcile-events
      graph events
      oracle-fn: (oracle-fn #f)
      funflow-runner: (funflow-runner #f)
      dag-strategy: (dag-strategy #f)
      completed-cas: (completed-cas #f))
  (let ((runner (or funflow-runner (workflow-make-pure-runner))))
    (let loop ((evts events) (g graph) (reports '()))
      (if (null? evts)
        (.o (graph := g)
            (final-frontier := (ascent-reconcile-frontier g))
            (reports := (reverse reports))
            (action-authorized? := #f))
        (let* ((g1 (obligation-graph-apply-event g (car evts)))
               (rep (workflow-reconcile g1
                                        oracle-fn: oracle-fn
                                        funflow-runner: runner
                                        dag-strategy: dag-strategy
                                        completed-cas: completed-cas)))
          (loop (cdr evts) (.get rep graph) (cons rep reports)))))))

;;; Selective bitemporal premise retraction when the workspace cut changes.
(def (workflow-retract-premise graph premise-id new-cut: (new-cut #f))
  (unless (obligation-graph? graph)
    (error "workflow-retract-premise expects an ObligationGraph" graph))
  (let ((next-cut (or new-cut (+ 1 (.ref graph 'cut)))))
    (obligation-graph-apply-event
     graph
     (.o (event-kind := 'premise-retracted)
         (premise-id := premise-id)
         (cut := next-cut)))))

;;; Scheme-owned 4-state Inversion-of-Control protocol step (RFC 0008):
;;;   1. `need-host-frames`: Scheme declares missing read-only HostCapability frames;
;;;      Rust dispatches them blindly via `HostCapabilityRegistry::dispatch_batch`.
;;;   2. `need-synthesis-or-human`: all HostRead receipts present, but graph has open
;;;      synthesis holes, competing worlds, or human audit gates.
;;;   3. `need-fenced-frames`: unique grounded world with live approval awaiting a
;;;      fenced effect frame (`action-authorized?: #f` at plan boundary).
;;;   4. `quiescent`: all obligations discharged with zero open holes or human gates.
(def (workflow-plan-protocol-step ctx)
  (unless (object? ctx)
    (error "workflow-plan-protocol-step expects a POO protocol context" ctx))
  (let* ((case-id (opt-ref ctx 'case-id 'aitia/case/gitops-commit))
         (directory (opt-ref ctx 'directory "."))
         (requested-paths (opt-ref ctx 'requested-paths '()))
         (model-check-enabled? (opt-ref ctx 'model-check-enabled? #t))
         (include-pr? (and (opt-ref ctx 'include-pr-observation? #f) #t))
         (receipts (opt-ref ctx 'receipts (.o)))
         (has-jj-cut? (and (object? receipts) (opt-ref receipts 'jj-observe-cut #f) #t))
         (has-sysml-scopes? (and (object? receipts)
                                 (.slot? receipts 'sysml-project-scopes)
                                 (list? (.ref receipts 'sysml-project-scopes))))
         (has-pr? (and (object? receipts) (opt-ref receipts 'github-observe-pr #f) #t))
         (missing-frames
          (append
           (if has-jj-cut?
             '()
             (list (.o (capability := "gitops.jj.observe-cut")
                       (effect-class := 'host-read)
                       (receipt-key := "gitops.jj.observe-cut")
                       (payload := (.o (directory := directory)
                                       (requested-paths := requested-paths))))))
           (if has-sysml-scopes?
             '()
             (list (.o (capability := "sysml.project-scopes")
                       (effect-class := 'host-read)
                       (receipt-key := "sysml.project-scopes")
                       (payload := (.o (directory := directory)
                                       (enabled := model-check-enabled?))))))
           (if (and include-pr? (not has-pr?))
             (list (.o (capability := "gitops.github.observe-pr")
                       (effect-class := 'host-read)
                       (receipt-key := "gitops.github.observe-pr")
                       (payload := (.o (directory := directory)))))
             '()))))
    (if (pair? missing-frames)
      (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
          (schema := "lambda-aitia.workflow-protocol-step.v1")
          (state := 'need-host-frames)
          (case-id := case-id)
          (frames := missing-frames)
          (graph := #f)
          (initial-frontier := #f)
          (report := #f)
          (final-frontier := #f)
          (proposal-admission := #f)
          (action-authorized? := #f))
      (let* ((naming (.ref ctx 'naming))
             (cut (.ref ctx 'cut))
             (sources (opt-ref ctx 'sources '()))
             (paths (opt-ref ctx 'paths '()))
             (proposals (opt-ref ctx 'proposals '()))
             (observations (opt-ref ctx 'observations '()))
             (approval-live? (and (opt-ref ctx 'approval-live? #f) #t))
             (run-reconcile? (opt-ref ctx 'reconcile? #t))
             (proposal (opt-ref ctx 'proposal #f))
             (graph (workflow-gitops-commit-graph
                     naming cut sources paths proposals
                     observations: observations
                     approval-live?: approval-live?))
             (initial (workflow-reconcile-frontier graph))
             (proposal-res (and proposal (workflow-admit-proposal graph proposal)))
             (report (if run-reconcile? (workflow-reconcile graph) #f))
             (final-frontier (if report (.ref report 'final-frontier) (.get initial frontier)))
             (choice-sol (.get graph choice-solution))
             (unsat (.ref final-frontier 'unsatisfied-obligations))
             (blocked (.ref final-frontier 'blocked-on-human-obligations))
             (holes (.ref final-frontier 'ready-synthesis-holes))
             (state
              (cond
               ((and (null? unsat) (null? blocked) (null? holes))
                'quiescent)
               ((and approval-live?
                     (= (.get choice-sol world-count) 1)
                     (eq? (.get (car (.get choice-sol worlds)) dispatch-decision) 'fenced-apply)
                     (null? blocked)
                     (null? holes))
                'need-fenced-frames)
               (else
                'need-synthesis-or-human))))
        (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
            (schema := "lambda-aitia.workflow-protocol-step.v1")
            (state := state)
            (case-id := case-id)
            (frames := '())
            (graph := graph)
            (initial-frontier := initial)
            (report := report)
            (final-frontier := final-frontier)
            (proposal-admission := proposal-res)
            (action-authorized? := #f))))))
