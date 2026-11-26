;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Dual-profile obligation projection (Standard-Free SDLC Core vs NASA NPR 7150.2D)
;;; and 5-state AI-Native Mixed-Initiative Inversion-of-Control protocol qualification.

(import :std/test
        (only-in :clan/poo/object .o .get .ref)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))

(export aitia-workflow-protocol-profile-test)

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
      summary: "Wire dual-profile 5-state protocol"
      rationale: "Decouple SDLC Core from NASA Profile and separate Agent synthesis from Human decision."))

(def aitia-workflow-protocol-profile-test
  (test-suite "Lambda Aitia dual-profile obligation projection and 5-state Mixed-Initiative protocol"

    (test-case "1. Dual-profile obligation projection separates Standard-Free SDLC Core from NASA NPR 7150.2D"
      (let* ((sdlc-domain (.get wf gitops-commit-domain))
             (nasa-domain (.get wf gitops-nasa-commit-domain))
             (g-sdlc ((.get wf gitops-commit-graph)
                      test-naming test-cut test-sources '("justfile") (list valid-proposal)
                      profile: "lambda-aitia/sdlc"
                      approval-live?: #f))
             (g-nasa ((.get wf gitops-commit-graph)
                      test-naming test-cut test-sources '("justfile") (list valid-proposal)
                      profile: "nasa/sdlc/npr-7150.2"
                      approval-live?: #f))
             (sdlc-ob-ids (map (lambda (o) (.ref o 'obligation-id)) (.ref g-sdlc 'obligations)))
             (nasa-ob-ids (map (lambda (o) (.ref o 'obligation-id)) (.ref g-nasa 'obligations))))
        (check-equal? (.get sdlc-domain profile-id) "lambda-aitia/sdlc")
        (check-equal? (.get nasa-domain profile-id) "nasa/sdlc/npr-7150.2")
        (check (and (member "sdlc.change-record" sdlc-ob-ids) #t) => #t)
        (check (and (member "sdlc.config-audit" sdlc-ob-ids) #t) => #t)
        (check-equal? (member "SWE-083" sdlc-ob-ids) #f)
        (check (and (member "SWE-083" nasa-ob-ids) #t) => #t)
        (check (and (member "SWE-084" nasa-ob-ids) #t) => #t)
        (check-equal? (member "sdlc.change-record" nasa-ob-ids) #f)))

    (test-case "2. 5-state AI-Native Mixed-Initiative protocol classifies host-probe, agent-synthesis, human-decision, fenced-effect, and quiescent"
      (let* (;; State 1: need-host-frames (host-probe / model-reality-gap)
             (s1 ((.get wf plan-protocol-step)
                  (.o (case-id := 'aitia/case/gitops-commit)
                      (profile := "lambda-aitia/sdlc")
                      (directory := "."))))
             ;; State 2: need-agent-synthesis (agent-synthesis / model-check-gap) with Schwarz repair tasks
             (s2 ((.get wf plan-protocol-step)
                  (.o (case-id := 'aitia/case/gitops-commit)
                      (profile := "lambda-aitia/sdlc")
                      (directory := ".")
                      (receipts := (.o (jj-observe-cut := #t)
                                       (sysml-project-scopes := '())))
                      (naming := test-naming)
                      (cut := test-cut)
                      (sources := test-sources)
                      (paths := '(".github/workflows/ci.yml"))
                      (proposals := (list valid-proposal))
                      (approval-live? := #f)
                      (reconcile? := #t))))
             ;; State 3: need-human-decision (human-decision / requirement-gap)
             (s3 ((.get wf plan-protocol-step)
                  (.o (case-id := 'aitia/case/gitops-commit)
                      (profile := "lambda-aitia/sdlc")
                      (directory := ".")
                      (receipts := (.o (jj-observe-cut := #t)
                                       (sysml-project-scopes := '())))
                      (naming := test-naming)
                      (cut := test-cut)
                      (sources := test-sources)
                      (paths := '("justfile"))
                      (proposals := (list valid-proposal))
                      (approval-live? := #f)
                      (reconcile? := #t))))
             ;; State 4: need-fenced-frames (host-fenced-effect / none)
             (s4 ((.get wf plan-protocol-step)
                  (.o (case-id := 'aitia/case/gitops-commit)
                      (profile := "nasa/sdlc/npr-7150.2")
                      (directory := ".")
                      (receipts := (.o (jj-observe-cut := #t)
                                       (sysml-project-scopes := '())))
                      (naming := test-naming)
                      (cut := test-cut)
                      (sources := test-sources)
                      (paths := '("justfile"))
                      (proposals := (list valid-proposal))
                      (approval-live? := #t)
                      (reconcile? := #f))))
             ;; State 5: quiescent (none / none)
             (s5 ((.get wf plan-protocol-step)
                  (.o (case-id := 'aitia/case/gitops-commit)
                      (profile := "lambda-aitia/sdlc")
                      (directory := ".")
                      (receipts := (.o (jj-observe-cut := #t)
                                       (sysml-project-scopes := '())))
                      (naming := test-naming)
                      (cut := test-cut)
                      (sources := test-sources)
                      (paths := '("justfile"))
                      (proposals := (list valid-proposal))
                      (approval-live? := #t)
                      (reconcile? := #t)))))
        (check-equal? (.get s1 state) 'need-host-frames)
        (check-equal? (.get s1 handoff-target) 'host-probe)
        (check-equal? (.get s1 gap-kind) 'model-reality-gap)
        (check-equal? (.get s2 state) 'need-agent-synthesis)
        (check-equal? (.get s2 handoff-target) 'agent-synthesis)
        (check-equal? (.get s2 gap-kind) 'model-check-gap)
        (check-equal? (length (.get s2 repair-tasks)) 1)
        (check-equal? (.get (car (.get s2 repair-tasks)) unscoped-paths) '(".github/workflows/ci.yml"))
        (check-equal? (.get (car (.get s2 repair-tasks)) action-authorized?) #f)
        (check-equal? (.get s3 state) 'need-human-decision)
        (check-equal? (.get s3 handoff-target) 'human-decision)
        (check-equal? (.get s3 gap-kind) 'requirement-gap)
        (check-equal? (.get s3 repair-tasks) '())
        (check-equal? (.get s4 state) 'need-fenced-frames)
        (check-equal? (.get s4 handoff-target) 'host-fenced-effect)
        (check-equal? (.get s4 gap-kind) 'none)
        (check-equal? (.get s4 profile) "nasa/sdlc/npr-7150.2")
        (check-equal? (length (.get s4 frames)) 1)
        (check-equal? (.get s5 state) 'quiescent)
        (check-equal? (.get s5 handoff-target) 'none)
        (check-equal? (.get s5 gap-kind) 'none)
        (check-equal? (.get s5 action-authorized?) #f)))

    (test-case "3. Evidence decay tracking detects stale cut observations and 2-stage fenced protocol transitions prepare -> apply -> quiescent"
      (let* ((stale-cut
              (.o project: "tao3k/lambda-aitia"
                  workspace: "default"
                  change: "sywptlmp"
                  operation: "op-old"
                  commit: "old-commit-000"
                  tree: "tree-old"
                  parents: '("835a5e62b8deb3caa9ecf89748660aef458a6393")))
             (stale-obs
              (list (.o (cut := stale-cut)
                        identity: "ev-stale-change"
                        obligation: "sdlc.change-record"
                        outcome: 'passed)))
             (fenced-spec
              (.o (expected-commit := (.get test-cut commit))
                  (expected-operation := (.get test-cut operation))
                  (description := "AITIA-RFC-0008 feat(gitops): Wire dual-profile 5-state protocol")
                  (review-context := "sha256:verified-fence-token")
                  (proposal-binding := "sha256:proposal-binding")))
             ;; Round A: stale prior-cut evidence is flagged as decayed in epistemic-summary,
             ;; and fenced-spec without prepare receipt emits `gitops.jj.prepare-description`!
             (step-prep
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (observations := stale-obs)
                   (approval-live? := #t)
                   (reconcile? := #f))))
             (ep-prep (.get step-prep epistemic-summary))
             (frame-prep (car (.get step-prep frames)))
             ;; Round B: prepare receipt present -> emits `gitops.jj.apply-description` with fence-token!
             (step-apply
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (jj-prepare-description := (.o (workspace := "default")))))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #f))))
             (frame-apply (car (.get step-apply frames)))
             ;; Round C: apply receipt present + reconcile -> discharges gitops.commit-applied and reaches quiescent!
             (step-done
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (jj-prepare-description := (.o (workspace := "default")))
                                    (jj-apply-description := (.o (resulting-commit := "new-commit-123")))))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t)))))
        (check-equal? (.get ep-prep evidence-decay-detected?) #t)
        (check-equal? (.get ep-prep decayed-obligations) '("sdlc.change-record"))
        (check-equal? (.get ep-prep stale-evidence-ids) '("ev-stale-change"))
        (check-equal? (.get step-prep state) 'need-fenced-frames)
        (check-equal? (.get frame-prep capability) "gitops.jj.prepare-description")
        (check-equal? (.get frame-prep effect-class) 'fenced-effect)
        (check-equal? (.get frame-prep fence-token) "sha256:verified-fence-token")
        (check-equal? (.get step-apply state) 'need-fenced-frames)
        (check-equal? (.get frame-apply capability) "gitops.jj.apply-description")
        (check-equal? (.get frame-apply effect-class) 'fenced-effect)
        (check-equal? (.get frame-apply fence-token) "sha256:verified-fence-token")
        (check-equal? (.get step-done state) 'quiescent)
        (check-equal? (.get step-done handoff-target) 'none)
        (check-equal? (.get step-done action-authorized?) #f)))

    (test-case "4. Slice A: Localized Schwarz repair preserves supported CAS evidence and escalates on rejected/exhausted rounds"
      (let* ((stale-cut
              (.o project: "tao3k/lambda-aitia"
                  workspace: "default"
                  change: "sywptlmp"
                  operation: "op-old"
                  commit: "old-commit-000"
                  tree: "tree-old"
                  parents: '("835a5e62b8deb3caa9ecf89748660aef458a6393")))
             (mixed-obs
              (list (.o (cut := stale-cut)
                        identity: "ev-stale-change"
                        obligation: "sdlc.change-record"
                        outcome: 'passed)
                    (.o (cut := test-cut)
                        identity: "ev-live-config"
                        obligation: "sdlc.config-audit"
                        outcome: 'passed)))
             ;; Round 1: decayed evidence triggers localized-decay repair task preserving live sdlc.config-audit
             (s-repair
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '(".github/workflows/ci.yml"))
                   (proposals := '())
                   (observations := mixed-obs)
                   (repair-round := 1)
                   (max-repair-rounds := 3)
                   (reconcile? := #t))))
             (rtask (car (.get s-repair repair-tasks)))
             ;; Exhausted repair budget escalates deterministically to human decision
             (s-exhausted
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '(".github/workflows/ci.yml"))
                   (proposals := '())
                   (observations := mixed-obs)
                   (repair-round := 3)
                   (max-repair-rounds := 3)
                   (reconcile? := #t))))
             ;; Rejected raw tool call escalates deterministically to human decision
             (s-rejected
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '(".github/workflows/ci.yml"))
                   (proposals := '())
                   (proposal := ((.get wf raw-tool-call) 'shell-exec '("rm -rf")))
                   (reconcile? := #t)))))
        (check-equal? (.get s-repair state) 'need-agent-synthesis)
        (check-equal? (.get rtask repair-round) 1)
        (check-equal? (.get rtask recompute-scope) 'localized-decay)
        (check-equal? (.get rtask decayed-obligations) '("sdlc.change-record"))
        (check-equal? (.get rtask preserved-supported-obligations) '("sdlc.config-audit"))
        (check-equal? (.get s-exhausted state) 'need-human-decision)
        (check-equal? (.get s-exhausted gap-kind) 'requirement-gap)
        (check-equal? (.get s-exhausted escalation-reason) 'repair-budget-exhausted)
        (check-equal? (.get s-rejected state) 'need-human-decision)
        (check-equal? (.get s-rejected escalation-reason) 'repair-proposal-rejected)))

    (test-case "5. Slice B: GitOps PR observation + 3rd fenced stage push-reviewed + route-mismatch fail-closed"
      (let* ((fenced-spec
              (.o (expected-commit := (.get test-cut commit))
                  (expected-operation := (.get test-cut operation))
                  (description := "AITIA-RFC-0008 feat(gitops): Wire push-reviewed fenced stage")
                  (review-context := "sha256:verified-push-fence")
                  (proposal-binding := "sha256:proposal-binding")))
             (push-target (.o (remote := "origin") (bookmark := "reviewed")))
             ;; Missing github.observe-pr when push-target is requested -> need-host-frames requests observe-pr!
             (s-need-pr
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (push-target := push-target)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '()))))))
             ;; Apply receipt present + matching PR route -> emits gitops.jj.push-reviewed with fence-token!
             (apply-rcpt (hash ("resulting_commit" "applied-commit-999")
                               ("resulting_operation" "applied-op-999")
                               ("description" "AITIA-RFC-0008 feat(gitops): Wire push-reviewed fenced stage")))
             (matching-pr (hash ("pullRequest" (hash ("remote" "origin") ("source" "reviewed")))))
             (mismatch-pr (hash ("pullRequest" (hash ("remote" "origin") ("source" "other-branch")))))
             (s-push
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (push-target := push-target)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (github-observe-pr := matching-pr)
                                    (jj-prepare-description := (.o (workspace := "default")))
                                    (jj-apply-description := apply-rcpt)))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t))))
             (push-frame (car (.get s-push frames)))
             ;; Mismatched PR route -> fail-closed escalation to need-human-decision!
             (s-mismatch
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (push-target := push-target)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (github-observe-pr := mismatch-pr)
                                    (jj-prepare-description := (.o (workspace := "default")))
                                    (jj-apply-description := apply-rcpt)))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t))))
             ;; Push receipt present -> quiescent!
             (s-pushed
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := ".")
                   (fenced-commit-spec := fenced-spec)
                   (push-target := push-target)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (github-observe-pr := matching-pr)
                                    (jj-prepare-description := (.o (workspace := "default")))
                                    (jj-apply-description := apply-rcpt)
                                    (jj-push-reviewed := (hash ("remote" "origin") ("bookmark" "reviewed")))))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t)))))
        (check-equal? (.get s-need-pr state) 'need-host-frames)
        (check-equal? (.get (car (.get s-need-pr frames)) capability) "gitops.github.observe-pr")
        (check-equal? (.get s-push state) 'need-fenced-frames)
        (check-equal? (.get push-frame capability) "gitops.jj.push-reviewed")
        (check-equal? (.get push-frame effect-class) 'fenced-effect)
        (check-equal? (.get push-frame fence-token) "sha256:verified-push-fence")
        (check-equal? (.ref (.get push-frame payload) 'expected-commit) "applied-commit-999")
        (check-equal? (.ref (.get push-frame payload) 'expected-operation) "applied-op-999")
        (check-equal? (.get s-mismatch state) 'need-human-decision)
        (check-equal? (.get s-mismatch escalation-reason) 'push-route-mismatch)
        (check-equal? (.get s-mismatch frames) '())
        (check-equal? (.get s-pushed state) 'quiescent)
        (check-equal? (.get s-pushed action-authorized?) #f)))

    (test-case "6. Slice C: Multi-profile SDLC Core + OpenSecurity + NASA orthogonal composition and SdlcLifecycleWorkflowDomain protocol"
      (let* ((sdlc (.get lambda-aitia.init.exports modules sdlc))
             (core-std (.get sdlc core-standard))
             (sec-std (.get sdlc open-security-standard))
             (composed ((.get sdlc with-standards) (.get sdlc profile) (list core-std sec-std)))
             ;; Open-Security lifecycle missing security obligations -> need-agent-synthesis with Schwarz tasks
             (sec-open
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "lambda-aitia/sdlc/open-security")
                   (change-id := "change:sec-001")
                   (design-alternatives := '(design-zero-trust))
                   (verified? := #t)
                   (observed-obligations := '("sec.sbom-provenance"))
                   (reconcile? := #t))))
             ;; Competing design alternatives -> never collapses, enters need-human-decision
             (competing
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "lambda-aitia/sdlc")
                   (change-id := "change:core-002")
                   (design-alternatives := '(design-a design-b))
                   (verified? := #t)
                   (approval-live? := #t)
                   (reconcile? := #t))))
             ;; All open-security obligations + approval + published -> quiescent!
             (sec-done
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "lambda-aitia/sdlc/open-security")
                   (change-id := "change:sec-001")
                   (design-alternatives := '(design-zero-trust))
                   (verified? := #t)
                   (observed-obligations := '("sec.sbom-provenance"
                                              "sec.dependency-audit"
                                              "sec.threat-model-review"))
                   (approval-live? := #t)
                   (release-published? := #t)
                   (reconcile? := #t))))
             ;; NASA NPR 7150.2D lifecycle enforces SWE-052 / SWE-065 / SWE-084 dynamically
             (nasa-open
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "nasa/sdlc/npr-7150.2")
                   (change-id := "change:nasa-003")
                   (design-alternatives := '(design-flight-sw))
                   (verified? := #t)
                   (observed-obligations := '())
                   (reconcile? := #t)))))
        (check-equal? (.get core-std identity) "lambda-aitia/sdlc")
        (check-equal? (.get sec-std identity) "lambda-aitia/sdlc/open-security")
        (check-equal? (length (.get composed standards)) 2)
        (check-equal? (.get sec-open state) 'need-agent-synthesis)
        (check-equal? (length (.get sec-open repair-tasks)) 2)
        (check-equal? (.get competing state) 'need-human-decision)
        (check-equal? (.get (.get competing epistemic-summary) world-count) 2)
        (check-equal? (.get sec-done state) 'quiescent)
        (check-equal? (.get sec-done profile) "lambda-aitia/sdlc/open-security")
        (check-equal? (.get sec-done action-authorized?) #f)
        (check-equal? (.get nasa-open state) 'need-agent-synthesis)
        (check-equal? (length (.get nasa-open repair-tasks)) 3)))

    (test-case "7. Multi-Repo GitOps: topological waves, cycle rejection, cross-repo pin-drift decay, and staged convergence"
      (let* ((core-cut
              (.o project: "tao3k/core"
                  workspace: "default"
                  change: "core1111"
                  operation: "op-core-1"
                  commit: "core-sha-new-222"
                  tree: "tree-core"
                  parents: '("core-sha-old-111")))
             (app-cut
              (.o project: "tao3k/app"
                  workspace: "default"
                  change: "app2222"
                  operation: "op-app-1"
                  commit: "app-sha-111"
                  tree: "tree-app"
                  parents: '("app-sha-000")))
             (core-sources
              (list (.o path: "README.org" text: "* Core\nEnglish project readme.\n" cut: core-cut)
                    (.o path: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
                        text: "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"
                        cut: core-cut)))
             (app-sources
              (list (.o path: "README.org" text: "* App\nEnglish project readme.\n" cut: app-cut)
                    (.o path: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
                        text: "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"
                        cut: app-cut)))
             ;; A. Dependency cycle fails closed to need-human-decision (dependency-cycle)
             (s-cycle
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "a") (depends-on := '("b")))
                                   (.o (repo-id := "b") (depends-on := '("a"))))))))
             ;; B. Unknown upstream dependency fails closed
             (s-unknown
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "app") (depends-on := '("missing-upstream"))))))))
             ;; C. Missing HostRead receipts fan out across ALL repos with repo-qualified receiptKeys
             (s-probe
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "core") (directory := "/tmp/core") (depends-on := '()))
                                   (.o (repo-id := "app") (directory := "/tmp/app") (depends-on := '("core"))))))))
             ;; D. Cross-repo pin drift: app pins core-sha-old-111 while core is at core-sha-new-222 -> localized repairTask!
             (s-drift
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "core")
                                       (directory := "/tmp/core")
                                       (depends-on := '())
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())))
                                       (naming := test-naming) (cut := core-cut) (sources := core-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #t))
                                   (.o (repo-id := "app")
                                       (directory := "/tmp/app")
                                       (depends-on := '("core"))
                                       (pinned-upstream-commits := '(("core" . "core-sha-old-111")))
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())))
                                       (naming := test-naming) (cut := app-cut) (sources := app-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #t)))))))
             ;; E. Aligned pins, Wave 0 (core) ready for fenced apply while Wave 1 (app) stays blocked-on-upstream!
             (s-wave0
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "core")
                                       (directory := "/tmp/core")
                                       (depends-on := '())
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())))
                                       (naming := test-naming) (cut := core-cut) (sources := core-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #f))
                                   (.o (repo-id := "app")
                                       (directory := "/tmp/app")
                                       (depends-on := '("core"))
                                       (pinned-upstream-commits := '(("core" . "core-sha-new-222")))
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())))
                                       (naming := test-naming) (cut := app-cut) (sources := app-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #f)))))))
             ;; F. Both Wave 0 and Wave 1 quiescent -> global quiescent!
             (s-done
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "core")
                                       (directory := "/tmp/core")
                                       (depends-on := '())
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())
                                                        (jj-apply-description := (hash ("resulting_commit" "core-sha-new-222")))))
                                       (naming := test-naming) (cut := core-cut) (sources := core-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #t))
                                   (.o (repo-id := "app")
                                       (directory := "/tmp/app")
                                       (depends-on := '("core"))
                                       (pinned-upstream-commits := '(("core" . "core-sha-new-222")))
                                       (receipts := (.o (jj-observe-cut := #t) (sysml-project-scopes := '())
                                                        (jj-apply-description := (hash ("resulting_commit" "app-sha-222")))))
                                       (naming := test-naming) (cut := app-cut) (sources := app-sources)
                                       (paths := '("justfile")) (proposals := (list valid-proposal))
                                       (approval-live? := #t) (reconcile? := #t))))))))
        (check-equal? (.get s-cycle state) 'need-human-decision)
        (check-equal? (.get s-cycle escalation-reason) 'dependency-cycle)
        (check-equal? (.get s-unknown state) 'need-human-decision)
        (check-equal? (.get s-unknown escalation-reason) 'unknown-repo-dependency)
        (check-equal? (.get s-probe state) 'need-host-frames)
        (check-equal? (.ref s-probe 'waves) '(("core") ("app")))
        (check-equal? (length (.get s-probe frames)) 4)
        (check-equal? (.get s-drift state) 'need-agent-synthesis)
        (check-equal? (.get s-drift escalation-reason) 'cross-repo-pin-drift)
        (check-equal? (length (.get s-drift repair-tasks)) 1)
        (check-equal? (.get (car (.get s-drift repair-tasks)) recompute-scope) 'cross-repo-pin-drift)
        (check-equal? (.get (car (.get s-drift repair-tasks)) preserved-supported-obligations) '("core"))
        (check-equal? (.get s-wave0 state) 'need-fenced-frames)
        ;; Only Wave 0 ("core") emits a fenced frame; Wave 1 ("app") MUST remain blocked on upstream!
        (check-equal? (length (.get s-wave0 frames)) 1)
        (check-equal? (.ref (car (.get s-wave0 frames)) 'repo-id) "core")
        (check-equal? (.get s-done state) 'quiescent)
        (check-equal? (.get s-done action-authorized?) #f)))))
