;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        (only-in :agentic-ai-lab/modules/governance/objects
                 AgenticAILabGovernanceProfile.
                 agentic-ai-lab-governance-source)
        "types.ss")

(export ADRProfile)

(def ADRProfile
  (.o (:: @ AgenticAILabGovernanceProfile.) identity: "lambda-aitia/ADR"
      revision: "1" owner: "lambda-aitia"
      module-family: 'ADR
      ontology: (.o decision-label: 'Decision reference-edge: 'REFERENCES
                    supersession-edge: 'SUPERSEDED_BY identity-property: 'id)
      policies: (.o lifecycle:
                    (.o allowed: +ADR-statuses+
                        missing-replacement: 'requires-complete-scope
                        incomplete-scope: 'unknown
                        expired-reference: 'review-required
                        repair: 'proposal-only)
                    authority: (.o accepted-is-authority?: #f
                                   effect-authorization: 'separate-receipt))
      source-assets:
      (list (agentic-ai-lab-governance-source
             "ADR/expired-reference-witnesses"
             "modules/ADR/expired-references.gql" 'gql))))
