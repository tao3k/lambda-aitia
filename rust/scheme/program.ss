;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/init gerbil-load-expander!)
        (only-in :gerbil-scheme-rust/scheme/runtime gerbil-rs-rooted-call)
        (only-in "../../bindings/operations.ss"
                 aitia-sdlc-flow-graph-payload aitia-gitops-evaluate-payload
                 aitia-org-contract-evaluate-payload aitia-project-config-validate-payload
                 aitia-agent-input-check-payload aitia-agent-input-assess-payload
                 aitia-pytest-assess-payload aitia-context-operation aitia-nasa-draft-payload
                 aitia-commit-journal-payload))
(export main)

(def (main . _)
  (gerbil-load-expander!))

(begin-foreign
  (c-define (flow-graph request) (int64) int64 "aitia_program_flow_graph" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-sdlc-flow-graph-payload))
  (c-define (gitops-evaluate request) (int64) int64 "aitia_program_gitops_evaluate" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-gitops-evaluate-payload))
  (c-define (org-contract-evaluate request) (int64) int64 "aitia_program_org_contract_evaluate" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-org-contract-evaluate-payload))
  (c-define (agent-input-check request) (int64) int64 "aitia_program_agent_input_check" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-agent-input-check-payload))
  (c-define (agent-input-assess request) (int64) int64 "aitia_program_agent_input_assess" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-agent-input-assess-payload))
  (c-define (pytest-assess request) (int64) int64 "aitia_program_pytest_assess" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-pytest-assess-payload))
  (c-define (context-operation request) (int64) int64 "aitia_program_context_operation" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-context-operation))
  (c-define (commit-journal request) (int64) int64 "aitia_program_commit_journal" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-commit-journal-payload))
  (c-define (nasa-draft request) (int64) int64 "aitia_program_nasa_draft" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-nasa-draft-payload))
  (c-define (project-config-validate request) (int64) int64 "aitia_program_project_config_validate" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-project-config-validate-payload)))
