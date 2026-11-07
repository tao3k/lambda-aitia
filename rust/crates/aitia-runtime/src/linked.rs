// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bind AITIA operations to the compiled Scheme program.

use gerbil_scheme::{GerbilRuntime, LinkedGerbilProgram, LinkedObjectExport, NativeError};
use gerbil_scheme_sys::{GerbilGlobalState, GerbilModuleOrLink};

unsafe extern "C" {
    fn ___LNK_aitia__program(state: *mut GerbilGlobalState) -> *mut GerbilModuleOrLink;
    fn aitia_program_flow_graph(request: i64) -> i64;
    fn aitia_program_gitops_evaluate(request: i64) -> i64;
    fn aitia_program_org_contract_evaluate(request: i64) -> i64;
    fn aitia_program_project_config_validate(request: i64) -> i64;
}

/// Operations borrowed from the live Scheme program.
pub struct AitiaProgram<'runtime> {
    runtime: &'runtime GerbilRuntime,
    flow_graph: LinkedObjectExport<'runtime>,
    gitops_evaluate: LinkedObjectExport<'runtime>,
    org_contract_evaluate: LinkedObjectExport<'runtime>,
    project_config_validate: LinkedObjectExport<'runtime>,
}

impl AitiaProgram<'_> {
    /// Run the published SDLC flow-graph operation.
    ///
    /// # Errors
    ///
    /// Propagates request conversion, rooted call, and result conversion failures.
    pub fn flow_graph(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.flow_graph, request)
    }

    /// Evaluate a GitOps change using the published Scheme Scenario.
    ///
    /// # Errors
    ///
    /// Propagates request conversion, rooted call, and result conversion failures.
    pub fn gitops_evaluate(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.gitops_evaluate, request)
    }

    /// Evaluate an Orgize Contract over supplied Element facts.
    ///
    /// # Errors
    ///
    /// Propagates transport and Orgize evaluation errors.
    pub fn org_contract_evaluate(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.org_contract_evaluate, request)
    }

    /// Validate the project envelope through the published Yuanxu Contract.
    ///
    /// # Errors
    /// Propagates errors while resolving the declaration and projecting checks.
    pub fn project_config_validate(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.project_config_validate, request)
    }

    fn call(
        &self,
        operation: &LinkedObjectExport<'_>,
        request: &str,
    ) -> Result<String, NativeError> {
        let request = self.runtime.string_from_utf8(request)?.into_object();
        operation
            .call(&request)
            .into_result()?
            .into_string()?
            .to_string()
            .into_result()
    }
}

/// Initialize the linked program once and execute operations on its owner thread.
///
/// # Errors
///
/// Propagates initialization, rooted call, or result conversion failures.
pub fn with_linked_program<T>(
    operation: impl for<'runtime> FnOnce(AitiaProgram<'runtime>) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    // SAFETY: Cargo links the compiler-owned archive containing the SDK startup
    // stub and the matching Scheme entry. No other image is used by this call.
    let program = unsafe { LinkedGerbilProgram::from_linker(___LNK_aitia__program) };
    crate::with_program(program, |runtime| {
        // SAFETY: The same archive owns the export. It delegates root custody
        // and exception containment to the bridge's gerbil-rs-rooted-call.
        let flow_graph = unsafe { runtime.bind_object_export(aitia_program_flow_graph) }?;
        // SAFETY: The GitOps entry uses the same archive and rooted-call contract.
        let gitops_evaluate = unsafe { runtime.bind_object_export(aitia_program_gitops_evaluate) }?;
        // SAFETY: The Orgize projection uses the same rooted-call contract.
        let org_contract_evaluate =
            unsafe { runtime.bind_object_export(aitia_program_org_contract_evaluate) }?;
        // SAFETY: This entry uses the same archive and rooted-call contract.
        let project_config_validate =
            unsafe { runtime.bind_object_export(aitia_program_project_config_validate) }?;
        operation(AitiaProgram {
            runtime,
            flow_graph,
            gitops_evaluate,
            org_contract_evaluate,
            project_config_validate,
        })
    })
}
