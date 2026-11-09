;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "types.ss" "objects.ss" "func.ss"
        "evidence-admission.ss" "host.ss" "input-correspondence.ss"
        "replay-assessment.ss" "context-delivery.ss")
(export Config)

;;; Obtaining this POO scope creates no verifier, Host, grant or reservation.
(def Config
  (.o policy: AssurancePolicy verification-policy: assurance-verification-policy
      agent-input-corresponds?: assurance-agent-input-corresponds?
      prepare-context-input: assurance-prepare-context-input
      prepare-context-body: assurance-prepare-context-body
      assess-agent-input-delivery: assurance-assess-agent-input-delivery
      replay-cases: assurance-replay-cases
      replay-observation-matches?: assurance-replay-observation-matches?
      assess-replay-deployment: assurance-assess-replay-deployment
      assess-pytest-replay: assurance-assess-pytest-replay
      evidence-kinds: +assurance-evidence-kinds+
      contracts: (.o required-support-row: AssessmentRequiredSupport)
      required-support-row?: assessment-required-support?
      artifact: assurance-artifact claim: assurance-claim assumption: assurance-assumption
      observation: assurance-observation event: assurance-event action: assurance-action
      obligation: assurance-obligation evidence: assurance-evidence
      counterexample: assurance-counterexample finding: assurance-finding
      decision: assurance-decision effect: assurance-effect relation: assurance-relation
      verifier-candidate: assurance-verifier-candidate
      decision?: assurance-decision? snapshot-canonical?: assurance-snapshot-canonical?
      artifact?: assurance-artifact? claim?: assurance-claim? obligation?: assurance-obligation?
      digest?: assurance-digest? snapshot?: assurance-snapshot?
      verification-subject?: assurance-verification-subject?
      relation?: assurance-relation? composition-derivation?: assurance-composition-derivation?
      decision-preflight?: assurance-decision-preflight?
      evidence-admission-receipt?: assurance-evidence-admission-receipt?
      invalidation-receipt?: assurance-invalidation-receipt?
      invalidation-receipt-ref: assurance-invalidation-receipt-ref
      replacement-declaration-receipt?: assurance-replacement-declaration-receipt?
      replacement-derivation?: assurance-replacement-derivation?
      replacement-requirement?: assurance-replacement-requirement?
      required-support?: assurance-required-support?
      verification-plan?: assurance-verification-plan?
      verification-policy?: assurance-verification-policy?
      verification-request?: assurance-verification-request?
      verifier-choice-receipt?: assurance-verifier-choice-receipt?
      digest: assurance-canonical-digest node-canonical: assurance-node-canonical
      relation-canonical: assurance-relation-canonical snapshot: assurance-snapshot
      bind-obligation: assurance-bind-obligation-to-snapshot
      invalidation-graph: assurance-invalidation-graph invalidate: assurance-invalidate
      derive-replacements: assurance-derive-replacement-requirements
      declare-replacement: assurance-declare-replacement-obligation
      derive-composition: assurance-derive-composition-requirements
      plan-verification: assurance-plan-verification
      explain-verifiers: assurance-explain-verifier-choices
      verifier-input: assurance-verifier-input verifier-outcome: assurance-verifier-outcome
      verifier-outcome-digest: assurance-verifier-outcome-digest
      evaluate-admission: assurance-evaluate-evidence-admission
      verification-subject: assurance-verification-subject
      verification-subject-snapshot: assurance-verification-subject-snapshot
      support-sealed-under-adapter?: assurance-support-sealed-under-adapter?
      verification-host: assurance-verification-host host-verify: assurance-host-verify
      host-admit: assurance-host-admit host-admit-verified: assurance-host-admit-verified
      host-admission-current?: assurance-host-admission-current?
      host-admitted-support?: assurance-host-admitted-support?
      host-sealed-support?: assurance-host-sealed-support?
      host-source-current?: assurance-host-source-current?
      host-required-support: assurance-host-required-support
      host-preflight: assurance-host-preflight-decision
      host-preflight-current?: assurance-host-decision-preflight-current?
      host-revoke!: assurance-host-revoke! host-revoke-admission!: assurance-host-revoke-admission!
      host-revoke-preflight!: assurance-host-revoke-decision-preflight!))
