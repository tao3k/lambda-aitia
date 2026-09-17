;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o)
        :poo-flow/src/module-system/contribution/model
        (only-in :poo-flow/src/modules/governance/objects
                 PooFlowGovernanceProfile.
                 poo-flow-governance-source)
        :poo-flow/lambda-aitia/modules/ADR/types)

(export ADRProfile ADR-link ADR-option ADR-consequence ADR-record)

(def ADRProfile
  (.o (:: @ PooFlowGovernanceProfile.) identity: "lambda-aitia/ADR"
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
      (list (poo-flow-governance-source
             "ADR/expired-reference-witnesses"
             "modules/ADR/expired-references.gql" 'gql))))

(def (ADR-link relation-value target-value)
  (poo-flow-check-model
   ADRLink
   (.o (:: @ (poo-flow-model-prototype ADRLink))
       relation: relation-value target: target-value)))

(def (ADR-option identity-value title-value description-value
                 disposition-value pros-value cons-value)
  (poo-flow-check-model
   ADROption
   (.o (:: @ (poo-flow-model-prototype ADROption))
       identity: identity-value title: title-value
       description: description-value disposition: disposition-value
       pros: pros-value cons: cons-value)))

(def (ADR-consequence sentiment-value statement-value)
  (poo-flow-check-model
   ADRConsequence
   (.o (:: @ (poo-flow-model-prototype ADRConsequence))
       sentiment: sentiment-value statement: statement-value)))

(def (ADR-record identity-value title-value status-value date-value
                 revision-value context-value decision-value
                 drivers-value options-value consequences-value
                 confirmation-value decision-makers-value consulted-value
                 informed-value links-value)
  (let ((record
         (poo-flow-check-model
          ADRRecord
          (.o (:: @ (poo-flow-model-prototype ADRRecord))
              identity: identity-value title: title-value status: status-value
              date: date-value revision: revision-value context: context-value
              decision: decision-value decision-drivers: drivers-value
              considered-options: options-value consequences: consequences-value
              confirmation: confirmation-value
              decision-makers: decision-makers-value consulted: consulted-value
              informed: informed-value links: links-value))))
    (unless (ADR-record-valid? record)
      (error "invalid ADR decision record" identity-value status-value))
    record))
