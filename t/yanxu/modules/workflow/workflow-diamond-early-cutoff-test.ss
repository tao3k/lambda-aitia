;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; RFC 0009: IOHK (Cardano) + Bazel Skyframe / Bzlmod 4-repo diamond invariants:
;;;   1. Two-level bitemporal Early Cutoff (Change Pruning) when interface-digest is unchanged.
;;;   2. io-sim-inspired Church-Rosser schedule confluence under peer repo permutation.
;;;   3. Breaking interface-digest drift -> localized Schwarz `cross-repo-pin-drift` repair.
;;;   4. Bzlmod / CHaP Transitive Diamond Pin Conflict -> fail-closed `need-human-decision`.

(import :std/test
        (only-in :clan/poo/object .o .get .ref)
        (only-in :lambda-aitia/init lambda-aitia.init.exports))

(export aitia-workflow-diamond-early-cutoff-test)

(def wf (.get lambda-aitia.init.exports modules workflow))

(def diamond-naming
  (.o project-key: "AITIA"
      types: '("build" "chore" "ci" "docs" "feat" "fix" "refactor" "test")
      primary-language: "en"
      language-sources: '("README.org")
      scopes: (list (.o name: "gitops" paths: '("justfile" "modules/gitops" ".agents/aita")))
      references: (list (.o identity: "RFC-0008"
                            source: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
                            element: "ascent-obligation-funflow"))))

(def diamond-valid-proposal
  (.o identity: "AITIA-RFC-0008"
      reference: "RFC-0008"
      language: "en"
      language-source: "README.org"
      type: "feat"
      scope: "gitops"
      summary: "Verify diamond early cutoff"
      rationale: "Preserve CAS support on interface-preserving upstream commits and fail closed on diamond pin conflicts."))

(def aitia-workflow-diamond-early-cutoff-test
  (test-suite "RFC 0009 IOHK/Bazel 4-repo diamond Early Cutoff, Diamond Conflict, and Schedule Confluence"

    (test-case "1. Bazel Skyframe Early Cutoff, io-sim Schedule Confluence, Breaking Interface Drift, and Bzlmod/CHaP Diamond Conflict"
      (let* ((mk-cut (lambda (proj sha)
                       (.o project: proj workspace: "default" change: sha
                           operation: (string-append "op-" sha) commit: sha
                           tree: (string-append "tree-" sha) parents: '("base-0"))))
             (mk-src (lambda (src-cut)
                       (list (.o path: "README.org" text: "* Repo\nEnglish readme.\n" cut: src-cut)
                             (.o path: "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
                                 text: "* RFC 0008\n:PROPERTIES:\n:ID: ascent-obligation-funflow\n:ENGINEERING_ID: RFC-0008\n:END:\n"
                                 cut: src-cut))))
             (base-cut (mk-cut "iohk/protocol-base" "base-sha-v2"))
             (ledger-cut (mk-cut "iohk/ledger-core" "ledger-sha-v1"))
             (net-cut (mk-cut "iohk/network-mux" "net-sha-v1"))
             (node-cut (mk-cut "iohk/node-runner" "node-sha-v1"))
             (mk-repo (lambda (rid deps repo-cut iface pins iface-pins)
                        (.o (repo-id := rid)
                            (directory := (string-append "/tmp/" rid))
                            (depends-on := deps)
                            (interface-digest := iface)
                            (pinned-upstream-commits := pins)
                            (pinned-upstream-interfaces := iface-pins)
                            (receipts := (.o (jj-observe-cut := #t)
                                             (sysml-project-scopes := '())
                                             (jj-apply-description := (hash ("resulting_commit" (.get repo-cut commit))))))
                            (naming := diamond-naming)
                            (cut := repo-cut)
                            (sources := (mk-src repo-cut))
                            (paths := '("justfile"))
                            (proposals := (list diamond-valid-proposal))
                            (approval-live? := #t)
                            (reconcile? := #t))))
             ;; A. Bazel Skyframe Early Cutoff: protocol-base moved base-sha-v1 -> base-sha-v2,
             ;;    but interface-digest stayed "abi:v1" -> ledger & network hit early-cutoff and stay quiescent!
             (repos-cutoff
              (list (mk-repo "protocol-base" '() base-cut "abi:v1" '() '())
                    (mk-repo "ledger-core" '("protocol-base") ledger-cut "abi:ledger-v1"
                             '(("protocol-base" . "base-sha-v1")) '(("protocol-base" . "abi:v1")))
                    (mk-repo "network-mux" '("protocol-base") net-cut "abi:net-v1"
                             '(("protocol-base" . "base-sha-v1")) '(("protocol-base" . "abi:v1")))
                    (mk-repo "node-runner" '("ledger-core" "network-mux") node-cut "abi:node-v1"
                             '() '())))
             (s-cutoff ((.get wf plan-protocol-step)
                        (.o (case-id := 'aitia/case/multi-repo-gitops) (repos := repos-cutoff))))
             ;; B. io-sim Schedule Confluence: reversed input repo order yields identical waves & cutoffs!
             (s-cutoff-rev ((.get wf plan-protocol-step)
                            (.o (case-id := 'aitia/case/multi-repo-gitops) (repos := (reverse repos-cutoff)))))
             ;; C. Breaking interface change ("abi:v2") invalidates downstream with localized Schwarz repair
             (s-iface-break
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos :=
                    (list (mk-repo "protocol-base" '() base-cut "abi:v2" '() '())
                          (mk-repo "ledger-core" '("protocol-base") ledger-cut "abi:ledger-v1"
                                   '(("protocol-base" . "base-sha-v1")) '(("protocol-base" . "abi:v1")))
                          (mk-repo "network-mux" '("protocol-base") net-cut "abi:net-v1"
                                   '(("protocol-base" . "base-sha-v1")) '(("protocol-base" . "abi:v1")))
                          (mk-repo "node-runner" '("ledger-core" "network-mux") node-cut "abi:node-v1"
                                   '() '()))))))
             ;; D. Bazel Bzlmod / IOHK CHaP Diamond Conflict: ledger pins abi:v2 while network pins abi:v1!
             (s-diamond-conflict
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos :=
                    (list (mk-repo "protocol-base" '() base-cut "abi:v2" '() '())
                          (mk-repo "ledger-core" '("protocol-base") ledger-cut "abi:ledger-v1"
                                   '() '(("protocol-base" . "abi:v2")))
                          (mk-repo "network-mux" '("protocol-base") net-cut "abi:net-v1"
                                   '() '(("protocol-base" . "abi:v1")))
                          (mk-repo "node-runner" '("ledger-core" "network-mux") node-cut "abi:node-v1"
                                   '() '())))))))
        (check-equal? (.get s-cutoff state) 'quiescent)
        (check-equal? (.ref s-cutoff 'waves) '(("protocol-base") ("ledger-core" "network-mux") ("node-runner")))
        (check-equal? (length (.ref s-cutoff 'early-cutoffs)) 2)
        (check-equal? (.ref s-cutoff 'pin-drifts) '())
        ;; Church-Rosser confluence under input permutation:
        (check-equal? (.ref s-cutoff-rev 'waves) (.ref s-cutoff 'waves))
        (check-equal? (.get s-cutoff-rev state) (.get s-cutoff state))
        (check-equal? (length (.ref s-cutoff-rev 'early-cutoffs)) (length (.ref s-cutoff 'early-cutoffs)))
        ;; True ABI break triggers cross-repo-pin-drift:
        (check-equal? (.get s-iface-break state) 'need-agent-synthesis)
        (check-equal? (.get s-iface-break escalation-reason) 'cross-repo-pin-drift)
        (check-equal? (length (.get s-iface-break repair-tasks)) 2)
        ;; Diamond conflict fails closed to need-human-decision with competing peer provenance:
        (check-equal? (.get s-diamond-conflict state) 'need-human-decision)
        (check-equal? (.get s-diamond-conflict escalation-reason) 'diamond-pin-conflict)
        (check-equal? (length (.ref s-diamond-conflict 'diamond-conflicts)) 1)
        (check-equal? (.ref (car (.ref s-diamond-conflict 'diamond-conflicts)) 'consumer-repo) "node-runner")
        (check-equal? (.ref (car (.ref s-diamond-conflict 'diamond-conflicts)) 'upstream-repo) "protocol-base")
        (check-equal? (.get s-diamond-conflict action-authorized?) #f)))

    (test-case "2. Content-addressed interface.project-digest HostRead probe emission and receipt consumption"
      (let* ((s-probe
              ((.get wf plan-protocol-step)
               (.o (case-id := 'aitia/case/multi-repo-gitops)
                   (repos :=
                    (list (.o (repo-id := "protocol-base")
                              (directory := "/tmp/protocol-base")
                              (depends-on := '())
                              (interface-paths := '("include/protocol.h"))))))))
             (caps (map (lambda (f) (.get f capability)) (.get s-probe frames))))
        (check-equal? (.get s-probe state) 'need-host-frames)
        (check (and (member "interface.project-digest" caps) #t) => #t)
        (check-equal? (.get s-probe action-authorized?) #f)))))
