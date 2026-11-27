;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .o .cc .get)
        (only-in "../sidecar-audit.ss" gitops-sidecar-audit-assess))
(export sidecar-audit-test)

(def +ctx-digest+ "sha256:1111111111111111111111111111111111111111111111111111111111111111")
(def +prompt-digest+ "sha256:2222222222222222222222222222222222222222222222222222222222222222")

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
  (test-suite "RFC 0022 native Scheme/POO gerbil-ascent sidecar audit derivation"
    (test-case "complete dual-mode sanctioned audit admits all 4 NASA obligations with zero authority"
      (let ((res (gitops-sidecar-audit-assess +base-input+)))
        (check-equal? (.get res admissible?) #t)
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
        (check-equal? (.get res next-handoff-mode) "human-independent-review")))))
