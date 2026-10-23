;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :agentic-ai-lab/modules/governance/objects
                 AgenticAILabGovernanceProfile.)
        (only-in :yuanxu/poo-clos/model poo-clos-check-model poo-clos-model-prototype)
        :agentic-ai-lab/lambda-aitia/modules/sdlc/types)
(export StandardProfile. SdlcProfile)
(def StandardProfile.
  (.o (:: @ (poo-clos-model-prototype SdlcStandard)) kind: 'lambda-aitia.sdlc-standard coverage: 'partial
      requirements: '() assessment: 'not-evaluated))
(def sdlc-ontology
  (.o entities: '(LifecycleActivity Requirement Artifact Verification Evidence
                 Review Decision Baseline Standard TailoringRequest Approval)
      relations: '(REFINES IMPLEMENTS VERIFIES EVIDENCES REVIEWS BASELINED_IN
                   DERIVED_FROM REQUESTS_RELIEF APPROVED_BY)))
(def SdlcProfile
  (.o (:: @ AgenticAILabGovernanceProfile.) identity: "lambda-aitia/sdlc"
      revision: "1" owner: "lambda-aitia"
      ontology: sdlc-ontology standards: '()
      activities: '(planning requirements architecture design implementation
                    verification release operations maintenance retirement)
      policies:
      (.o lifecycle: (.o ordering: 'project-defined iteration: 'allowed)
          traceability: (.o direction: 'bidirectional incomplete-scope: 'unknown)
          evidence: (.o binding: '(subject revision producer scope)
                        changed-baseline: 'review-required)
          tailoring: (.o default: 'unapproved approval: 'explicit-authority
                         prototype-override-is-approval?: #f)
          assessment: 'not-evaluated)))

(export sdlc-trace-node sdlc-trace-edge sdlc-trace-rule)
(def (sdlc-trace-rule id source-kind target-kind)
  (let ((value (.o (:: @ (poo-clos-model-prototype SdlcTraceRule)) identity: id source-category: source-kind target-category: target-kind)))
    (unless (sdlc-trace-rule? value) (error "invalid trace rule")) value))
(def (sdlc-trace-node id category-value project)
  (unless (sdlc-bound-fact? project) (error "invalid trace project"))
  (let ((value (.o (:: @ (poo-clos-model-prototype SdlcTraceNode)) kind: 'sdlc.trace-node identity: id category: category-value
                   subject: (.ref project 'subject) revision: (.ref project 'revision)
                   scope: (.ref project 'scope))))
    (unless (sdlc-trace-node? value) (error "invalid trace node")) value))
(def (sdlc-trace-edge id relation-value source-value target-value project)
  (unless (sdlc-bound-fact? project) (error "invalid trace project"))
  (let ((value (.o (:: @ (poo-clos-model-prototype SdlcTraceEdge)) kind: 'sdlc.trace-edge identity: id relation: relation-value
                   source: source-value target: target-value
                   subject: (.ref project 'subject) revision: (.ref project 'revision)
                   scope: (.ref project 'scope))))
    (unless (sdlc-trace-edge? value) (error "invalid trace edge")) value))

(export sdlc-project sdlc-obligation sdlc-evidence sdlc-tailoring-request)
(def (sdlc-project subject-value revision-value scope-value complete-value)
  (poo-clos-check-model SdlcProject
    (.o (:: @ (poo-clos-model-prototype SdlcProject)) kind: 'sdlc.project subject: subject-value revision: revision-value
      scope: scope-value complete?: complete-value)))
(def (sdlc-obligation standard-value requirement-value applicability-value)
  (poo-clos-check-model SdlcObligation
    (.o (:: @ (poo-clos-model-prototype SdlcObligation)) kind: 'sdlc.obligation standard: standard-value requirement: requirement-value
      applicability: applicability-value)))
(def (sdlc-evidence identity-value subject-value revision-value scope-value
                    standard-value requirement-value producer-value outcome-value)
  (poo-clos-check-model SdlcEvidence
    (.o (:: @ (poo-clos-model-prototype SdlcEvidence)) kind: 'sdlc.evidence identity: identity-value subject: subject-value
      revision: revision-value scope: scope-value standard: standard-value
      requirement: requirement-value producer: producer-value outcome: outcome-value)))
(def (sdlc-tailoring-request subject-value revision-value standard-value
                            requirement-value rationale-value)
  (poo-clos-check-model SdlcTailoringRequest
    (.o (:: @ (poo-clos-model-prototype SdlcTailoringRequest)) kind: 'sdlc.tailoring-request subject: subject-value revision: revision-value
      standard: standard-value requirement: requirement-value rationale: rationale-value)))
