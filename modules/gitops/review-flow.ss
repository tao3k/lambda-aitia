;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; FunFlow Choice + Native Lean-Verified `gerbil-ascent` Finite-Choice Review Engine
;;; (`aitia review [plan.sexp | plan.json | repo]` / Marlin gRPC `StepReview`).
;;;
;;; Unifies LLM-authored scenario plans with mechanical `closed`-invariant validation:
;;;   1. Pure-datum S-expression DSL parser (`parse-review-plan-sexp`, ZERO `eval`):
;;;      LLMs write a scenario-specific `(aitia-review-plan ...)` file declaring
;;;      `open-branches`, epistemic `probes` (`supports`/`refutes`/`inconclusive`),
;;;      and subdomain POO `rule-pack`s without touching Rust or weakening core floors.
;;;   2. Native `gerbil-ascent` `relational-choice-program` + `relational-choice-solve`
;;;      with `provenance?: #t`:
;;;      - `closed` rules enforce immutable core invariants (`de-g2-core`, staged clean,
;;;        core-floor preservation, human-approved unique world for `fenced-apply`).
;;;      - `open` rules admit bounded LLM / subdomain divergent branches (`M_1..M_k`).
;;;      - `refutes` probes / `refuted-branches` emit empty `closed` offers that
;;;        automatically prune disproven worlds (`world-count` converges `k -> 1`).
;;;   3. Always preserves competing hypotheses and `action-authorized?: #f`.

(import (only-in :clan/poo/object .def .get .o .ref .slot? object?)
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
        gitops-review-flow-step)

(def (opt-slot obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (non-empty-string? value)
  (and (string? value) (> (string-length value) 0)))

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

;; ── Pure-Datum S-Expression Scenario Plan Parser (ZERO eval!) ──────────────

(def (sexp-string-list elems)
  (filter non-empty-string?
          (map (lambda (x)
                 (cond ((string? x) x)
                       ((symbol? x) (symbol->string x))
                       (else "")))
               elems)))

(def (parse-sexp-rule form)
  ;; (rule "rule-id" (languages "rust" "scheme") (tokens-all "tok") (tokens-any ...) (forbid-unless ...) (detail "..."))
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
  ;; (rule-pack "pack-id" "subdomain" (rule ...) ...)
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
  ;; (probe "branch-name" supports|refutes|inconclusive "detail")
  (if (not (and (pair? form) (eq? (car form) 'probe) (>= (length form) 3)))
    #f
    (let ((branch (sym->str (cadr form)))
          (verdict (sym->str (caddr form)))
          (detail (if (>= (length form) 4) (sym->str (cadddr form)) "")))
      (.o (branch := branch)
          (verdict := verdict)
          (detail := detail)))))

;;; Safely reads a declarative `(aitia-review-plan ...)` S-expression string
;;; without invoking `eval`. Rejects any forbidden attempt to disable the DE G2
;;; core floor or claim execution authority (`action-authorized?`).
(def (parse-review-plan-sexp text)
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
          (scenario := "")
          (repo := #f)
          (base-ref := #f)
          (disclosure := #f)
          (required-lenses := '())
          (open-branches := '())
          (refuted-branches := '())
          (probes := '())
          (rule-packs := '()))
      (let ((scenario "unnamed-scenario")
            (repo #f)
            (base-ref #f)
            (disclosure #f)
            (required-lenses '())
            (open-branches '())
            (refuted-branches '())
            (probes '())
            (rule-packs '())
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
               ;; Fail-closed security boundary: LLM plans may NEVER weaken core floor or authorize effects!
               ((disable-core-floor skip-g2 authorize-action fenced-in-prefix eval)
                (set! floor-violation? #t)
                (set! violation-reason
                      (string-append "Forbidden declarative plan clause `"
                                     (symbol->string (car clause))
                                     "`: LLM plans are strictly monotone and cannot weaken closed invariants or authorize effects"))))))
         (cdr parsed))
        (.o (valid? := (not floor-violation?))
            (error := violation-reason)
            (core-floor-violation? := floor-violation?)
            (scenario := scenario)
            (repo := repo)
            (base-ref := base-ref)
            (disclosure := disclosure)
            (required-lenses := required-lenses)
            (open-branches := (delete-duplicates/hash open-branches))
            (refuted-branches := (delete-duplicates/hash refuted-branches))
            (probes := probes)
            (rule-packs := rule-packs))))))

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
         ;; Collect refuted branches from BOTH explicit `refuted-branches` AND `probes` with verdict `refutes`
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
         ;; Default open branches if caller didn't supply custom scenario branches
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
            ;; Functional Finite-Choice attributes per world
            (choice review_branch (cut value))
            (choice dispatch_decision (cut value))
            ;; 1. Bounded open divergence from LLM/subdomain scenario plan
            (rule (open (review_branch ?c) ?b)
                  (open_branch_offer ?c ?b))
            ;; 2. Closed hard refutation -> empty closed offer prunes disproven worlds!
            (rule (closed (review_branch ?c) ())
                  (review_branch ?c ?b)
                  (refuted_branch ?c ?b))
            ;; 3. Closed hard contradiction if LLM plan attempts to weaken core floor!
            (rule (closed (dispatch_decision ?c) ())
                  (core_floor_violated ?c))
            ;; 4. Closed dispatch invariants (LLM open offers can NEVER override these!)
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
   "  (scenario \"<name>\")             ; Scenario label"
   "  (repo \"<path>\")                 ; Optional repo path (default \".\")"
   "  (base-ref \"<git-ref>\")          ; Optional base ref (default \"HEAD\")"
   "  (disclosure \"frontier\"|\"causal\"|\"deep-spec\")"
   "  (open-branches \"<b1>\" \"<b2>\"...) ; Bounded ASCENT open hypotheses"
   "  (refuted-branches \"<b1>\"...)    ; Prunes worlds via closed empty offer"
   "  (probes (probe \"<branch>\" supports|refutes|inconclusive \"<witness>\")...)"
   "  (rule-pack \"<pack-id>\" \"<subdomain>\" (rule \"<id>\" (languages \"rust\" \"scheme\"...) (tokens-all \"<t>\"...) (tokens-any ...) (forbid-unless ...) (detail \"...\"))...)"
   "  (required-lenses \"correctness\" \"security\" \"api-regression\" \"nasa-swe146\")"
   "FORBIDDEN (fail-closed): disable-core-floor, skip-g2, authorize-action, fenced-in-prefix, eval"))

(def (render-sexp-plan-template repo-hint base-ref target-repo)
  (string-append
   "(aitia-review-plan\n"
   "  (scenario \"" target-repo "-review\")\n"
   "  (repo \"" repo-hint "\")\n"
   "  (base-ref \"" base-ref "\")\n"
   "  (disclosure \"frontier\")\n"
   "  (open-branches \"hypothesis-a\" \"hypothesis-b\")\n"
   "  (probes\n"
   "    (probe \"hypothesis-a\" supports \"describe executable witness\"))\n"
   "  (rule-pack \"" target-repo "-subdomain-pack\" \"" target-repo "\"\n"
   "    (rule \"subdomain-invariant-1\"\n"
   "      (languages \"rust\" \"scheme\")\n"
   "      (tokens-all \"forbidden_pattern\")\n"
   "      (detail \"Describe domain-specific invariant\"))))"))

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
                                     "Do NOT weaken assertions, add skip/ignore, or add silent fallbacks"
                                     "Re-run `aitia review` after editing to advance the causal trajectory")
                      template: (.o (repo := repo-hint)
                                    (base-ref := base-ref)
                                    (choice := "discover")))
                     (make-choice-branch
                      choice-id: "attach-guard-probe-witness"
                      effect-class: "verified-epistemic"
                      title: "Submit DE F3 Quint guard-probe witness for disputed defensive checks"
                      why-open: "Competing hypothesis: a flagged check may be an essential boundary invariant"
                      constraints: '("Verdict must come from an executable Quint F3 guard-probe"
                                     "Hypothetical fit never authorizes effects (actionAuthorized: false)")
                      template: (.o (repo := repo-hint)
                                    (base-ref := base-ref)
                                    (choice := "attach-guard-probe-witness")
                                    (guard-probes := (list (.o (probe-id := "probe-1")
                                                               (verdict := "essential"))))))))))
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
                      constraints: '("epistemicStatus MUST equal \"hypothesized\""
                                     "actionAuthorized MUST equal false"
                                     "Preserve competingHypotheses and openQuestions without probability collapse"
                                     "Include SWE-146 provider, modelId, and sha256 promptTemplateDigest")
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
                      constraints: '("Prefer upstream-library-reuse for generic protocol/safety properties"
                                     "ephemeral-ai-overlay MUST set countermodelVerified: true and storedInSidecarVault: true"
                                     "Bind contextDigest to the live sharedPrefix.contextDigest")
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
                    constraints: '("Additive only: never weakens de-g2-core findings"
                                   "Or author a declarative `(aitia-review-plan ...)` file and pass to `aitia review <plan.sexp>`")
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
                    template: (.o (repo := repo-hint)
                                  (base-ref := base-ref)
                                  (choice := "inspect-causal-detail")
                                  (disclosure := "causal")))
                   (make-choice-branch
                    choice-id: "request-human-disposition"
                    effect-class: "fenced-effect"
                    title: "Present competing hypotheses and verified evidence to human reviewer for disposition"
                    why-open: (if fenced-admitted?
                                "All mechanical, lens, and formal obligations are Proven; ready for human-approved fenced commit"
                                (string-append "Human review required; open obligations: "
                                               (number->string (length open-obs))))
                    admitted?: fenced-admitted?
                    constraints: '("AI agents may NEVER self-approve (actionAuthorized: false)"
                                   "Fenced commit requires worldCount == 1, epistemicStatus == Proven, stagedFindingsCount == 0, and explicit human approval")
                    template: (.o (repo := repo-hint)
                                  (base-ref := base-ref)
                                  (choice := "request-human-disposition")
                                  (conversation-bound? := #t)
                                  (human-approved? := #t))))))
    choices))

(def (gitops-review-flow-step input)
  (let* ((plan-sexp (opt-slot input 'plan-sexp #f))
         (parsed-plan (and (non-empty-string? plan-sexp) (parse-review-plan-sexp plan-sexp)))
         (plan-valid? (or (not parsed-plan) (.get parsed-plan valid?)))
         (plan-floor-violation? (and parsed-plan (.get parsed-plan core-floor-violation?)))
         (repo-hint (or (and parsed-plan (.get parsed-plan repo)) (opt-slot input 'repo ".")))
         (target-repo (opt-slot input 'target-repo "external-repo"))
         (nasa-profile (opt-slot input 'nasa-profile "nasa/sdlc/npr-7150.2d"))
         (base-ref (or (and parsed-plan (.get parsed-plan base-ref)) (opt-slot input 'base-ref "HEAD")))
         (ctx-digest (opt-slot input 'context-digest ""))
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
         ;; Shared-prefix (pure-cas): Scheme POO diff-governance over raw VCS diff surfaces
         (diff-res
          (gitops-diff-defense-audit
           (.o (base-ref := base-ref)
               (staged-only? := (and (opt-slot input 'staged-only? #f) #t))
               (staged-diff := (opt-slot input 'staged-diff ""))
               (unstaged-diff := (opt-slot input 'unstaged-diff ""))
               (base-ref-diff := (opt-slot input 'base-ref-diff ""))
               (rule-packs := merged-rule-packs)
               (funflow-receipts := (opt-slot input 'funflow-receipts '())))))
         ;; Scheme/ASCENT sidecar obligation derivation
         (ascent-res
          (gitops-sidecar-audit-assess
           (.o (target-repo := target-repo)
               (nasa-profile := nasa-profile)
               (context-digest := ctx-digest)
               (changed-paths := changed-paths)
               (forbidden-prefixes := (let ((p (opt-slot input 'forbidden-prefixes '())))
                                        (if (null? p) '(".agents/aita/" ".aitia/") p)))
               (required-lenses := required-lenses)
               (ai-reports := (opt-slot input 'ai-reports '()))
               (conversation-bound? := (and (opt-slot input 'conversation-bound? #f) #t))
               (human-approved? := (and (opt-slot input 'human-approved? #f) #t))
               (dispositions := (opt-slot input 'dispositions '()))
               (g2-findings := (.get diff-res g2-findings))
               (guard-probes := (opt-slot input 'guard-probes '()))
               (formal-models := (opt-slot input 'formal-models '()))
               (pending-oracles := (opt-slot input 'pending-oracles '()))
               (coordinator-claimed-admit? := (and (opt-slot input 'coordinator-claimed-admit? #f) #t)))))
         (human-approved? (and (opt-slot input 'human-approved? #f) #t))
         ;; Native Lean-verified `gerbil-ascent` Finite-Choice solver (`closed` vs `open` + provenance!)
         (choice-sol
          (solve-review-finite-choice
           ctx-digest diff-res ascent-res open-branches refuted-branches probes human-approved? plan-floor-violation?))
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
              (core-floor-intact? := (not plan-floor-violation?))
              (fenced-prefix-forbidden? := #t)
              (zero-eval-datum-parser? := #t)
              (action-authorized? := #f)))
         (shared-prefix
          (.o (effect-class := "pure-cas")
              (fenced-effects-forbidden? := #t)
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
        (dsl-grammar := +review-plan-dsl-grammar+)
        (sexp-plan-template := (render-sexp-plan-template repo-hint base-ref target-repo))
        (choices := choices)
        (self-healing-hint := self-healing)
        (diff-result := diff-res)
        (ascent-result := ascent-res)
        (action-authorized? := #f))))
