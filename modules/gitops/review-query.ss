;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o .get .ref)
        (only-in :tao3k/yuanxu/graph/types yuanxu-graph-id yuanxu-graph-nodes yuanxu-graph-node-id)
        (only-in :tao3k/agentic-ai-lab/modules/query/config AgenticAILabQueryModule.)
        (only-in :tao3k/agentic-ai-lab/modules/query/objects
                 AgenticAILabQuery. AgenticAILabSchemeGqlQueryLanguage.
                 AgenticAILabGqlQueryProgram. GraphSyntaxNode. GraphSyntaxStep. GraphSyntaxPath.
                 GraphSyntaxEquals. GraphSyntaxLiteral. GraphSyntaxProperty. GraphSyntaxProjection.
                 agentic-ai-lab-query-element-space agentic-ai-lab-query-result-contract))
(export gitops-review-query)

(def (gitops-review-query graph revision)
  (let (identity (yuanxu-graph-id graph))
    (unless (eq? identity (string->symbol revision))
      (error "Review query revision differs from the evidence graph"))
    (let* ((ids (map yuanxu-graph-node-id (yuanxu-graph-nodes graph)))
           (space (agentic-ai-lab-query-element-space identity revision ids #f))
           (select (.ref AgenticAILabQueryModule. '.select-scheme-graph))
           (project (.ref AgenticAILabQueryModule. '.project-gql)))
      (def (execute name path projections)
        (let* ((query (revision-query identity revision ids name path projections))
               (result (select query space graph)))
          (.o status: 'executed
              gql: (project query)
              revision: (.get result semantic-revision)
              complete?: (.get result complete?)
              action-authority?: (.get result action-authority?)
              columns: (map cadr projections)
              rows: (.get result rows))))
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
          related-decisions: (execute 'revision-related-decisions
                               (revision-step 'relates_decision 'd 'DecisionRecord
                                 (revision-files 'declared_in))
                               '((d adrId) (d revision) (d status) (d relation) (f path)))
          affected-domains: (execute 'revision-affected-domains
                              (revision-files 'changes
                                (revision-step 'owned_by_domain 'd 'Domain))
                              '((d domain) (d ownerModule) (f path)))
          model-evidence: (execute 'revision-model-evidence
                                   (file-report-path 'parsed_by)
                                   '((f path) (e method)))))))

(def (revision-files relation (next-step #f))
  (revision-step relation 'f 'FileVersion next-step))

(def (revision-step relation binding label (next-step #f))
  (.o (:: @ GraphSyntaxStep.) (relation := relation)
      target: (.o (:: @ GraphSyntaxNode.) (binding := binding) (label := label))
      next: next-step))

(def (file-report-path relation)
  (revision-files 'changes
    (revision-step relation 'e 'EvidenceReport)))

(def (revision-query graph-id revision ids name path columns)
  (let (bound (length ids))
    (.o (:: @ AgenticAILabQuery.) identity: name version: "1"
        semantic-revision: revision element-space-identity: graph-id
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
                       right: (.o (:: @ GraphSyntaxLiteral.) literal-kind: 'string value: revision))
            project: (foldr (lambda (column next-projection)
                              (.o (:: @ GraphSyntaxProjection.)
                                  expression: (.o (:: @ GraphSyntaxProperty.)
                                                  binding: (car column) property: (cadr column))
                                  next: next-projection))
                            #f columns)))))
