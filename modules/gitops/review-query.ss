;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .ref)
        (only-in :tao3k/yuanxu/graph/types yuanxu-graph-id yuanxu-graph-nodes yuanxu-graph-node-id)
        (only-in :agentic-ai-lab/modules/query/config AgenticAILabQueryModule.)
        (only-in :agentic-ai-lab/modules/query/objects
                 AgenticAILabQuery. AgenticAILabSchemeGqlQueryLanguage.
                 AgenticAILabGqlQueryProgram. GraphSyntaxNode. GraphSyntaxStep. GraphSyntaxPath.
                 GraphSyntaxEquals. GraphSyntaxLiteral. GraphSyntaxProperty. GraphSyntaxProjection.
                 agentic-ai-lab-query-element-space agentic-ai-lab-query-result-contract))
(export gitops-review-query)

(def (gitops-review-query graph revision-value)
  (let (identity-value (yuanxu-graph-id graph))
    (unless (eq? identity-value (string->symbol revision-value))
      (error "Review query revision differs from the evidence graph"))
    (let* ((ids (map yuanxu-graph-node-id (yuanxu-graph-nodes graph)))
           (space (agentic-ai-lab-query-element-space identity-value revision-value ids #f))
           (select (.ref AgenticAILabQueryModule. '.select-scheme-graph))
           (project (.ref AgenticAILabQueryModule. '.project-gql)))
      (def (execute name path projections)
        (let* ((query (revision-query identity-value revision-value ids name path projections))
               (result (select query space graph)))
          (.o status: 'executed gql: (project query)
              revision: (.ref result 'semantic-revision)
              complete?: (.ref result 'complete?)
              action-authority?: (.ref result 'action-authority?)
              columns: (map cadr projections) rows: (.ref result 'rows))))
      (.o status: 'executed
          changed-files: (execute 'revision-changed-files
                                  (revision-files 'changes)
                                  '((f path)))
          inventory: (execute 'revision-change-evidence
                              (file-report-path 'enumerated_by)
                              '((f path) (e method)))
          verified-reports: (execute 'revision-verified-reports
                                     (revision-step 'verified_report 'e 'EvidenceReport)
                                     '((e method)))
          missing-reports: (execute 'revision-missing-reports
                                    (revision-step 'missing_report 'e 'EvidenceReport)
                                    '((e method)))
          project-inputs: (execute 'revision-project-inputs
                                   (revision-files 'reads_config)
                                   '((f path) (f changed)))
          policy-sources: (execute 'revision-policy-sources
                                   (revision-files 'has_policy_source)
                                   '((f path) (f changed)))
          engineering-reference: (execute 'revision-engineering-reference
                                   (revision-step 'names_engineering_item 'e 'EngineeringReference
                                     (revision-files 'declared_in))
                                   '((e engineeringId) (e element) (f path)))
          model-evidence: (execute 'revision-model-evidence
                                   (file-report-path 'parsed_by)
                                   '((f path) (e method)))))))

(def (revision-files relation-value (next-step #f))
  (revision-step relation-value 'f 'FileVersion next-step))

(def (revision-step relation-value binding-value label-value (next-step #f))
  (.o (:: @ GraphSyntaxStep.) relation: relation-value
      target: (.o (:: @ GraphSyntaxNode.) binding: binding-value label: label-value)
      next: next-step))

(def (file-report-path relation-value)
  (revision-files 'changes
    (revision-step relation-value 'e 'EvidenceReport)))

(def (revision-query graph-id-value revision-value ids name path columns)
  (let (bound (length ids))
    (.o (:: @ AgenticAILabQuery.) identity: name version: "1"
        semantic-revision: revision-value element-space-identity: graph-id-value
        selected-element-identities: ids
        language: AgenticAILabSchemeGqlQueryLanguage. result-bound: bound
        completeness-requirement: 'partial-allowed
        result-contract: (agentic-ai-lab-query-result-contract
                          name 'relation-row (map cadr columns) bound)
        program:
        (.o (:: @ AgenticAILabGqlQueryProgram.) identity: name
            match: (.o (:: @ GraphSyntaxPath.)
                       start: (.o (:: @ GraphSyntaxNode.) binding: 'r label: 'Revision)
                       next: path)
            where: (.o (:: @ GraphSyntaxEquals.)
                       left: (.o (:: @ GraphSyntaxProperty.) binding: 'r property: 'revision)
                       right: (.o (:: @ GraphSyntaxLiteral.) literal-kind: 'string value: revision-value))
            project: (foldr (lambda (column next-projection)
                              (.o (:: @ GraphSyntaxProjection.)
                                  expression: (.o (:: @ GraphSyntaxProperty.)
                                                  binding: (car column) property: (cadr column))
                                  next: next-projection))
                            #f columns)))))
