;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :gerbil/runtime/init gerbil-load-expander!)
        (only-in :gerbil-scheme-rust/scheme/runtime gerbil-rs-rooted-call)
        (only-in "../../bindings/operations.ss"
                 aitia-sdlc-flow-graph-payload aitia-gitops-evaluate-payload
                 aitia-org-contract-evaluate-payload aitia-project-config-validate-payload))
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
  (c-define (project-config-validate request) (int64) int64 "aitia_program_project_config_validate" "extern"
    (gerbil-scheme-rust/scheme/runtime#gerbil-rs-rooted-call
     request lambda-aitia/bindings/operations#aitia-project-config-validate-payload)))
