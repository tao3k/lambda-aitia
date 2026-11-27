;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; FunFlow Choice-Driven Progressive Review Frontier (`aitia review` / gRPC `StepReview`).
;;;
;;; Replaces human flag-soup CLIs with ONE single progressive Scheme/ASCENT/FunFlow entrypoint:
;;;   - `shared-prefix` (`pure-cas`): executes read-only VCS + diff-governance + ASCENT derivation
;;;     (forbids fenced effects).
;;;   - `choices` (`FunflowChoiceBranch.`): dynamically projects ONLY the currently admissible
;;;     epistemic moves with pre-filled JSON templates bound to the live `context-digest`,
;;;     preserving competing hypotheses without hard-coding a single "next" path.
;;;   - `fenced-tail` (`fenced-effect`): admitted ONLY when `epistemic-status == "Proven"`,
;;;     `world-count == 1`, `human-approved? == #t`, and `staged-findings-count == 0`, while
;;;     always preserving `action-authorized?: #f`.
;;;   - Self-healing feedback: invalid or unrecognised `choice` names fail closed AND return the
;;;     exact valid choice IDs and minimal pre-filled templates so LLMs recover in 1 turn.

(import (only-in :clan/poo/object .def .get .o .ref .slot? object?)
        (only-in :std/list/list filter)
        "diff-governance.ss"
        "sidecar-audit.ss")

(export FunflowChoiceBranch.
        FunflowReviewFrontier.
        gitops-review-flow-step)

(def (opt-slot obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (non-empty-string? value)
  (and (string? value) (> (string-length value) 0)))

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

(def +known-review-choices+
  '("discover"
    "repair-diff-defects"
    "attach-guard-probe-witness"
    "compose-subdomain-rule-pack"
    "submit-ai-lens-report"
    "attach-formal-evidence"
    "inspect-causal-detail"
    "inspect-formal-guide"
    "request-human-disposition"))

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
    ;; 1. If G2 / subdomain diff defects exist, surface BOTH repair AND competing guard-probe witness choices
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
    ;; 2. Missing AI audit lenses or unaddressed high findings
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
    ;; 3. Formal verification choice (general upstream library reuse OR special ephemeral @countermodel overlay)
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
    ;; 4. Always-available monotone subdomain rule-pack extension choice (for 1,000+ subdomains)
    (set! choices
          (append choices
                  (list
                   (make-choice-branch
                    choice-id: "compose-subdomain-rule-pack"
                    effect-class: "pure-cas"
                    title: "Attach a subdomain or ephemeral POO RulePack (strictly monotone tightening)"
                    why-open: "Scale governance to any subdomain without modifying Rust; core de-g2-core floor stays immutable"
                    constraints: '("Additive only: never weakens de-g2-core findings"
                                   "Declarative tokensAll/tokensAny/forbidUnless evaluated by Scheme POO lexer")
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
  (let* ((repo-hint (opt-slot input 'repo "."))
         (target-repo (opt-slot input 'target-repo "external-repo"))
         (nasa-profile (opt-slot input 'nasa-profile "nasa/sdlc/npr-7150.2d"))
         (base-ref (opt-slot input 'base-ref "HEAD"))
         (ctx-digest (opt-slot input 'context-digest ""))
         (changed-paths (opt-slot input 'changed-paths '()))
         (required-lenses
          (let ((ls (opt-slot input 'required-lenses '())))
            (if (null? ls) '("correctness" "security" "api-regression" "nasa-swe146") ls)))
         (requested-choice (opt-slot input 'choice #f))
         (disclosure
          (let ((raw (opt-slot input 'disclosure "frontier")))
            (cond
             ((equal? requested-choice "inspect-causal-detail") "causal")
             ((equal? requested-choice "inspect-formal-guide") "deep-spec")
             ((member raw '("frontier" "causal" "deep-spec")) raw)
             (else "frontier"))))
         (choice-valid? (or (not requested-choice)
                            (equal? requested-choice "")
                            (if (member requested-choice +known-review-choices+) #t #f)))
         ;; Shared-prefix (pure-cas): run Scheme POO diff-governance over raw VCS diff surfaces
         (diff-res
          (gitops-diff-defense-audit
           (.o (base-ref := base-ref)
               (staged-only? := (and (opt-slot input 'staged-only? #f) #t))
               (staged-diff := (opt-slot input 'staged-diff ""))
               (unstaged-diff := (opt-slot input 'unstaged-diff ""))
               (base-ref-diff := (opt-slot input 'base-ref-diff ""))
               (rule-packs := (opt-slot input 'rule-packs '()))
               (funflow-receipts := (opt-slot input 'funflow-receipts '())))))
         ;; Feed diff findings straight into Scheme/ASCENT sidecar obligation engine
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
         (tc (.get diff-res temporal-causality))
         (competing-hyps (.get tc competing-hypotheses))
         (epistemic-status (.get ascent-res epistemic-status))
         (admissible? (.get ascent-res admissible?))
         (human-approved? (and (opt-slot input 'human-approved? #f) #t))
         (staged-clean? (= (.get diff-res staged-findings-count) 0))
         ;; Converged to 1 unique proven world ONLY when ASCENT is Proven & diff is clean
         (world-count (if (and admissible? (.get diff-res passed?))
                        1
                        (max 2 (length competing-hyps))))
         (fenced-admitted? (and admissible?
                                (equal? epistemic-status "Proven")
                                (= world-count 1)
                                human-approved?
                                staged-clean?))
         (choices (build-progressive-choices
                   repo-hint base-ref ctx-digest diff-res ascent-res fenced-admitted?))
         (self-healing
          (if choice-valid?
            #f
            (.o (rejected-choice := requested-choice)
                (message := (string-append "Unknown FunFlow review choice `" requested-choice
                                           "`; select one of the admissible choiceIds below."))
                (valid-choice-ids := (map (lambda (c) (.get c choice-id)) choices)))))
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
        (blockers := (.get ascent-res blockers))
        (competing-hypotheses := competing-hyps)
        (choices := choices)
        (self-healing-hint := self-healing)
        (diff-result := diff-res)
        (ascent-result := ascent-res)
        (action-authorized? := #f))))
