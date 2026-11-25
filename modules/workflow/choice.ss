;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Stage 2 native `gerbil-ascent` Finite-Choice solver and
;;; cross-world FunFlow CAS execution bridge (RFC 0008).
;;;
;;; Architecture (Two-Stage Pure Relational Pipeline + Shared FunFlow CAS):
;;;   Stage 1 (stratified `gitops-commit-semantics`): computes negated/derived
;;;     facts (affected SysML v2 scopes, unscoped paths, open violations,
;;;     eligible proposals).
;;;   Stage 2 (Lean-verified `relational-choice-program` + `relational-choice-solve`
;;;     with `provenance?: #t`):
;;;     - `closed` rules enforce hard graph/SysML/policy invariants:
;;;         * singleton closed intersection -> forced `'deduction` (0 LLM, 0 branching)
;;;         * empty closed intersection     -> automatic contradiction pruning
;;;     - `open` rules admit bounded Agent/LLM divergent offers & cross-scope
;;;       candidates without overriding closed invariants.
;;;     - Exhaustive search returns all consistent saturated worlds `M_1..M_k`
;;;       with detached `provenance?: #t` derivation witnesses.
;;;   Stage 3 (`workflow-execute-choice-worlds`):
;;;     - Executes typed FunFlow DAG tasks across surviving worlds against ONE
;;;       shared `GovernedFunflowRunner` (`FunflowCasStore`), so shared read-only
;;;       prefixes execute ONCE (`cas-hit?: #t` on subsequent worlds).
;;;     - Strictly blocks `FencedEffect.` tasks whenever `world-count != 1`,
;;;       human approval is absent, or `dispatch-decision != 'fenced-apply`.

(import (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :clan/poo/type validate)
        (only-in :std/list/list every filter delete-duplicates/hash)
        (only-in :gerbil-ascent/program/api
                 relational-choice-program
                 relational-choice-solve
                 relational-program-query)
        (only-in :tao3k/agentic-ai-lab/modules/funflow/governed-runner
                 governed-funflow-run)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/obligation-graph
                 make-hypothesis deterministic-task-node?)
        (only-in "./objects.ss" ChoiceFlowPlan.)
        (only-in "./types.ss"
                 ChoiceSolutionType
                 ChoiceFlowPlanType
                 GovernedRunnerType))

(export workflow-solve-gitops-choices
        workflow-choice-hypotheses
        workflow-choice-flow-plan
        workflow-execute-choice-worlds)

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (as-symbol value)
  (cond
   ((symbol? value) value)
   ((string? value) (string->symbol value))
   (else (error "expected symbol or string for Finite-Choice scalar" value))))

(def (normalize-symbol-list values)
  (delete-duplicates/hash (map as-symbol values)))

(def (first-choice-value rows)
  (and (pair? rows) (pair? (car rows)) (pair? (cdar rows))
       (cadar rows)))

(def (first-derivation-kind provenance-steps)
  (and (pair? provenance-steps) (pair? (car provenance-steps))
       (caar provenance-steps)))

;;; Stage 2: Native Lean-verified Finite-Choice solver over Stage 1 GitOps
;;; stratified semantics + bounded Agent/LLM open offers + hard exclusions.
(def (workflow-solve-gitops-choices
      semantics cut
      approval-live?: (approval-live? #f)
      candidate-offers: (candidate-offers '())
      forbidden-scopes: (forbidden-scopes '())
      state-budget: (state-budget 32))
  (let* ((commit-id (.get cut commit))
         (cut-sym (string->symbol (string-append "cut:" commit-id)))
         (affected-syms
          (normalize-symbol-list
           (map car (.get semantics affected-scopes))))
         (unscoped-paths (.get semantics unscoped-paths))
         (open-rows (.get semantics open))
         (eligible-scope-syms
          (normalize-symbol-list
           (map (lambda (row) (list-ref row 3))
                (.get semantics eligible))))
         (offer-syms (normalize-symbol-list candidate-offers))
         (forbid-syms (normalize-symbol-list forbidden-scopes))
         (has-unscoped? (pair? unscoped-paths))
         (unique-scope-rows
          (if (and (not has-unscoped?) (= (length affected-syms) 1))
            (list (list cut-sym (car affected-syms)))
            '()))
         (multi-scope-rows
          (if (and (not has-unscoped?) (> (length affected-syms) 1))
            (map (lambda (s) (list cut-sym s)) affected-syms)
            '()))
         (has-unscoped-rows (if has-unscoped? (list (list cut-sym)) '()))
         (incomplete-rows
          (if (and (not has-unscoped?) (pair? open-rows))
            (list (list cut-sym))
            '()))
         (eligible-rows
          (if (and (not has-unscoped?) (null? open-rows))
            (map (lambda (s) (list cut-sym s)) eligible-scope-syms)
            '()))
         (no-eligible-rows
          (map (lambda (s) (list cut-sym s))
               (filter (lambda (s) (not (memq s eligible-scope-syms)))
                       affected-syms)))
         (approval-rows (if approval-live? (list (list cut-sym)) '()))
         (awaiting-rows (if approval-live? '() (list (list cut-sym))))
         (offer-rows (map (lambda (s) (list cut-sym s)) offer-syms))
         (forbid-rows (map (lambda (s) (list cut-sym s)) forbid-syms))
         (program
          (relational-choice-program
            (relation unique_affected_scope (cut scope) unique-scope-rows)
            (relation multi_affected_scope (cut scope) multi-scope-rows)
            (relation has_unscoped (cut) has-unscoped-rows)
            (relation incomplete_narration (cut) incomplete-rows)
            (relation eligible_proposal (cut scope) eligible-rows)
            (relation no_eligible_proposal (cut scope) no-eligible-rows)
            (relation approval_live (cut) approval-rows)
            (relation awaiting_approval (cut) awaiting-rows)
            (relation candidate_scope_offer (cut option) offer-rows)
            (relation forbidden_scope (cut option) forbid-rows)
            ;; Functional Finite-Choice attributes (at most 1 value per cut per world)
            (choice scope_decision (cut value))
            (choice dispatch_decision (cut value))
            ;; 1. Unique SysML v2 scope -> closed singleton -> forced 'deduction (0 branching!)
            (rule (closed (scope_decision ?c) (?s))
                  (unique_affected_scope ?c ?s))
            ;; 2. Unscoped paths -> closed 2-way competing scope hypotheses
            (rule (closed (scope_decision ?c)
                          ((value 'extend-existing-scope)
                           (value 'declare-new-scope)))
                  (has_unscoped ?c))
            ;; 3. Cross-scope change -> open alternatives over each affected SysML v2 scope
            (rule (open (scope_decision ?c) ?s)
                  (multi_affected_scope ?c ?s))
            ;; 4. Bounded Agent/LLM divergent offers (never overrides a closed invariant!)
            (rule (open (scope_decision ?c) ?opt)
                  (candidate_scope_offer ?c ?opt))
            ;; 5. Hard refutation / policy exclusion -> empty closed offer prunes branch!
            (rule (closed (scope_decision ?c) ())
                  (scope_decision ?c ?opt)
                  (forbidden_scope ?c ?opt))
            ;; 6. Dispatch decision driven by grounded scope + eligibility + human approval
            (rule (closed (dispatch_decision ?c) ((value 'fenced-apply)))
                  (scope_decision ?c ?s)
                  (eligible_proposal ?c ?s)
                  (approval_live ?c))
            (rule (closed (dispatch_decision ?c) ((value 'human-audit-gate)))
                  (scope_decision ?c ?s)
                  (eligible_proposal ?c ?s)
                  (awaiting_approval ?c))
            (rule (closed (dispatch_decision ?c) ((value 'epistemic-competition)))
                  (has_unscoped ?c))
            (rule (closed (dispatch_decision ?c) ((value 'epistemic-competition)))
                  (incomplete_narration ?c))
            (rule (closed (dispatch_decision ?c) ((value 'epistemic-competition)))
                  (multi_affected_scope ?c ?s)
                  (scope_decision ?c ?s)
                  (no_eligible_proposal ?c ?s))
            (limits 256 1024 1024)))
         (models (relational-choice-solve program state-budget: state-budget))
         (worlds
          (let loop ((ms models) (idx 0) (acc '()))
            (if (null? ms)
              (reverse acc)
              (let* ((m (car ms))
                     (scope-rows (relational-program-query m 'scope_decision))
                     (dispatch-rows (relational-program-query m 'dispatch_decision))
                     (scope-prov (relational-program-query m 'scope_decision provenance?: #t))
                     (dispatch-prov (relational-program-query m 'dispatch_decision provenance?: #t)))
                (loop (cdr ms)
                      (+ idx 1)
                      (cons (.o (kind := 'lambda-aitia.workflow.choice-world.v1)
                                (world-index := idx)
                                (scope-decision := (first-choice-value scope-rows))
                                (dispatch-decision := (first-choice-value dispatch-rows))
                                (scope-derivation-kind := (first-derivation-kind scope-prov))
                                (dispatch-derivation-kind := (first-derivation-kind dispatch-prov))
                                (scope-provenance := scope-prov)
                                (dispatch-provenance := dispatch-prov)
                                (action-authorized? := #f))
                            acc))))))
         (wcount (length worlds))
         (choice-status
          (cond
           ((= wcount 0) 'unsatisfiable)
           ((and (= wcount 1)
                 (let ((w (car worlds)))
                   (not (or (eq? (.get w scope-derivation-kind) 'branch)
                            (eq? (.get w dispatch-derivation-kind) 'branch)))))
            'unique-deduction)
           (else 'competing-worlds))))
    (.o (kind := 'lambda-aitia.workflow.choice-solution.v1)
        (schema := "lambda-aitia.workflow-choice-solution.v1")
        (commit := commit-id)
        (choice-status := choice-status)
        (world-count := wcount)
        (worlds := worlds)
        (unscoped-paths := unscoped-paths)
        (open-rows := open-rows)
        (action-authorized? := #f))))

(def (world->hypothesis world unscoped open-rows)
  (let ((sdec (.get world scope-decision))
        (ddec (.get world dispatch-decision))
        (widx (.get world world-index)))
    (cond
     ((eq? sdec 'extend-existing-scope)
      (make-hypothesis
       "hyp:scope-registration-missing"
       "Finite-Choice world: changed paths belong to an existing SysML v2 CommitScope whose path list is incomplete."
       open-questions: (list (list 'unscoped-paths unscoped)
                             (list 'choice-world widx sdec ddec))))
     ((eq? sdec 'declare-new-scope)
      (make-hypothesis
       "hyp:separate-scope-required"
       "Finite-Choice world: changed paths represent an independent governance scope and should be declared as a new SysML v2 CommitScope."
       open-questions: (list (list 'unscoped-paths unscoped)
                             (list 'choice-world widx sdec ddec))))
     ((and (symbol? sdec) (eq? ddec 'epistemic-competition))
      (make-hypothesis
       (string-append "hyp:choice-scope:" (symbol->string sdec))
       (string-append "Finite-Choice competing world selecting SysML v2 scope '"
                      (symbol->string sdec) "' under open competition.")
       open-questions: (append open-rows (list (list 'choice-world widx sdec ddec)))))
     ((pair? open-rows)
      (make-hypothesis
       "hyp:proposal-narration-incomplete"
       "Current commit proposal violates naming, reference, or language grounding contracts."
       open-questions: open-rows))
     (else #f))))

;;; Project surviving Finite-Choice worlds into Lab `Hypothesis.` POO objects.
;;; Unique forced-deduction worlds without open violations produce ZERO competing
;;; hypotheses; multi-world or incomplete worlds preserve every surviving world!
(def (workflow-choice-hypotheses choice-solution)
  (validate ChoiceSolutionType choice-solution)
  (let ((status (.get choice-solution choice-status))
        (worlds (.get choice-solution worlds))
        (unscoped (.get choice-solution unscoped-paths))
        (open-rows (.get choice-solution open-rows)))
    (cond
     ((eq? status 'unsatisfiable)
      (list
       (make-hypothesis
        "hyp:choice-space-unsatisfiable"
        "Finite-Choice closed constraints pruned all candidate worlds; premise revision or human decision required."
        open-questions: (list (list 'unscoped-paths unscoped)
                              (list 'open open-rows)))))
     ((and (eq? status 'unique-deduction) (null? open-rows) (null? unscoped))
      '())
     (else
      (filter values
              (map (lambda (w) (world->hypothesis w unscoped open-rows))
                   worlds))))))

;;; Declarative POO ChoiceFlowPlan constructor:
;;;   - `shared-prefix` and every slot in `branches` MUST contain only typed
;;;     `PureCAS.` or `VerifiedEpistemic.` DeterministicTaskNodes (zero FencedEffect).
;;;   - `fenced-tail` isolates all `FencedEffect.` tasks behind the multi-world
;;;     and human-approval safety fence.
(def (assert-non-fenced-tasks! label tasks)
  (unless (and (list? tasks) (every deterministic-task-node? tasks))
    (error (string-append label " expects a list of typed DeterministicTaskNode objects") tasks))
  (for-each
   (lambda (task)
     (when (eq? (opt-ref task 'effect-class 'pure-cas) 'fenced-effect)
       (error (string-append label " forbids FencedEffect tasks; place them in fenced-tail")
              (.ref task 'task-id))))
   tasks))

(def (workflow-choice-flow-plan
      branches
      choice-key: (choice-key 'scope-decision)
      shared-prefix: (shared-prefix '())
      fenced-tail: (fenced-tail '()))
  (unless (object? branches)
    (error "workflow-choice-flow-plan expects a POO branches object" branches))
  (unless (symbol? choice-key)
    (error "workflow-choice-flow-plan expects a symbol choice-key" choice-key))
  (assert-non-fenced-tasks! "choice-flow-plan shared-prefix" shared-prefix)
  (unless (and (list? fenced-tail) (every deterministic-task-node? fenced-tail))
    (error "choice-flow-plan fenced-tail expects typed DeterministicTaskNode objects" fenced-tail))
  (.o (:: @ ChoiceFlowPlan.)
      (choice-key := choice-key)
      (shared-prefix := shared-prefix)
      (branches := branches)
      (fenced-tail := fenced-tail)
      (action-authorized? := #f)))

;;; Stage 3: Execute a declarative POO `ChoiceFlowPlan.` across ALL surviving
;;; Finite-Choice worlds against a SINGLE shared `GovernedFunflowRunner`
;;; (`FunflowCasStore`), with static pre-execution branch completeness check:
;;; - Missing branch for any surviving world -> Fail-Closed with 0 executions!
;;; - `shared-prefix` runs ONCE and hits FunFlow singleflight CAS on later worlds.
;;; - `branches` run PureCAS/VerifiedEpistemic probes per world (fenced forbidden).
;;; - `fenced-tail` is strictly blocked unless `world-count == 1`, `approval-live?`,
;;;   and `dispatch-decision == 'fenced-apply`.
(def (workflow-execute-choice-worlds
      choice-solution runner plan
      approval-live?: (approval-live? #f))
  (validate ChoiceSolutionType choice-solution)
  (validate GovernedRunnerType runner)
  (validate ChoiceFlowPlanType plan)
  (let* ((worlds (.get choice-solution worlds))
         (wcount (.get choice-solution world-count))
         (status (.get choice-solution choice-status))
         (ckey (.ref plan 'choice-key))
         (shared-prefix (.ref plan 'shared-prefix))
         (branches (.ref plan 'branches))
         (fenced-tail (.ref plan 'fenced-tail))
         ;; Static pre-execution completeness check across all surviving worlds!
         (missing-branches
          (delete-duplicates/hash
           (filter values
                   (map (lambda (w)
                          (let ((key-val (opt-ref w ckey #f)))
                            (if (and (symbol? key-val) (.slot? branches key-val))
                              #f
                              (or key-val 'missing-choice-value))))
                        worlds)))))
    (assert-non-fenced-tasks! "choice-flow-plan shared-prefix" shared-prefix)
    (if (pair? missing-branches)
      (.o (kind := 'lambda-aitia.workflow.choice-world-execution.v1)
          (schema := "lambda-aitia.workflow-choice-execution.v1")
          (admitted? := #f)
          (reason := 'incomplete-choice-flow-branches)
          (missing-branches := missing-branches)
          (choice-status := status)
          (world-count := wcount)
          (worlds := '())
          (total-executions := 0)
          (total-cas-hits := 0)
          (fenced-blocked-count := 0)
          (action-authorized? := #f))
      (let loop ((ws worlds)
                 (exec-total 0)
                 (hit-total 0)
                 (blocked-total 0)
                 (acc '()))
        (if (null? ws)
          (.o (kind := 'lambda-aitia.workflow.choice-world-execution.v1)
              (schema := "lambda-aitia.workflow-choice-execution.v1")
              (admitted? := #t)
              (reason := 'choice-flow-plan-executed)
              (missing-branches := '())
              (choice-status := status)
              (world-count := wcount)
              (worlds := (reverse acc))
              (total-executions := exec-total)
              (total-cas-hits := hit-total)
              (fenced-blocked-count := blocked-total)
              (action-authorized? := #f))
          (let* ((w (car ws))
                 (ddec (.get w dispatch-decision))
                 (key-val (.ref w ckey))
                 (branch-tasks (.ref branches key-val)))
            (assert-non-fenced-tasks!
             (string-append "choice-flow-plan branch:" (symbol->string key-val))
             branch-tasks)
            (let ((tasks (append shared-prefix branch-tasks fenced-tail)))
              (let tloop ((ts tasks)
                          (w-exec 0)
                          (w-hit 0)
                          (w-blocked 0)
                          (t-results '())
                          (t-blocked '()))
                (if (null? ts)
                  (loop (cdr ws)
                        (+ exec-total w-exec)
                        (+ hit-total w-hit)
                        (+ blocked-total w-blocked)
                        (cons (.o (kind := 'lambda-aitia.workflow.choice-world-receipt.v1)
                                  (world-index := (.get w world-index))
                                  (scope-decision := (.get w scope-decision))
                                  (dispatch-decision := ddec)
                                  (scope-derivation-kind := (.get w scope-derivation-kind))
                                  (dispatch-derivation-kind := (.get w dispatch-derivation-kind))
                                  (scope-provenance := (.get w scope-provenance))
                                  (dispatch-provenance := (.get w dispatch-provenance))
                                  (task-results := (reverse t-results))
                                  (fenced-blocked-tasks := (reverse t-blocked))
                                  (executions := w-exec)
                                  (cas-hits := w-hit)
                                  (action-authorized? := #f))
                              acc))
                  (let* ((task (car ts))
                         (tid (.ref task 'task-id))
                         (eff (opt-ref task 'effect-class 'pure-cas))
                         (fenced? (eq? eff 'fenced-effect))
                         (fenced-allowed?
                          (and (= wcount 1)
                               approval-live?
                               (eq? ddec 'fenced-apply))))
                    (if (and fenced? (not fenced-allowed?))
                      (let ((reason
                             (cond
                              ((not (= wcount 1)) 'fenced-effect-blocked-in-competing-worlds)
                              ((not approval-live?) 'fenced-effect-requires-human-approval)
                              (else 'fenced-effect-not-admitted-by-choice-dispatch))))
                        (tloop (cdr ts)
                               w-exec
                               w-hit
                               (+ w-blocked 1)
                               t-results
                               (cons (.o (task-id := tid)
                                         (effect-class := eff)
                                         (executed? := #f)
                                         (fenced-blocked? := #t)
                                         (reason := reason)
                                         (action-authorized? := #f))
                                     t-blocked)))
                      (let* ((res (governed-funflow-run
                                   runner
                                   (.ref task 'flow)
                                   (.ref task 'input)
                                   idempotency-key: (opt-ref task 'idempotency-key #f)
                                   idempotency-commits: (opt-ref task 'idempotency-commits '())
                                   sandbox-override: (opt-ref task 'sandbox-profile #f)
                                   env-digest-override: (opt-ref task 'env-digest #f)))
                             (hit? (and (.ref res 'cas-hit?) #t))
                             (ex? (and (.ref res 'executed?) #t)))
                        (tloop (cdr ts)
                               (+ w-exec (if ex? 1 0))
                               (+ w-hit (if hit? 1 0))
                               w-blocked
                               (cons (.o (task-id := tid)
                                         (effect-class := eff)
                                         (admitted? := (.ref res 'admitted?))
                                         (executed? := ex?)
                                         (cas-hit? := hit?)
                                         (cas-key := (.ref res 'cas-key))
                                         (value := (opt-ref res 'value #f))
                                         (reason := (.ref res 'reason))
                                         (action-authorized? := #f))
                                     t-results)
                               t-blocked)))))))))))))
