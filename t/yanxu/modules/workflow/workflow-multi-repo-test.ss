;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Multi-profile SDLC lifecycle, Multi-Repo GitOps topological wave orchestration,
;;; and leaf Python frozen-pytest HostRead capability qualification.

(import :std/test
        (only-in :clan/poo/object .o .get .ref)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))

(export aitia-workflow-multi-repo-test)

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

(def aitia-workflow-multi-repo-test
  (test-suite "Lambda Aitia multi-profile SDLC, multi-repo GitOps waves, and leaf Python checks"

    (test-case "1. Slice C: Multi-profile SDLC Core + OpenSecurity + NASA orthogonal composition and SdlcLifecycleWorkflowDomain protocol"
      (let* ((sdlc (.get lambda-aitia.init.exports modules sdlc))
             (core-std (.get sdlc core-standard))
             (sec-std (.get sdlc open-security-standard))
             (composed ((.get sdlc with-standards) (.get sdlc profile) (list core-std sec-std)))
             (sec-open
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "lambda-aitia/sdlc/open-security")
                   (change-id := "change:sec-001")
                   (design-alternatives := '(design-zero-trust))
                   (verified? := #t)
                   (observed-obligations := '("sec.sbom-provenance"))
                   (reconcile? := #t))))
             (competing
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/sdlc-lifecycle)
                   (profile := "lambda-aitia/sdlc")
                   (change-id := "change:core-002")
                   (design-alternatives := '(design-a design-b))
                   (verified? := #t)
                   (approval-live? := #t)
                   (reconcile? := #t))))
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

    (test-case "2. Multi-Repo GitOps: topological waves, cycle rejection, cross-repo pin-drift decay, and staged convergence"
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
             (s-cycle
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "a") (depends-on := '("b")))
                                   (.o (repo-id := "b") (depends-on := '("a"))))))))
             (s-unknown
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "app") (depends-on := '("missing-upstream"))))))))
             (s-probe
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos := (list (.o (repo-id := "core") (directory := "/tmp/core") (depends-on := '()))
                                   (.o (repo-id := "app") (directory := "/tmp/app") (depends-on := '("core"))))))))
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
        (check-equal? (length (.get s-wave0 frames)) 1)
        (check-equal? (.ref (car (.get s-wave0 frames)) 'repo-id) "core")
        (check-equal? (.get s-done state) 'quiescent)
        (check-equal? (.get s-done action-authorized?) #f)))

    (test-case "3. Leaf Python frozen-pytest HostRead frame emission, pass evidence, and fail-closed repair"
      (let* ((py-spec (.o (interpreter := "/usr/bin/python3")
                          (selectors := '("tests/test_app.py"))
                          (paths := '("src/app.py" "tests/test_app.py"))))
             (s-missing
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := "/tmp/py-repo")
                   (python-check := py-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '()))))))
             (s-failed
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := "/tmp/py-repo")
                   (python-check := py-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (python-observe-pytest := (hash ("verdict" "process-failed")
                                                                    ("sourceUnchanged" #t)
                                                                    ("sourceSha256" "sha256:abc")))))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t))))
             (s-passed
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/gitops-commit)
                   (profile := "lambda-aitia/sdlc")
                   (directory := "/tmp/py-repo")
                   (python-check := py-spec)
                   (receipts := (.o (jj-observe-cut := #t)
                                    (sysml-project-scopes := '())
                                    (python-observe-pytest := (hash ("verdict" "passed")
                                                                    ("sourceUnchanged" #t)
                                                                    ("sourceSha256" "sha256:abc")))
                                    (jj-apply-description := (hash ("resulting_commit" "new-sha")))))
                   (naming := test-naming)
                   (cut := test-cut)
                   (sources := test-sources)
                   (paths := '("justfile"))
                   (proposals := (list valid-proposal))
                   (approval-live? := #t)
                   (reconcile? := #t)))))
        (check-equal? (.get s-missing state) 'need-host-frames)
        (check-equal? (length (.get s-missing frames)) 1)
        (check-equal? (.get (car (.get s-missing frames)) capability) "python.observe-pytest")
        (check-equal? (.get (car (.get s-missing frames)) effect-class) 'host-read)
        (check-equal? (.get s-failed state) 'need-agent-synthesis)
        (check-equal? (.get s-failed escalation-reason) 'python-check-failed)
        (check-equal? (.get (car (.get s-failed repair-tasks)) recompute-scope) 'leaf-python-check)
        (check-equal? (.get s-failed action-authorized?) #f)
        (check-equal? (.get s-passed state) 'quiescent)
        (check-equal? (.get s-passed action-authorized?) #f)))))
