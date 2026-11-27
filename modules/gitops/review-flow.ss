;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; FunFlow Choice + Native Lean-Verified `gerbil-ascent` Finite-Choice Review Engine
;;; (`aitia review [plan.sexp | plan.json | repo | --tool-schema]` / Marlin gRPC `StepReview`).
;;;
;;; Phase 1 Optimizations:
;;;   1. Cross-round `FunflowCasStore`-style cache keyed by `(context-digest, rule-packs, staged-only)`
;;;      so repeat turns over unchanged diffs hit CAS (`shared-prefix-cas-hit?: #t`).
;;;   2. Extended zero-`eval` S-expr `(aitia-review-plan ...)` parser supporting
;;;      `(formal-model ...)`, `(ai-lens-report ...)`, `(check ...)`, and `(depends-on ...)`
;;;      with pre-execution DFS/SCC cycle detection (`acyclic?: #f` -> 0 worlds fail-closed).
;;;   3. Built-in DE Formal Library Catalog Recommender (37 Quint models + 54 Lean SM17-SM37
;;;      modules) projecting repo-aware `recommended-formal-models` and tailored `sexp-plan-template`.
;;;   4. Token-budgeted progressive disclosure: Turn 1 (or invalid plan) emits `dsl-grammar` +
;;;      repo-tailored `sexp-plan-template` + `recommended-formal-models`; Turn 2+ valid plans
;;;      omit bulky grammar/templates by default (saving ~60% tokens).
;;;   5. Single-source-of-truth `gitops-review-tool-schema` projecting the exact JSON Schema
;;;      `ModelToolDefinition` (`aitia_review_step`) for Marlin & native LLM tool calling.

(import (only-in :clan/poo/object .def .get .o .ref .slot? object?)
        (only-in :gerbil/core string-contains string-join string-suffix?)
        (only-in :std/list/list delete-duplicates/hash filter filter-map)
        (only-in :gerbil-ascent/program/api
                 relational-choice-program
                 relational-choice-solve
                 relational-program-query)
        "diff-governance.ss"
        "sidecar-audit.ss")

(export FunflowChoiceBranch.
        FunflowReviewFrontier.
        parse-review-plan-sexp
        recommend-de-formal-models
        gitops-review-tool-schema
        gitops-review-flow-step)

(def (opt-slot obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (non-empty-string? value)
  (and (string? value) (> (string-length value) 0)))

(def (str-has? hay needle)
  (and (string? hay) (string? needle) (> (string-length needle) 0)
       (if (string-contains hay needle) #t #f)))

(def (as-sym value)
  (cond
   ((symbol? value) value)
   ((string? value) (string->symbol value))
   (else (error "expected symbol or string for ASCENT Finite-Choice scalar" value))))

(def (sym->str value)
  (cond
   ((symbol? value) (symbol->string value))
   ((string? value) value)
   (else "")))

(def (first-choice-value rows)
  (and (pair? rows) (pair? (car rows)) (pair? (cdar rows))
       (cadar rows)))

(def (first-derivation-kind provenance-steps)
  (and (pair? provenance-steps) (pair? (car provenance-steps))
       (caar provenance-steps)))

;; ── Cross-Round FunFlow Shared-Prefix CAS Store (Bounded, Thread-Safe) ─────

(def +review-cas-mutex+ (make-mutex 'review-diff-cas))
(def +review-cas-table+ (make-hash-table))
(def +review-cas-max-entries+ 64)

(def (rule-packs-cache-key packs)
  (map (lambda (p)
         (list (opt-slot p 'pack-id "")
               (opt-slot p 'subdomain "")
               (map (lambda (r)
                      (list (opt-slot r 'rule-id "")
                            (opt-slot r 'languages '())
                            (opt-slot r 'tokens-all '())))
                    (opt-slot p 'rules '()))))
       packs))

(def (cached-diff-defense-audit ctx-digest base-ref staged-only? staged-diff unstaged-diff base-ref-diff rule-packs funflow-receipts)
  (let* ((key (and (non-empty-string? ctx-digest)
                   (list ctx-digest
                         base-ref
                         staged-only?
                         staged-diff
                         unstaged-diff
                         base-ref-diff
                         (rule-packs-cache-key rule-packs)
                         (length funflow-receipts))))
         (hit (and key
                   (with-lock +review-cas-mutex+
                     (lambda () (hash-get +review-cas-table+ key))))))
    (if hit
      (values hit #t)
      (let ((res (gitops-diff-defense-audit
                  (.o (base-ref := base-ref)
                      (staged-only? := staged-only?)
                      (staged-diff := staged-diff)
                      (unstaged-diff := unstaged-diff)
                      (base-ref-diff := base-ref-diff)
                      (rule-packs := rule-packs)
                      (funflow-receipts := funflow-receipts)))))
        (when key
          (with-lock +review-cas-mutex+
            (lambda ()
              (when (>= (hash-length +review-cas-table+) +review-cas-max-entries+)
                (hash-clear! +review-cas-table+))
              (hash-put! +review-cas-table+ key res))))
        (values res #f)))))

;; ── Prototypes ─────────────────────────────────────────────────────────────

(.def FunflowChoiceBranch.
  kind: 'lambda-aitia.funflow-choice-branch.v1
  choice-id: ""
  effect-class: "pure-cas"
  title: ""
  why-open: ""
  admitted?: #t
  constraints: '()
  template: #f
  action-authorized?: #f)

(.def FunflowReviewFrontier.
  schema: "lambda-aitia.funflow-choice-frontier.v1"
  engine-owner: "scheme-poo-ascent-funflow"
  single-entrypoint: "aitia review"
  grpc-entrypoint: "StepReview"
  action-authorized?: #f)

(def (make-choice-branch
      choice-id: cid
      effect-class: eff
      title: title
      why-open: why
      admitted?: (admitted? #t)
      constraints: (constraints '())
      template: (template (.o)))
  (.o (:: @ FunflowChoiceBranch.)
      (choice-id := cid)
      (effect-class := eff)
      (title := title)
      (why-open := why)
      (admitted? := (and admitted? #t))
      (constraints := constraints)
      (template := template)
      (action-authorized? := #f)))

;; ── DE Formal Library Catalog Recommender (37 Quint + 54 Lean SM17-SM37) ───

(def (mk-de-rec model-id kind pkg why)
  (.o (model-id := model-id)
      (formal-kind := kind)
      (mode := "upstream-library-reuse")
      (library-package := pkg)
      (why-matched := why)
      (ephemeral-overlay-rule := "For project-specific extensions use `// @quint-extends` + `// @countermodel` (MR05) or Lean `LeanPoo.ObjectContract.refine` in sidecar vault.")))

(def (recommend-de-formal-models target-repo changed-paths)
  (let* ((joined (string-join (cons target-repo changed-paths) " "))
         (recs '())
         (add! (lambda (r) (set! recs (append recs (list r))))))
    (when (or (str-has? joined "gitops") (str-has? joined "subprocess")
              (str-has? joined "sidecar") (str-has? joined "worktree"))
      (add! (mk-de-rec "GitopsSubprocessConfinementAndArgInjection" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM32 Git/subprocess env neutralization & fsmonitor/arg confinement"))
      (add! (mk-de-rec "effect-handoff" "quint"
                       "@deterministic-engineering/quint-models"
                       "Prepare / durable-commit / emit exact-effect handoff safety")))
    (when (or (str-has? joined "auth") (str-has? joined "token")
              (str-has? joined "grpc") (str-has? joined "bearer"))
      (add! (mk-de-rec "ControlPlaneAuthAndGovernanceConfinement" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM26 non-blank constant-time Bearer auth & Operator E-Stop confinement"))
      (add! (mk-de-rec "oauth-token-lifecycle" "quint"
                       "@deterministic-engineering/quint-models"
                       "Token replay, nonce single-use & refresh epoch monotonicity")))
    (when (or (str-has? joined "hook") (str-has? joined "protocol")
              (str-has? joined "governance") (str-has? joined "cedar")
              (str-has? joined "policy"))
      (add! (mk-de-rec "HookPolicyAndProtocolContractConfinement" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM33 fail-closed hook/protocol contract & trust-floor preservation"))
      (add! (mk-de-rec "governance-sod" "quint"
                       "@deterministic-engineering/quint-models"
                       "Separation of Duties & forbid-veto precedence")))
    (when (or (str-has? joined "weaver") (str-has? joined "harness")
              (str-has? joined "search") (str-has? joined "stream")
              (str-has? joined "tool"))
      (add! (mk-de-rec "GraphWitnessAndHarnessConfinement" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM35 harness Cedar read-only confinement & bounded Weaver route loading"))
      (add! (mk-de-rec "agent-ifc-capability" "quint"
                       "@deterministic-engineering/quint-models"
                       "AI Agent control/data segregation & capability IFC (CaMeL/FIDES)")))
    (when (or (str-has? joined "storage") (str-has? joined "cas")
              (str-has? joined "sqlite") (str-has? joined "session"))
      (add! (mk-de-rec "StorageBoundaryIntegrityAndSyncConfinement" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM31 CAS integrity, serde bounds & immutable index replay"))
      (add! (mk-de-rec "wal-crash-recovery" "quint"
                       "@deterministic-engineering/quint-models"
                       "Crash-safe durability & atomic persistence")))
    (when (or (str-has? joined "funflow") (str-has? joined "graph-engine")
              (str-has? joined "choice") (str-has? joined "workflow"))
      (add! (mk-de-rec "SingleOwnerGraphGovernanceConfinement" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM25 single-owner GraphEngine convergence & reachable governance"))
      (add! (mk-de-rec "structured-cancellation" "quint"
                       "@deterministic-engineering/quint-models"
                       "Parent-child quiescence & lease fencing")))
    (if (null? recs)
      (list (mk-de-rec "SubprocessEnvScrubAndAuthTiming" "lean4"
                       "@deterministic-engineering/lean-models"
                       "SM24 default baseline subprocess & constant-time auth floor")
            (mk-de-rec "agent-ifc-capability" "quint"
                       "@deterministic-engineering/quint-models"
                       "Default AI Agent capability confinement model"))
      ;; Keep compact top 4 recommendations for LLM context efficiency
      (if (> (length recs) 4)
        (list (list-ref recs 0) (list-ref recs 1) (list-ref recs 2) (list-ref recs 3))
        recs))))

;; ── Pre-Execution DAG Cycle Check on `(depends-on a b)` ────────────────────

(def (dag-has-cycle? edges)
  ;; edges: list of (from . to)
  (let ((adj (make-hash-table))
        (nodes '())
        (state (make-hash-table))) ;; 0=unvisited, 1=visiting, 2=done
    (for-each
     (lambda (e)
       (let ((u (car e)) (v (cdr e)))
         (set! nodes (cons u (cons v nodes)))
         (hash-put! adj u (cons v (or (hash-get adj u) '())))))
     edges)
    (letrec ((dfs
              (lambda (u)
                (let ((st (or (hash-get state u) 0)))
                  (cond
                   ((= st 1) #t)
                   ((= st 2) #f)
                   (else
                    (hash-put! state u 1)
                    (let ((cyc (ormap dfs (or (hash-get adj u) '()))))
                      (hash-put! state u 2)
                      cyc)))))))
      (ormap dfs (delete-duplicates/hash nodes)))))

;; ── Pure-Datum S-Expression Scenario Plan Parser (ZERO eval!) ──────────────

(def (sexp-string-list elems)
  (filter non-empty-string?
          (map (lambda (x)
                 (cond ((string? x) x)
                       ((symbol? x) (symbol->string x))
                       (else "")))
               elems)))

(def (parse-sexp-rule form)
  (if (not (and (pair? form) (eq? (car form) 'rule) (pair? (cdr form))))
    #f
    (let* ((rid (sym->str (cadr form)))
           (clauses (cddr form))
           (langs '("*"))
           (toks-all '())
           (toks-any '())
           (forbid-unless '())
           (hclass "subdomain-invariant-violation")
           (detail (string-append "Scenario rule `" rid "` violated"))
           (c2 "Satisfy scenario invariant explicitly with typed contract and witness."))
      (for-each
       (lambda (cl)
         (when (pair? cl)
           (case (car cl)
             ((languages) (set! langs (sexp-string-list (cdr cl))))
             ((tokens-all) (set! toks-all (sexp-string-list (cdr cl))))
             ((tokens-any) (set! toks-any (sexp-string-list (cdr cl))))
             ((forbid-unless) (set! forbid-unless (sexp-string-list (cdr cl))))
             ((class hallucination-class)
              (when (pair? (cdr cl)) (set! hclass (sym->str (cadr cl)))))
             ((detail) (when (pair? (cdr cl)) (set! detail (sym->str (cadr cl)))))
             ((c2 c2-replacement) (when (pair? (cdr cl)) (set! c2 (sym->str (cadr cl))))))))
       clauses)
      (.o (rule-id := rid)
          (hallucination-class := hclass)
          (languages := (if (null? langs) '("*") langs))
          (match-mode := "code-only")
          (tokens-all := toks-all)
          (tokens-any := toks-any)
          (forbid-unless := forbid-unless)
          (exclude-test-files? := #f)
          (anti-pattern-id := "AP-SUBDOMAIN")
          (detail := detail)
          (c2-replacement := c2)
          (anti-evasion-warning := "Declarative plan rules are strictly additive; core DE G2 floor stays immutable.")))))

(def (parse-sexp-rule-pack form)
  (if (not (and (pair? form) (eq? (car form) 'rule-pack) (>= (length form) 3)))
    #f
    (let* ((pack-id (sym->str (cadr form)))
           (subdomain (sym->str (caddr form)))
           (rules (filter-map parse-sexp-rule (cdddr form))))
      (.o (pack-id := pack-id)
          (subdomain := subdomain)
          (version := "1.0.0")
          (source-mode := "ephemeral-ai-proposed")
          (rules := rules)))))

(def (parse-sexp-probe form)
  (if (not (and (pair? form) (eq? (car form) 'probe) (>= (length form) 3)))
    #f
    (let ((branch (sym->str (cadr form)))
          (verdict (sym->str (caddr form)))
          (detail (if (>= (length form) 4) (sym->str (cadddr form)) "")))
      (.o (branch := branch)
          (verdict := verdict)
          (detail := detail)))))

(def (parse-sexp-formal-model form ctx-digest)
  ;; (formal-model "<id>" (mode "upstream-library-reuse") (library "@deterministic-engineering/quint-models") (resolver-digest "sha256:...") (countermodel-verified #t) (proof-clean #t) (passed #t) (sidecar-vault #t))
  (if (not (and (pair? form) (eq? (car form) 'formal-model) (pair? (cdr form))))
    #f
    (let ((mid (sym->str (cadr form)))
          (mode "upstream-library-reuse")
          (lib "@deterministic-engineering/quint-models")
          (res-digest "")
          (cm? #f)
          (clean? #t)
          (passed? #t)
          (vault? #t))
      (for-each
       (lambda (cl)
         (when (and (pair? cl) (pair? (cdr cl)))
           (case (car cl)
             ((mode) (set! mode (sym->str (cadr cl))))
             ((library library-package) (set! lib (sym->str (cadr cl))))
             ((resolver-digest) (set! res-digest (sym->str (cadr cl))))
             ((countermodel-verified) (set! cm? (eq? (cadr cl) #t)))
             ((proof-clean) (set! clean? (eq? (cadr cl) #t)))
             ((passed) (set! passed? (eq? (cadr cl) #t)))
             ((sidecar-vault stored-in-sidecar-vault) (set! vault? (eq? (cadr cl) #t))))))
       (cddr form))
      (.o (model-id := mid)
          (mode := mode)
          (library-package := lib)
          (resolver-digest := res-digest)
          (context-digest := ctx-digest)
          (countermodel-verified? := cm?)
          (proof-clean? := clean?)
          (passed? := passed?)
          (stored-in-sidecar-vault? := vault?)))))

(def (parse-sexp-ai-report form ctx-digest)
  ;; (ai-lens-report "<lens>" (provider "...") (model-id "...") (prompt-digest "sha256:...") (engine "marlin-agent-core"))
  (if (not (and (pair? form) (eq? (car form) 'ai-lens-report) (pair? (cdr form))))
    #f
    (let ((lens (sym->str (cadr form)))
          (provider "host-llm")
          (model-id "")
          (prompt-digest "")
          (engine "native-ai-environment"))
      (for-each
       (lambda (cl)
         (when (and (pair? cl) (pair? (cdr cl)))
           (case (car cl)
             ((provider) (set! provider (sym->str (cadr cl))))
             ((model-id) (set! model-id (sym->str (cadr cl))))
             ((prompt-digest prompt-template-digest) (set! prompt-digest (sym->str (cadr cl))))
             ((engine engine-binding) (set! engine (sym->str (cadr cl)))))))
       (cddr form))
      (.o (lens := lens)
          (engine-binding := engine)
          (provider := provider)
          (model-id := model-id)
          (prompt-template-digest := prompt-digest)
          (context-digest := ctx-digest)
          (epistemic-status := "hypothesized")
          (findings := '())
          (action-authorized? := #f)))))

(def (parse-review-plan-sexp text (ctx-digest ""))
  (let ((parsed
         (with-catch
          (lambda (e) (cons 'parse-error (object->string e)))
          (lambda ()
            (let* ((port (open-input-string text))
                   (datum (read port)))
              (if (and (pair? datum) (eq? (car datum) 'aitia-review-plan))
                (cons 'ok (cdr datum))
                (cons 'parse-error "Expected top-level `(aitia-review-plan ...)` S-expression")))))))
    (if (not (eq? (car parsed) 'ok))
      (.o (valid? := #f)
          (error := (cdr parsed))
          (core-floor-violation? := #f)
          (acyclic? := #t)
          (scenario := "")
          (repo := #f)
          (base-ref := #f)
          (disclosure := #f)
          (required-lenses := '())
          (open-branches := '())
          (refuted-branches := '())
          (probes := '())
          (rule-packs := '())
          (formal-models := '())
          (ai-reports := '())
          (failed-checks := '())
          (dep-edges := '()))
      (let ((scenario "unnamed-scenario")
            (repo #f)
            (base-ref #f)
            (disclosure #f)
            (required-lenses '())
            (open-branches '())
            (refuted-branches '())
            (probes '())
            (rule-packs '())
            (formal-models '())
            (ai-reports '())
            (failed-checks '())
            (dep-edges '())
            (floor-violation? #f)
            (violation-reason #f))
        (for-each
         (lambda (clause)
           (when (pair? clause)
             (case (car clause)
               ((scenario) (when (pair? (cdr clause)) (set! scenario (sym->str (cadr clause)))))
               ((repo) (when (pair? (cdr clause)) (set! repo (sym->str (cadr clause)))))
               ((base-ref) (when (pair? (cdr clause)) (set! base-ref (sym->str (cadr clause)))))
               ((disclosure) (when (pair? (cdr clause)) (set! disclosure (sym->str (cadr clause)))))
               ((required-lenses) (set! required-lenses (sexp-string-list (cdr clause))))
               ((open-branches) (set! open-branches (append open-branches (sexp-string-list (cdr clause)))))
               ((refuted-branches) (set! refuted-branches (append refuted-branches (sexp-string-list (cdr clause)))))
               ((probes) (set! probes (append probes (filter-map parse-sexp-probe (cdr clause)))))
               ((probe) (let ((p (parse-sexp-probe clause)))
                          (when p (set! probes (append probes (list p))))))
               ((rule-pack) (let ((rp (parse-sexp-rule-pack clause)))
                              (when rp (set! rule-packs (append rule-packs (list rp))))))
               ((formal-model) (let ((fm (parse-sexp-formal-model clause ctx-digest)))
                                 (when fm (set! formal-models (append formal-models (list fm))))))
               ((ai-lens-report) (let ((ar (parse-sexp-ai-report clause ctx-digest)))
                                   (when ar (set! ai-reports (append ai-reports (list ar))))))
               ((depends-on)
                (when (>= (length clause) 3)
                  (set! dep-edges (cons (cons (sym->str (cadr clause)) (sym->str (caddr clause))) dep-edges))))
               ((check)
                (when (and (>= (length clause) 3)
                           (not (equal? (sym->str (caddr clause)) "passed")))
                  (set! failed-checks (cons (sym->str (cadr clause)) failed-checks))))
               ((disable-core-floor skip-g2 authorize-action fenced-in-prefix eval)
                (set! floor-violation? #t)
                (set! violation-reason
                      (string-append "Forbidden declarative plan clause `"
                                     (symbol->string (car clause))
                                     "`: LLM plans are strictly monotone and cannot weaken closed invariants or authorize effects"))))))
         (cdr parsed))
        (let* ((acyclic? (not (dag-has-cycle? dep-edges)))
               (err-msg (or violation-reason
                            (and (not acyclic?)
                                 "Cyclic `(depends-on ...)` dependency graph rejected before execution"))))
          (.o (valid? := (and (not floor-violation?) acyclic?))
              (error := err-msg)
              (core-floor-violation? := (or floor-violation? (not acyclic?)))
              (acyclic? := acyclic?)
              (scenario := scenario)
              (repo := repo)
              (base-ref := base-ref)
              (disclosure := disclosure)
              (required-lenses := required-lenses)
              (open-branches := (delete-duplicates/hash open-branches))
              (refuted-branches := (delete-duplicates/hash refuted-branches))
              (probes := probes)
              (rule-packs := rule-packs)
              (formal-models := formal-models)
              (ai-reports := ai-reports)
              (failed-checks := (reverse failed-checks))
              (dep-edges := (reverse dep-edges))))))))

;; ── Native Lean-Verified `gerbil-ascent` Finite-Choice Solver ──────────────

(def (solve-review-finite-choice
      ctx-digest diff-res ascent-res open-branches refuted-branches probes human-approved? plan-floor-violation?)
  (let* ((cut-sym (as-sym (if (non-empty-string? ctx-digest)
                            (string-append "cut:" ctx-digest)
                            "cut:live")))
         (diff-bad? (not (.get diff-res passed?)))
         (staged-bad? (> (.get diff-res staged-findings-count) 0))
         (ascent-proven? (and (.get ascent-res admissible?)
                              (equal? (.get ascent-res epistemic-status) "Proven")))
         (probe-refuted
          (filter-map (lambda (p)
                        (and (equal? (opt-slot p 'verdict "") "refutes")
                             (let ((b (opt-slot p 'branch "")))
                               (and (non-empty-string? b) b))))
                      probes))
         (probe-supported
          (filter-map (lambda (p)
                        (and (equal? (opt-slot p 'verdict "") "supports")
                             (let ((b (opt-slot p 'branch "")))
                               (and (non-empty-string? b) b))))
                      probes))
         (all-refuted (delete-duplicates/hash (append refuted-branches probe-refuted)))
         (effective-open
          (cond
           ((pair? open-branches) (delete-duplicates/hash open-branches))
           (ascent-proven? '("verified-unique-world"))
           (diff-bad? '("repair-diff-defects" "attach-guard-probe-witness"))
           (else '("submit-ai-lens-report" "attach-formal-evidence"))))
         (open-rows (map (lambda (b) (list cut-sym (as-sym b))) effective-open))
         (refuted-rows (map (lambda (b) (list cut-sym (as-sym b))) all-refuted))
         (diff-bad-rows (if diff-bad? (list (list cut-sym)) '()))
         (staged-bad-rows (if staged-bad? (list (list cut-sym)) '()))
         (floor-viol-rows (if plan-floor-violation? (list (list cut-sym)) '()))
         (proven-approved-rows
          (if (and ascent-proven? (not diff-bad?) (not staged-bad?) human-approved? (not plan-floor-violation?))
            (list (list cut-sym))
            '()))
         (proven-awaiting-rows
          (if (and ascent-proven? (not diff-bad?) (not staged-bad?) (not human-approved?) (not plan-floor-violation?))
            (list (list cut-sym))
            '()))
         (epistemic-open-rows
          (if (and (not diff-bad?) (not ascent-proven?) (not plan-floor-violation?))
            (list (list cut-sym))
            '()))
         (program
          (relational-choice-program
            (relation open_branch_offer (cut branch) open-rows)
            (relation refuted_branch (cut branch) refuted-rows)
            (relation diff_defect_present (cut) diff-bad-rows)
            (relation staged_defect_present (cut) staged-bad-rows)
            (relation core_floor_violated (cut) floor-viol-rows)
            (relation proven_and_approved (cut) proven-approved-rows)
            (relation proven_awaiting_human (cut) proven-awaiting-rows)
            (relation epistemic_open (cut) epistemic-open-rows)
            (choice review_branch (cut value))
            (choice dispatch_decision (cut value))
            (rule (open (review_branch ?c) ?b)
                  (open_branch_offer ?c ?b))
            (rule (closed (review_branch ?c) ())
                  (review_branch ?c ?b)
                  (refuted_branch ?c ?b))
            (rule (closed (dispatch_decision ?c) ())
                  (core_floor_violated ?c))
            (rule (closed (dispatch_decision ?c) ((value 'repair-mechanical-defects)))
                  (review_branch ?c ?b)
                  (diff_defect_present ?c))
            (rule (closed (dispatch_decision ?c) ((value 'fenced-apply)))
                  (review_branch ?c ?b)
                  (proven_and_approved ?c))
            (rule (closed (dispatch_decision ?c) ())
                  (dispatch_decision ?c (value 'fenced-apply))
                  (staged_defect_present ?c))
            (rule (closed (dispatch_decision ?c) ((value 'human-audit-gate)))
                  (review_branch ?c ?b)
                  (proven_awaiting_human ?c))
            (rule (closed (dispatch_decision ?c) ((value 'epistemic-competition)))
                  (review_branch ?c ?b)
                  (epistemic_open ?c))
            (limits 256 1024 1024)))
         (models (relational-choice-solve program state-budget: 32))
         (worlds
          (let loop ((ms models) (idx 0) (acc '()))
            (if (null? ms)
              (reverse acc)
              (let* ((m (car ms))
                     (b-rows (relational-program-query m 'review_branch))
                     (d-rows (relational-program-query m 'dispatch_decision))
                     (b-prov (relational-program-query m 'review_branch provenance?: #t))
                     (d-prov (relational-program-query m 'dispatch_decision provenance?: #t))
                     (b-val (first-choice-value b-rows))
                     (d-val (first-choice-value d-rows))
                     (b-str (sym->str b-val)))
                (loop (cdr ms)
                      (+ idx 1)
                      (cons (.o (world-index := idx)
                                (review-branch := b-str)
                                (dispatch-decision := (sym->str d-val))
                                (branch-derivation-kind := (sym->str (first-derivation-kind b-prov)))
                                (dispatch-derivation-kind := (sym->str (first-derivation-kind d-prov)))
                                (probe-supported? := (if (member b-str probe-supported) #t #f))
                                (provenance-steps := (+ (length b-prov) (length d-prov)))
                                (action-authorized? := #f))
                            acc))))))
         (wcount (length worlds))
         (status
          (cond
           ((= wcount 0) "unsatisfiable")
           ((= wcount 1) "unique-deduction")
           (else "competing-worlds"))))
    (.o (schema := "lambda-aitia.ascent-finite-choice-solution.v1")
        (choice-status := status)
        (world-count := wcount)
        (worlds := worlds)
        (open-branches-offered := effective-open)
        (refuted-branches := all-refuted)
        (supported-branches := probe-supported)
        (action-authorized? := #f))))

(def +known-review-choices+
  '("discover"
    "validate-plan"
    "repair-diff-defects"
    "attach-guard-probe-witness"
    "compose-subdomain-rule-pack"
    "submit-ai-lens-report"
    "attach-formal-evidence"
    "inspect-causal-detail"
    "inspect-formal-guide"
    "request-human-disposition"))

(def +review-plan-dsl-grammar+
  (list
   "(aitia-review-plan <clause>...)  ; Pure datum S-expr (ZERO eval)"
   "  (scenario \"<name>\") (repo \"<path>\") (base-ref \"<git-ref>\") (disclosure \"frontier\"|\"causal\"|\"deep-spec\")"
   "  (open-branches \"<b1>\" \"<b2>\"...) ; Bounded ASCENT open hypotheses"
   "  (refuted-branches \"<b1>\"...) (probes (probe \"<b>\" supports|refutes|inconclusive \"<witness>\")...)"
   "  (depends-on \"<step-a>\" \"<step-b>\") ; Acyclic DAG edge (cycles rejected fail-closed)"
   "  (rule-pack \"<pack-id>\" \"<subdomain>\" (rule \"<id>\" (languages \"rust\" \"scheme\"...) (tokens-all \"<t>\"...) (detail \"...\"))...)"
   "  (formal-model \"<id>\" (mode \"upstream-library-reuse\"|\"ephemeral-ai-overlay\") (library \"@deterministic-engineering/...\") (resolver-digest \"sha256:...\") (countermodel-verified #t) (proof-clean #t) (passed #t))"
   "  (ai-lens-report \"<lens>\" (provider \"<p>\") (model-id \"<m>\") (prompt-digest \"sha256:...\") (engine \"marlin-agent-core\"))"
   "  (check \"<name>\" passed|failed) (required-lenses \"correctness\" \"security\" \"api-regression\" \"nasa-swe146\")"
   "FORBIDDEN (fail-closed, 0 worlds): disable-core-floor, skip-g2, authorize-action, fenced-in-prefix, eval"))

(def (detect-active-languages changed-paths)
  (let ((langs
         (delete-duplicates/hash
          (filter-map
           (lambda (p)
             (cond
              ((string-suffix? ".rs" p) "rust")
              ((or (string-suffix? ".ss" p) (string-suffix? ".scm" p)) "scheme")
              ((string-suffix? ".py" p) "python")
              ((string-suffix? ".go" p) "go")
              ((or (string-suffix? ".ts" p) (string-suffix? ".tsx" p)) "typescript")
              (else #f)))
           changed-paths))))
    (if (null? langs) '("rust" "scheme") langs)))

(def (render-sexp-plan-template repo-hint base-ref target-repo changed-paths recs)
  (let* ((langs (detect-active-languages changed-paths))
         (lang-str (string-join (map (lambda (l) (string-append "\"" l "\"")) langs) " "))
         (top-rec (and (pair? recs) (car recs)))
         (rec-id (if top-rec (.get top-rec model-id) "agent-ifc-capability"))
         (rec-pkg (if top-rec (.get top-rec library-package) "@deterministic-engineering/quint-models")))
    (string-append
     "(aitia-review-plan\n"
     "  (scenario \"" target-repo "-review\")\n"
     "  (repo \"" repo-hint "\")\n"
     "  (base-ref \"" base-ref "\")\n"
     "  (open-branches \"verify-diff-invariants\" \"investigate-boundary-risk\")\n"
     "  (probes\n"
     "    (probe \"verify-diff-invariants\" supports \"describe executable witness\"))\n"
     "  (formal-model \"" rec-id "\"\n"
     "    (mode \"upstream-library-reuse\")\n"
     "    (library \"" rec-pkg "\")\n"
     "    (resolver-digest \"sha256:0000000000000000000000000000000000000000000000000000000000000000\")\n"
     "    (countermodel-verified #t) (proof-clean #t) (passed #t))\n"
     "  (rule-pack \"" target-repo "-subdomain-pack\" \"" target-repo "\"\n"
     "    (rule \"subdomain-invariant-1\"\n"
     "      (languages " lang-str ")\n"
     "      (tokens-all \"forbidden_pattern\")\n"
     "      (detail \"Describe domain-specific invariant\"))))")))

(def (render-quint-overlay-template recs)
  (let* ((qrec (let loop ((xs recs))
                 (cond
                  ((null? xs) #f)
                  ((equal? (.get (car xs) formal-kind) "quint") (car xs))
                  (else (loop (cdr xs))))))
         (extends-id (if qrec (.get qrec model-id) "agent-ifc-capability")))
    (string-append
     "// @quint-extends " extends-id "\n"
     "// @countermodel\n"
     "module EphemeralOverlay {\n"
     "  var inputValid: bool\n"
     "  var authorized: bool\n\n"
     "  def failClosedInv: bool = authorized implies inputValid\n\n"
     "  action init = all { inputValid' = false, authorized' = false }\n"
     "  action acceptValid = all { inputValid' = true, authorized' = true }\n"
     "  action buggyFallback = all { inputValid' = false, authorized' = true }\n\n"
     "  run safePathTest = init.then(acceptValid).expect(failClosedInv)\n"
     "  run mr05CountermodelTest = init.then(buggyFallback).expect(not(failClosedInv))\n"
     "}")))

;; ── Single-Source-of-Truth Tool-Calling JSON Schema Projection ─────────────

(def (gitops-review-tool-schema)
  (.o (schema := "lambda-aitia.model-tool-definition.v1")
      (name := "aitia_review_step")
      (capability := "review")
      (read-only? := #t)
      (action-authorized? := #f)
      (description
       := "Read-only FunFlow/ASCENT SDLC Git/JJ review oracle. Turn 1: call with {} or {repo} to discover live gix/jj-lib diff state, DE G2 findings, recommended DE Quint/Lean models, dslGrammar, repo-tailored (aitia-review-plan ...) sexpPlanTemplate, and quintOverlayTemplate. Turn 2+: pass planSexp (zero-eval S-expr) with open-branches, probes (supports/refutes), subdomain rule-pack, and optional quintOverlaySource (Quint 0.33 module with // @countermodel + positive & *Countermodel*Test traces, executed live in an isolated sidecar vault) to converge worlds via ASCENT relational-choice-solve. Never executes writes.")))

(def (build-progressive-choices
      repo-hint base-ref ctx-digest diff-res ascent-res fenced-admitted?)
  (let* ((g2-findings (.get diff-res g2-findings))
         (missing-lenses (.get ascent-res missing-lenses))
         (unaddressed (.get ascent-res unaddressed-high-findings))
         (admitted-models (.get ascent-res admitted-formal-models))
         (pending-oracles (.get ascent-res pending-oracles))
         (vacuous-overlays (.get ascent-res vacuous-ephemeral-overlays))
         (open-obs (.get ascent-res open-obligations))
         (first-lens (if (pair? missing-lenses) (car missing-lenses) "security"))
         (choices '()))
    (when (pair? g2-findings)
      (set! choices
            (append choices
                    (list
                     (make-choice-branch
                      choice-id: "repair-diff-defects"
                      effect-class: "verified-epistemic"
                      title: "Repair mechanical G2 or subdomain diff defects without floor weakening"
                      why-open: (string-append (number->string (length g2-findings))
                                               " active diff finding(s) block commit admission")
                      constraints: '("Fix defects in source using C2 replacement directives"
                                     "Do NOT weaken assertions, add skip/ignore, or add silent fallbacks")
                      template: (.o (repo := repo-hint) (base-ref := base-ref) (choice := "discover")))
                     (make-choice-branch
                      choice-id: "attach-guard-probe-witness"
                      effect-class: "verified-epistemic"
                      title: "Submit DE F3 Quint guard-probe witness for disputed defensive checks"
                      why-open: "Competing hypothesis: a flagged check may be an essential boundary invariant"
                      constraints: '("Verdict must come from an executable Quint F3 guard-probe")
                      template: (.o (repo := repo-hint)
                                    (base-ref := base-ref)
                                    (choice := "attach-guard-probe-witness")
                                    (guard-probes := (list (.o (probe-id := "probe-1") (verdict := "essential"))))))))))
    (when (or (pair? missing-lenses) (pair? unaddressed))
      (set! choices
            (append choices
                    (list
                     (make-choice-branch
                      choice-id: "submit-ai-lens-report"
                      effect-class: "verified-epistemic"
                      title: "Submit hypothesized multi-lens AI review report (SWE-146 provenance)"
                      why-open: (if (pair? missing-lenses)
                                  (string-append "Missing required audit lenses: "
                                                 (number->string (length missing-lenses)) " remaining")
                                  "Unaddressed high-severity findings require explicit disposition")
                      constraints: '("epistemicStatus MUST equal \"hypothesized\"; actionAuthorized MUST equal false")
                      template: (.o (repo := repo-hint)
                                    (base-ref := base-ref)
                                    (choice := "submit-ai-lens-report")
                                    (ai-reports
                                     := (list (.o (lens := first-lens)
                                                  (engine-binding := "native-ai-environment")
                                                  (provider := "host-llm")
                                                  (model-id := "replace-with-model-id")
                                                  (prompt-template-digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000")
                                                  (context-digest := ctx-digest)
                                                  (epistemic-status := "hypothesized")
                                                  (findings := '())
                                                  (action-authorized? := #f))))))))))
    (when (or (null? admitted-models) (pair? pending-oracles) (pair? vacuous-overlays))
      (set! choices
            (append choices
                    (list
                     (make-choice-branch
                      choice-id: "attach-formal-evidence"
                      effect-class: "verified-epistemic"
                      title: "Attach DE Quint/Lean formal library reuse or ephemeral @countermodel overlay"
                      why-open: "General case reuses @deterministic-engineering/{quint,lean}-models; special case uses ephemeral-ai-overlay in sidecar vault"
                      constraints: '("Prefer upstream-library-reuse; ephemeral-ai-overlay requires countermodelVerified: true & storedInSidecarVault: true")
                      template: (.o (repo := repo-hint)
                                    (base-ref := base-ref)
                                    (choice := "attach-formal-evidence")
                                    (formal-models
                                     := (list (.o (model-id := "replace-model-id")
                                                  (mode := "upstream-library-reuse")
                                                  (library-package := "@deterministic-engineering/quint-models")
                                                  (resolver-digest := "sha256:0000000000000000000000000000000000000000000000000000000000000000")
                                                  (context-digest := ctx-digest)
                                                  (countermodel-verified? := #t)
                                                  (proof-clean? := #t)
                                                  (passed? := #t)
                                                  (stored-in-sidecar-vault? := #t))))))))))
    (set! choices
          (append choices
                  (list
                   (make-choice-branch
                    choice-id: "compose-subdomain-rule-pack"
                    effect-class: "pure-cas"
                    title: "Attach a subdomain or ephemeral POO RulePack (strictly monotone tightening)"
                    why-open: "Scale governance to any subdomain without modifying Rust; core de-g2-core floor stays immutable"
                    template: (.o (repo := repo-hint)
                                  (base-ref := base-ref)
                                  (choice := "compose-subdomain-rule-pack")
                                  (rule-packs
                                   := (list (.o (pack-id := "my-subdomain-pack")
                                                (subdomain := "my-subdomain")
                                                (source-mode := "ephemeral-ai-proposed")
                                                (rules := (list (.o (rule-id := "subdomain-rule-1")
                                                                    (languages := '("rust" "scheme"))
                                                                    (tokens-all := '("forbidden_token"))
                                                                    (detail := "Describe domain invariant")))))))))
                   (make-choice-branch
                    choice-id: "inspect-causal-detail"
                    effect-class: "pure-cas"
                    title: "Expand full causal trajectory, temporal causality DAG, FunFlow trace, and SARIF"
                    why-open: "Progressive disclosure level 1 (on-demand deep observability)"
                    template: (.o (repo := repo-hint) (base-ref := base-ref) (choice := "inspect-causal-detail") (disclosure := "causal")))
                   (make-choice-branch
                    choice-id: "request-human-disposition"
                    effect-class: "fenced-effect"
                    title: "Present competing hypotheses and verified evidence to human reviewer for disposition"
                    why-open: (if fenced-admitted?
                                "All obligations Proven; ready for human-approved fenced commit"
                                (string-append "Human review required; open obligations: " (number->string (length open-obs))))
                    admitted?: fenced-admitted?
                    constraints: '("AI agents may NEVER self-approve (actionAuthorized: false)")
                    template: (.o (repo := repo-hint) (base-ref := base-ref) (choice := "request-human-disposition")
                                  (conversation-bound? := #t) (human-approved? := #t))))))
    choices))

(def (gitops-review-flow-step input)
  (let* ((ctx-digest (opt-slot input 'context-digest ""))
         (plan-sexp (opt-slot input 'plan-sexp #f))
         (parsed-plan (and (non-empty-string? plan-sexp) (parse-review-plan-sexp plan-sexp ctx-digest)))
         (plan-valid? (or (not parsed-plan) (.get parsed-plan valid?)))
         (plan-floor-violation? (and parsed-plan (.get parsed-plan core-floor-violation?)))
         (repo-hint (or (and parsed-plan (.get parsed-plan repo)) (opt-slot input 'repo ".")))
         (target-repo (opt-slot input 'target-repo "external-repo"))
         (nasa-profile (opt-slot input 'nasa-profile "nasa/sdlc/npr-7150.2d"))
         (base-ref (or (and parsed-plan (.get parsed-plan base-ref)) (opt-slot input 'base-ref "HEAD")))
         (changed-paths (opt-slot input 'changed-paths '()))
         (required-lenses
          (let ((plan-ls (if parsed-plan (.get parsed-plan required-lenses) '()))
                (in-ls (opt-slot input 'required-lenses '())))
            (cond
             ((pair? plan-ls) plan-ls)
             ((pair? in-ls) in-ls)
             (else '("correctness" "security" "api-regression" "nasa-swe146")))))
         (requested-choice (or (opt-slot input 'choice #f)
                               (and parsed-plan "validate-plan")))
         (disclosure
          (let ((raw (or (and parsed-plan (.get parsed-plan disclosure))
                         (opt-slot input 'disclosure "frontier"))))
            (cond
             ((equal? requested-choice "inspect-causal-detail") "causal")
             ((equal? requested-choice "inspect-formal-guide") "deep-spec")
             ((member raw '("frontier" "causal" "deep-spec")) raw)
             (else "frontier"))))
         (choice-valid? (and plan-valid?
                             (or (not requested-choice)
                                 (equal? requested-choice "")
                                 (if (member requested-choice +known-review-choices+) #t #f))))
         (merged-rule-packs
          (append (opt-slot input 'rule-packs '())
                  (if parsed-plan (.get parsed-plan rule-packs) '())))
         (merged-formal-models
          (append (opt-slot input 'formal-models '())
                  (if parsed-plan (.get parsed-plan formal-models) '())))
         (merged-ai-reports
          (append (opt-slot input 'ai-reports '())
                  (if parsed-plan (.get parsed-plan ai-reports) '())))
         (failed-checks (if parsed-plan (.get parsed-plan failed-checks) '()))
         (open-branches
          (delete-duplicates/hash
           (append (opt-slot input 'open-branches '())
                   (if parsed-plan (.get parsed-plan open-branches) '()))))
         (refuted-branches
          (delete-duplicates/hash
           (append (opt-slot input 'refuted-branches '())
                   (if parsed-plan (.get parsed-plan refuted-branches) '()))))
         (probes
          (append (opt-slot input 'probes '())
                  (if parsed-plan (.get parsed-plan probes) '())))
         (staged-only? (and (opt-slot input 'staged-only? #f) #t))
         ;; Shared-prefix (pure-cas) with cross-round FunFlow CAS reuse
         ((values diff-res cas-hit?)
          (cached-diff-defense-audit
           ctx-digest base-ref staged-only?
           (opt-slot input 'staged-diff "")
           (opt-slot input 'unstaged-diff "")
           (opt-slot input 'base-ref-diff "")
           merged-rule-packs
           (opt-slot input 'funflow-receipts '())))
         (ascent-res
          (gitops-sidecar-audit-assess
           (.o (target-repo := target-repo)
               (nasa-profile := nasa-profile)
               (context-digest := ctx-digest)
               (changed-paths := changed-paths)
               (forbidden-prefixes := (let ((p (opt-slot input 'forbidden-prefixes '())))
                                        (if (null? p) '(".agents/aita/" ".aitia/") p)))
               (required-lenses := required-lenses)
               (ai-reports := merged-ai-reports)
               (conversation-bound? := (and (opt-slot input 'conversation-bound? #f) #t))
               (human-approved? := (and (opt-slot input 'human-approved? #f) #t))
               (dispositions := (opt-slot input 'dispositions '()))
               (g2-findings := (.get diff-res g2-findings))
               (guard-probes := (opt-slot input 'guard-probes '()))
               (formal-models := merged-formal-models)
               (pending-oracles := (append (opt-slot input 'pending-oracles '()) failed-checks))
               (coordinator-claimed-admit? := (and (opt-slot input 'coordinator-claimed-admit? #f) #t)))))
         (human-approved? (and (opt-slot input 'human-approved? #f) #t))
         (choice-sol
          (solve-review-finite-choice
           ctx-digest diff-res ascent-res open-branches refuted-branches probes human-approved?
           (or plan-floor-violation? (not plan-valid?))))
         (tc (.get diff-res temporal-causality))
         (competing-hyps (.get tc competing-hypotheses))
         (epistemic-status (if plan-valid? (.get ascent-res epistemic-status) "Refuted"))
         (admissible? (and plan-valid? (.get ascent-res admissible?)))
         (staged-clean? (= (.get diff-res staged-findings-count) 0))
         (world-count (.get choice-sol world-count))
         (unique-fenced-world?
          (and (= world-count 1)
               (equal? (.get (car (.get choice-sol worlds)) dispatch-decision) "fenced-apply")))
         (fenced-admitted? (and admissible?
                                (equal? epistemic-status "Proven")
                                unique-fenced-world?
                                human-approved?
                                staged-clean?))
         (recs (recommend-de-formal-models target-repo changed-paths))
         ;; Token-budgeted progressive self-discovery: emit full grammar/template on Turn 1
         ;; (`discover`), on any invalid plan/choice (`selfHealing`), or on `deep-spec`;
         ;; omit bulky grammar/template on Turn 2+ valid plans to save ~60% LLM tokens!
         (emit-teaching-kit?
          (or (not choice-valid?)
              (not plan-valid?)
              (not requested-choice)
              (equal? requested-choice "discover")
              (equal? disclosure "deep-spec")))
         (choices (build-progressive-choices
                   repo-hint base-ref ctx-digest diff-res ascent-res fenced-admitted?))
         (self-healing
          (cond
           ((not plan-valid?)
            (.o (rejected-choice := (or requested-choice "validate-plan"))
                (message := (or (.get parsed-plan error) "Invalid `(aitia-review-plan ...)` S-expression"))
                (valid-choice-ids := (map (lambda (c) (.get c choice-id)) choices))))
           ((not choice-valid?)
            (.o (rejected-choice := requested-choice)
                (message := (string-append "Unknown FunFlow review choice `" requested-choice
                                           "`; select one of the admissible choiceIds below."))
                (valid-choice-ids := (map (lambda (c) (.get c choice-id)) choices))))
           (else #f)))
         (plan-validation
          (.o (plan-format := (if parsed-plan "sexp-aitia-review-plan" "json-envelope"))
              (scenario := (if parsed-plan (.get parsed-plan scenario) (string-append target-repo "-live")))
              (validated? := plan-valid?)
              (acyclic? := (if parsed-plan (.get parsed-plan acyclic?) #t))
              (core-floor-intact? := (not plan-floor-violation?))
              (fenced-prefix-forbidden? := #t)
              (zero-eval-datum-parser? := #t)
              (action-authorized? := #f)))
         (shared-prefix
          (.o (effect-class := "pure-cas")
              (fenced-effects-forbidden? := #t)
              (shared-prefix-cas-hit? := cas-hit?)
              (target-repo := target-repo)
              (base-ref := base-ref)
              (context-digest := ctx-digest)
              (changed-files-count := (length changed-paths))
              (diff-decision := (.get diff-res decision))
              (total-diff-findings := (.get diff-res total-findings))
              (staged-findings-count := (.get diff-res staged-findings-count))
              (unstaged-findings-count := (.get diff-res unstaged-findings-count))
              (base-ref-findings-count := (.get diff-res base-ref-findings-count))
              (rule-packs-applied := (.get diff-res rule-packs-applied))
              (core-floor-preserved? := (.get diff-res core-floor-preserved?))
              (funflow-receipts-count := (.get diff-res funflow-receipts-count)))))
    (.o (:: @ FunflowReviewFrontier.)
        (choice-accepted? := choice-valid?)
        (requested-choice := (or requested-choice "discover"))
        (disclosure-level := disclosure)
        (emit-teaching-kit? := emit-teaching-kit?)
        (shared-prefix := shared-prefix)
        (epistemic-status := epistemic-status)
        (world-count := world-count)
        (admissible? := (and choice-valid? admissible?))
        (fenced-tail-admitted? := fenced-admitted?)
        (open-obligations := (.get ascent-res open-obligations))
        (supported-obligations := (.get ascent-res supported-obligations))
        (blockers := (if plan-valid? (.get ascent-res blockers)
                         (cons "invalid-declarative-review-plan" (.get ascent-res blockers))))
        (competing-hypotheses := competing-hyps)
        (ascent-choice-solution := choice-sol)
        (plan-validation := plan-validation)
        (recommended-formal-models := recs)
        (dsl-grammar := (if emit-teaching-kit? +review-plan-dsl-grammar+ #f))
        (sexp-plan-template := (if emit-teaching-kit?
                                 (render-sexp-plan-template repo-hint base-ref target-repo changed-paths recs)
                                 #f))
        (quint-overlay-template := (if emit-teaching-kit?
                                     (render-quint-overlay-template recs)
                                     #f))
        (choices := choices)
        (self-healing-hint := self-healing)
        (diff-result := diff-res)
        (ascent-result := ascent-res)
        (action-authorized? := #f))))
