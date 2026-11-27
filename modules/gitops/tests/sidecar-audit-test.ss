;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .o .cc .get)
        (only-in "../sidecar-audit.ss" gitops-sidecar-audit-assess)
        (only-in "../diff-governance.ss" gitops-diff-defense-audit rule-pack-from-descriptor))
(export sidecar-audit-test)

(def +ctx-digest+ "sha256:1111111111111111111111111111111111111111111111111111111111111111")
(def +prompt-digest+ "sha256:2222222222222222222222222222222222222222222222222222222222222222")
(def +resolver-digest+ "sha256:3333333333333333333333333333333333333333333333333333333333333333")

(def (mk-report lens engine (ctx +ctx-digest+) (findings '()) (prov-ok? #t))
  (.o (lens := lens)
      (engine-binding := engine)
      (provider := (if prov-ok? "host-llm" ""))
      (model-id := (if prov-ok? "host-agent-ascent-v1" ""))
      (prompt-template-digest := (if prov-ok? +prompt-digest+ ""))
      (context-digest := ctx)
      (epistemic-status := "hypothesized")
      (findings := findings)
      (action-authorized? := #f)))

(def +high-finding+
  (.o id: "SEC-001" severity: "high" file: "src/token_parser.py"))

(def +upstream-quint-model+
  (.o model-id: "oauth-token-lifecycle"
      mode: "upstream-library-reuse"
      library-package: "@deterministic-engineering/quint-models"
      resolver-digest: +resolver-digest+
      context-digest: +ctx-digest+
      countermodel-verified?: #t
      proof-clean?: #t
      passed?: #t
      stored-in-sidecar-vault?: #t))

(def +upstream-lean-model+
  (.o model-id: "SubprocessEnvScrubAndAuthTiming"
      mode: "upstream-library-reuse"
      library-package: "@deterministic-engineering/lean-models"
      resolver-digest: +resolver-digest+
      context-digest: +ctx-digest+
      countermodel-verified?: #f
      proof-clean?: #t
      passed?: #t
      stored-in-sidecar-vault?: #t))

(def +ephemeral-overlay-model+
  (.o model-id: "TokenParserTimingOverlay.qnt"
      mode: "ephemeral-ai-overlay"
      library-package: "@deterministic-engineering/quint-models"
      resolver-digest: +resolver-digest+
      context-digest: +ctx-digest+
      countermodel-verified?: #t
      proof-clean?: #t
      passed?: #t
      stored-in-sidecar-vault?: #t))

(def +base-input+
  (.o target-repo: "upstream-org/token-parser"
      nasa-profile: "nasa/sdlc/npr-7150.2d"
      context-digest: +ctx-digest+
      changed-paths: '("src/token_parser.py")
      forbidden-prefixes: '(".agents/aita/" ".aitia/")
      required-lenses: '("correctness" "security" "api-regression" "nasa-swe146")
      ai-reports: (list (mk-report "correctness" "native-ai-environment")
                        (mk-report "security" "native-ai-environment" +ctx-digest+ (list +high-finding+))
                        (mk-report "api-regression" "marlin-agent-core")
                        (mk-report "nasa-swe146" "marlin-agent-core"))
      conversation-bound?: #t
      human-approved?: #t
      dispositions: (list (.o finding-id: "SEC-001"
                              status: "fixed-verified"
                              rationale: "Verified empty-secret guard + unittest."))))

(def sidecar-audit-test
  (test-suite "RFC 0022 + RFC 0023 native Scheme/POO gerbil-ascent sidecar audit derivation"
    (test-case "complete dual-mode sanctioned audit admits all 4 NASA obligations with zero authority"
      (let ((res (gitops-sidecar-audit-assess +base-input+)))
        (check-equal? (.get res admissible?) #t)
        (check-equal? (.get res epistemic-status) "Proven")
        (check-equal? (.get res action-authorized?) #f)
        (check-equal? (.get res blockers) '())
        (check-equal? (.get res open-obligations) '())
        (check-equal? (.get res supported-obligations) '("SWE-083" "SWE-084" "SWE-087" "SWE-146"))
        (check-equal? (.get res next-handoff-mode) "ready-for-sidecar-commit")
        (check-equal? (.get (.get res marlin-handoff) boundary) "marlin-agent-core")
        (check-equal? (.get (.get res ascent-directive) action-authorized?) #f)))

    (test-case "missing lens keeps SWE-146 open and emits ASCENT + Marlin handoff directives"
      (let* ((partial (.cc +base-input+
                           ai-reports: (list (mk-report "correctness" "native-ai-environment"))))
             (res (gitops-sidecar-audit-assess partial)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res action-authorized?) #f)
        (check-equal? (.get res missing-lenses) '("api-regression" "nasa-swe146" "security"))
        (check-equal? (.get res open-obligations) '("SWE-146"))
        (check-equal? (.get res next-handoff-mode) "dispatch-ai-audit-lenses")
        (check-equal? (.get (.get res marlin-handoff) missing-lenses)
                      '("api-regression" "nasa-swe146" "security"))))

    (test-case "upstream repo pollution blocks SWE-084 and rejects admission"
      (let* ((polluted (.cc +base-input+
                            changed-paths: '("src/token_parser.py" ".agents/aita/project.json")))
             (res (gitops-sidecar-audit-assess polluted)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res upstream-polluted) '(".agents/aita/project.json"))
        (check-equal? (.get res open-obligations) '("SWE-084"))
        (check-equal? (.get res next-handoff-mode) "clean-upstream-pollution")))

    (test-case "unsanctioned ad-hoc CLI engine binding fails closed"
      (let* ((rogue (.cc +base-input+
                         ai-reports: (list (mk-report "correctness" "ad-hoc-cli-http-wrapper")
                                           (mk-report "security" "native-ai-environment" +ctx-digest+ (list +high-finding+))
                                           (mk-report "api-regression" "marlin-agent-core")
                                           (mk-report "nasa-swe146" "marlin-agent-core"))))
             (res (gitops-sidecar-audit-assess rogue)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res disallowed-engines) '(("report-0" "ad-hoc-cli-http-wrapper")))
        (check-equal? (and (member "unsanctioned-engine-binding" (.get res blockers)) #t) #t)))

    (test-case "stale AI audit contextDigest blocks admission and reopens SWE-146"
      (let* ((stale (.cc +base-input+
                         ai-reports: (list (mk-report "correctness" "native-ai-environment"
                                                      "sha256:9999999999999999999999999999999999999999999999999999999999999999")
                                           (mk-report "security" "native-ai-environment" +ctx-digest+ (list +high-finding+))
                                           (mk-report "api-regression" "marlin-agent-core")
                                           (mk-report "nasa-swe146" "marlin-agent-core"))))
             (res (gitops-sidecar-audit-assess stale)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (and (member "stale-ai-audit" (.get res blockers)) #t) #t)
        (check-equal? (.get res open-obligations) '("SWE-146"))))

    (test-case "unaddressed high-severity finding keeps SWE-087 open and blocks commit"
      (let* ((unaddressed (.cc +base-input+ dispositions: '()))
             (res (gitops-sidecar-audit-assess unaddressed)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res unaddressed-high-findings) '("SEC-001"))
        (check-equal? (.get res open-obligations) '("SWE-087"))
        (check-equal? (.get res next-handoff-mode) "human-independent-review")))

    ;; RFC 0023 tests: Deterministic Engineering formal library reuse, ephemeral AI overlays,
    ;; G2 mechanical defects, F3 guard-probe, PendingMethod, and N-Version disagreement.
    (test-case "RFC 0023 upstream-library-reuse (Quint + LeanPoo) and ephemeral-ai-overlay with countermodel both admit cleanly"
      (let* ((full (.cc +base-input+
                        guard-probes: (list (.o probe-id: "empty-secret-guard" verdict: "essential"))
                        formal-models: (list +upstream-quint-model+
                                             +upstream-lean-model+
                                             +ephemeral-overlay-model+)))
             (res (gitops-sidecar-audit-assess full)))
        (check-equal? (.get res admissible?) #t)
        (check-equal? (.get res epistemic-status) "Proven")
        (check-equal? (.get res action-authorized?) #f)
        (check-equal? (.get res admitted-formal-models)
                      '(("SubprocessEnvScrubAndAuthTiming" "upstream-library-reuse")
                        ("TokenParserTimingOverlay.qnt" "ephemeral-ai-overlay")
                        ("oauth-token-lifecycle" "upstream-library-reuse")))
        (check-equal? (.get (.get res formal-library-guidance) general-case-mode)
                      "upstream-library-reuse")
        (check-equal? (.get (.get res formal-library-guidance) special-case-mode)
                      "ephemeral-ai-overlay")
        (check-equal? (.get (.get res funflow-trace) schema)
                      "lambda-aitia.funflow-ascent-trace.v1")
        (check-equal? (.get (.get (.get res funflow-trace) derived-counts) admitted-formal-models) 3)
        (check-equal? (.get (.get res funflow-trace) action-authorized?) #f)))

    (test-case "RFC 0023 vacuous ephemeral-ai-overlay missing MR05 @countermodel fails closed"
      (let* ((vacuous (.cc +base-input+
                           formal-models: (list (.cc +ephemeral-overlay-model+
                                                     countermodel-verified?: #f))))
             (res (gitops-sidecar-audit-assess vacuous)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res vacuous-ephemeral-overlays) '("TokenParserTimingOverlay.qnt"))
        (check-equal? (and (member "de-vacuous-ephemeral-overlay" (.get res blockers)) #t) #t)
        (check-equal? (.get res open-obligations) '("SWE-084" "SWE-146"))
        (check-equal? (.get res next-handoff-mode) "repair-formal-and-mechanical-defects")))

    (test-case "RFC 0023 ephemeral-ai-overlay polluting upstream repo instead of sidecar vault fails closed"
      (let* ((polluting (.cc +base-input+
                             formal-models: (list (.cc +ephemeral-overlay-model+
                                                       stored-in-sidecar-vault?: #f))))
             (res (gitops-sidecar-audit-assess polluting)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res polluting-ephemeral-overlays) '("TokenParserTimingOverlay.qnt"))
        (check-equal? (and (member "de-polluting-ephemeral-overlay" (.get res blockers)) #t) #t)
        (check-equal? (.get res next-handoff-mode) "clean-upstream-pollution")))

    (test-case "RFC 0023 DE G2 diff-delta defect and redundant F3 guard-probe fail closed"
      (let* ((defective (.cc +base-input+
                             g2-findings: (list (.o id: "G2-001"
                                                    rule: "unwrap-or-default-silent-fallback"
                                                    hallucination-class: "silent-fallback"))
                             guard-probes: (list (.o probe-id: "dup-null-check"
                                                     verdict: "redundant-or-under-modeled"))))
             (res (gitops-sidecar-audit-assess defective)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res g2-defects) '("silent-fallback:G2-001"))
        (check-equal? (.get res redundant-guard-probes) '("dup-null-check"))
        (check-equal? (and (member "de-g2-mechanical-defect" (.get res blockers)) #t) #t)
        (check-equal? (and (member "de-redundant-guard-probe" (.get res blockers)) #t) #t)
        (check-equal? (.get res open-obligations) '("SWE-083" "SWE-087"))))

    (test-case "RFC 0023 unresolved formal library resolver and PendingMethod oracle never silently pass"
      (let* ((pending (.cc +base-input+
                           pending-oracles: '("de-g2-auditor")))
             (res-pending (gitops-sidecar-audit-assess pending))
             (unresolved (.cc +base-input+
                              formal-models: (list (.cc +upstream-quint-model+ resolver-digest: ""))))
             (res-unresolved (gitops-sidecar-audit-assess unresolved)))
        (check-equal? (.get res-pending admissible?) #f)
        (check-equal? (.get res-pending epistemic-status) "PendingMethod")
        (check-equal? (.get res-pending pending-oracles) '("de-g2-auditor"))
        (check-equal? (.get res-pending next-handoff-mode) "run-pending-mechanical-oracles")
        (check-equal? (.get res-unresolved admissible?) #f)
        (check-equal? (.get res-unresolved unresolved-formal-models) '("oauth-token-lifecycle"))
        (check-equal? (and (member "de-unresolved-formal-library" (.get res-unresolved blockers)) #t) #t)))

    (test-case "RFC 0023 N-Version oracle-disagreement-fail-closed triggers when coordinator claims ADMIT despite blockers"
      (let* ((disagree (.cc +base-input+
                            g2-findings: (list (.o id: "G2-002"
                                                   rule: "diff-deleted-assertion"
                                                   hallucination-class: "floor-weakening"))
                            coordinator-claimed-admit?: #t))
             (res (gitops-sidecar-audit-assess disagree)))
        (check-equal? (.get res admissible?) #f)
        (check-equal? (.get res oracle-disagreement?) #t)
        (check-equal? (and (member "oracle-disagreement-fail-closed" (.get res blockers)) #t) #t)
        (check-equal? (.get res next-handoff-mode) "resolve-n-version-oracle-disagreement")
        (check-equal? (.get res action-authorized?) #f)))

    (test-case "Scheme POO diff-governance strips strings/comments, catches multi-line Scheme with-catch, and enforces monotone subdomain rule packs"
      (let* ((string-only-diff
              (string-append
               "+++ b/src/linter.rs\n"
               "@@ -1,2 +1,4 @@\n"
               "+let msg = \"Do NOT use .unwrap_or_default() or @ts-ignore or catch-and-rethrow\";\n"
               "+// Err(_) => Ok(()) inside comment must not trigger false positive\n"))
             (clean-res
              (gitops-diff-defense-audit
               (.o base-ref: "HEAD~1"
                   staged-only?: #f
                   staged-diff: ""
                   unstaged-diff: ""
                   base-ref-diff: string-only-diff
                   rule-packs: '()
                   funflow-receipts: '())))
             (multiline-scheme-and-subdomain-diff
              (string-append
               "+++ b/scheme/kernel/bridge.ss\n"
               "@@ -10,2 +10,6 @@\n"
               "-(check-equal? (verify-cap tok) #t)\n"
               "+(with-catch\n"
               "+  (lambda (_) #f)\n"
               "+  (lambda () (raw-shell-bypass cmd)))\n"))
             (marlin-pack
              (rule-pack-from-descriptor
               (.o pack-id: "marlin-kernel-confinement"
                   subdomain: "marlin-kernel"
                   source-mode: "subdomain-library"
                   rules: (list (.o rule-id: "no-raw-shell-bypass"
                                    hallucination-class: "subdomain-invariant-violation"
                                    languages: '("scheme")
                                    tokens-all: '("raw-shell-bypass")
                                    detail: "Marlin kernel forbids raw-shell-bypass outside fenced capability")))))
             (defective-res
              (gitops-diff-defense-audit
               (.o base-ref: "HEAD~1"
                   staged-only?: #f
                   staged-diff: multiline-scheme-and-subdomain-diff
                   unstaged-diff: ""
                   base-ref-diff: ""
                   rule-packs: (list marlin-pack)
                   funflow-receipts: (list (.o flow: "choice-flow" world-count: 1))))))
        (check-equal? (.get clean-res passed?) #t)
        (check-equal? (.get clean-res total-findings) 0)
        (check-equal? (.get clean-res engine-owner) "scheme-poo-ascent-framework")
        (check-equal? (.get clean-res action-authorized?) #f)
        (check-equal? (.get defective-res passed?) #f)
        (check-equal? (.get defective-res core-floor-preserved?) #t)
        (check-equal? (.get defective-res rule-packs-applied) '("de-g2-core" "marlin-kernel-confinement"))
        (check-equal? (.get defective-res diff-deleted-assertions-count) 1)
        (check-equal? (.get (.get defective-res counts-by-class) silent-fallback) 1)
        (check-equal? (.get (.get defective-res counts-by-class) floor-weakening) 1)
        (check-equal? (.get (.get defective-res counts-by-class) subdomain-invariant-violation) 1)
        (check-equal? (.get (.get defective-res temporal-causality) acyclic?) #t)
        (check-equal? (.get defective-res funflow-receipts-count) 1)
        (check-equal? (.get defective-res action-authorized?) #f)))))
