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
        (check-equal? (.get s5 action-authorized?) #f)))))
