;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: POO prototypes for Lambda Aitia workflow domains (RFC 0008).
;;; DE and user projects specialize domains via standard POO prototype
;;; composition (`:: @`), never a separate custom workflow DSL.

(import (only-in :clan/poo/object .def .o))

(export AitiaWorkflowDomain.
        GitOpsCommitWorkflowDomain.
        GitOpsNasaCommitWorkflowDomain.
        SdlcLifecycleWorkflowDomain.
        ChoiceFlowPlan.)

(.def AitiaWorkflowDomain.
  aitia-workflow-domain?: #t
  schema: "lambda-aitia.workflow-domain.v1"
  domain-id: 'aitia/workflow-base
  default-max-branches: 4
  deterministic-first?: #t
  raw-tool-calls-allowed?: #f
  action-authorized?: #f)

;;; Standard-free SDLC Core GitOps workflow domain (zero NASA hard-coding).
(.def (GitOpsCommitWorkflowDomain. @ AitiaWorkflowDomain.)
  domain-id: 'aitia/gitops-commit
  profile-id: "lambda-aitia/sdlc"
  default-checks: '(("sdlc.change-record" "jj.recorded-change")
                    ("sdlc.config-audit" "jj.configuration-audit"))
  obligation-ids: '("sdlc.change-record"
                    "sdlc.config-audit"
                    "gitops.commit-semantics"
                    "gitops.commit-review-approved"
                    "gitops.commit-applied")
  synthesis-hole-id: "hole:gitops-commit-narration-or-scope"
  human-gate-obligation: "gitops.commit-review-approved"
  fenced-effect-obligation: "gitops.commit-applied")

;;; NASA NPR 7150.2D Profile specialization via pure POO prototype inheritance.
(.def (GitOpsNasaCommitWorkflowDomain. @ GitOpsCommitWorkflowDomain.)
  domain-id: 'aitia/gitops-commit-nasa
  profile-id: "nasa/sdlc/npr-7150.2"
  default-checks: '(("SWE-083" "jj.recorded-change")
                    ("SWE-084" "jj.configuration-audit"))
  obligation-ids: '("SWE-083"
                    "SWE-084"
                    "gitops.commit-semantics"
                    "gitops.commit-review-approved"
                    "gitops.commit-applied"))

(.def (SdlcLifecycleWorkflowDomain. @ AitiaWorkflowDomain.)
  domain-id: 'aitia/sdlc-lifecycle
  obligation-ids: '("sdlc.requirements-traced"
                    "sdlc.design-alternatives-assessed"
                    "sdlc.verification-observed"
                    "sdlc.retirement-impact-audited"
                    "sdlc.release-approved")
  synthesis-hole-id: "hole:sdlc-competing-design-or-retirement"
  human-gate-obligation: "sdlc.release-approved"
  fenced-effect-obligation: "sdlc.release-published")

;;; Declarative POO prototype for Finite-Choice -> Typed FunFlow routing
;;; (the Coproduct/ArrowChoice dual of FunFlow's Product `flow-fanout`).
;;; DE extends branches via standard POO prototype composition (`:: @`),
;;; never an opaque routing callback or custom workflow DSL.
(.def ChoiceFlowPlan.
  kind: 'lambda-aitia.workflow.choice-flow-plan.v1
  choice-key: 'scope-decision
  shared-prefix: '()
  branches: (.o)
  fenced-tail: '()
  action-authorized?: #f)
