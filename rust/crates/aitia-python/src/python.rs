// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

use aitia_runtime::{AitiaSession, SessionError};
use pyo3::exceptions::PyRuntimeError;
use pyo3::types::{PyAnyMethods, PyModule, PyModuleMethods};
#[cfg(unix)]
use pyo3::types::{PyBytes, PyBytesMethods, PyDict, PyDictMethods};
use pyo3::{
    Bound, Py, PyAny, PyErr, PyRef, PyResult, Python, pyclass, pyfunction, pymethods, pymodule,
};
#[cfg(unix)]
use std::path::PathBuf;
use std::sync::Mutex;

#[pyclass(name = "Session", module = "lambda_aitia_rust")]
struct PythonSession {
    session: Mutex<Option<AitiaSession>>,
}

#[pymethods]
impl PythonSession {
    #[new]
    fn new(py: Python<'_>) -> PyResult<Self> {
        let session = py.detach(AitiaSession::start).map_err(runtime_error)?;
        Ok(Self {
            session: Mutex::new(Some(session)),
        })
    }

    fn flow_graph(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::flow_graph)
    }

    fn gitops_evaluate(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::gitops_evaluate)
    }

    fn org_contract_evaluate(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::org_contract_evaluate)
    }

    fn project_config_validate(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::project_config_validate)
    }

    fn evidence_lineage(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::evidence_lineage)
    }

    fn workflow_reconcile(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::workflow_reconcile)
    }

    fn workflow_protocol_step(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::workflow_protocol_step)
    }

    fn sidecar_audit_assess(&self, py: Python<'_>, request: String) -> PyResult<String> {
        self.call(py, request, AitiaSession::sidecar_audit_assess)
    }

    #[pyo3(signature = (directory=".", case_id="aitia/case/gitops-commit", overlay=None, execute_fenced=false))]
    fn drive_protocol(
        &self,
        py: Python<'_>,
        directory: &str,
        case_id: &str,
        overlay: Option<String>,
        execute_fenced: bool,
    ) -> PyResult<String> {
        let directory = directory.to_owned();
        let case_id = case_id.to_owned();
        py.detach(|| {
            let session = self
                .session
                .lock()
                .map_err(|_| PyRuntimeError::new_err(SessionError::OwnerPanicked.to_string()))?;
            let live = session
                .as_ref()
                .ok_or_else(|| PyRuntimeError::new_err(SessionError::OwnerStopped.to_string()))?;
            live.drive_protocol(directory, case_id, overlay, execute_fenced)
                .map_err(PyRuntimeError::new_err)
        })
    }

    #[pyo3(signature = (request, execute_fenced=false))]
    fn drive_multi_repo_protocol(
        &self,
        py: Python<'_>,
        request: String,
        execute_fenced: bool,
    ) -> PyResult<String> {
        py.detach(|| {
            let session = self
                .session
                .lock()
                .map_err(|_| PyRuntimeError::new_err(SessionError::OwnerPanicked.to_string()))?;
            let live = session
                .as_ref()
                .ok_or_else(|| PyRuntimeError::new_err(SessionError::OwnerStopped.to_string()))?;
            live.drive_multi_repo_protocol(request, execute_fenced)
                .map_err(PyRuntimeError::new_err)
        })
    }

    fn __enter__(slf: PyRef<'_, Self>) -> Py<Self> {
        slf.into()
    }

    fn __exit__(
        &self,
        py: Python<'_>,
        _exc_type: Option<&Bound<'_, PyAny>>,
        _exc_value: Option<&Bound<'_, PyAny>>,
        _traceback: Option<&Bound<'_, PyAny>>,
    ) -> PyResult<bool> {
        self.close(py)?;
        Ok(false)
    }

    fn close(&self, py: Python<'_>) -> PyResult<()> {
        py.detach(|| {
            let mut session = self
                .session
                .lock()
                .map_err(|_| SessionError::OwnerPanicked)?;
            session.take().map_or(Ok(()), AitiaSession::close)
        })
        .map_err(runtime_error)
    }
}

impl PythonSession {
    fn call(
        &self,
        py: Python<'_>,
        request: String,
        operation: fn(&AitiaSession, String) -> Result<String, SessionError>,
    ) -> PyResult<String> {
        py.detach(|| {
            let session = self
                .session
                .lock()
                .map_err(|_| SessionError::OwnerPanicked)?;
            operation(session.as_ref().ok_or(SessionError::OwnerStopped)?, request)
        })
        .map_err(runtime_error)
    }
}

fn runtime_error(error: SessionError) -> PyErr {
    PyRuntimeError::new_err(error.to_string())
}

#[pyo3::pyfunction]
fn host_capabilities() -> PyResult<String> {
    aitia_runtime::host_capabilities_json().map_err(PyRuntimeError::new_err)
}

#[pyo3::pyfunction]
fn dispatch_host_frames(py: Python<'_>, frames_json: String) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::dispatch_host_frames_json(&frames_json).map_err(PyRuntimeError::new_err)
    })
}

#[cfg(unix)]
#[pyo3::pyfunction]
fn capture_source_tree(py: Python<'_>, root: PathBuf) -> PyResult<Bound<'_, PyBytes>> {
    let bytes = py.detach(move || aitia_runtime::capture_source_tree(&root))?;
    Ok(PyBytes::new(py, &bytes))
}

/// Observe pytest running against an isolated frozen source snapshot.
#[cfg(unix)]
#[pyo3::pyfunction]
fn run_frozen_pytest<'py>(
    py: Python<'py>,
    interpreter: PathBuf,
    payload: &Bound<'py, PyBytes>,
    selectors: Vec<String>,
) -> PyResult<Bound<'py, PyDict>> {
    use aitia_runtime::PytestExit;

    let payload = payload.as_bytes();
    let run = py.detach(move || {
        let selectors: Vec<_> = selectors.iter().map(String::as_str).collect();
        aitia_runtime::run_frozen_pytest(&interpreter, payload, &selectors)
    })?;
    let (outcome, exit_code) = match run.exit {
        PytestExit::Exited(status) => ("exited", status.code()),
        PytestExit::TimedOut => ("timed-out", None),
        PytestExit::OutputExceeded => ("output-exceeded", None),
    };
    let result = PyDict::new(py);
    result.set_item("outcome", outcome)?;
    result.set_item("verdict", run.verdict().as_str())?;
    result.set_item("exit_code", exit_code)?;
    result.set_item("source_unchanged", run.source_unchanged)?;
    result.set_item("source_sha256", run.source_sha256)?;
    result.set_item("observed_source_sha256", run.observed_source_sha256)?;
    result.set_item("selectors", run.selectors)?;
    result.set_item("output_tail", PyBytes::new(py, &run.output_tail))?;
    let report = run
        .report
        .map(|observed| {
            let report = PyDict::new(py);
            report.set_item("sha256", observed.sha256)?;
            report.set_item("passed", observed.passed)?;
            report.set_item("failed", observed.failed)?;
            report.set_item("skipped", observed.skipped)?;
            Ok::<_, PyErr>(report)
        })
        .transpose()?;
    result.set_item("report", report)?;
    Ok(result)
}

#[cfg(unix)]
#[pyclass(name = "OrgEdit", module = "lambda_aitia_rust", frozen)]
struct PythonOrgEdit(aitia_runtime::OrgEdit);

#[cfg(unix)]
#[pymethods]
impl PythonOrgEdit {
    #[new]
    fn new(
        node_id: String,
        start_byte: usize,
        end_byte: usize,
        expected: String,
        replacement: String,
    ) -> Self {
        Self(aitia_runtime::OrgEdit {
            node_id,
            span: start_byte..end_byte,
            expected,
            replacement,
        })
    }

    #[getter]
    fn node_id(&self) -> &str {
        &self.0.node_id
    }

    #[getter]
    fn start_byte(&self) -> usize {
        self.0.span.start
    }

    #[getter]
    fn end_byte(&self) -> usize {
        self.0.span.end
    }

    #[getter]
    fn expected(&self) -> &str {
        &self.0.expected
    }

    #[getter]
    fn replacement(&self) -> &str {
        &self.0.replacement
    }
}

#[cfg(unix)]
#[pyclass(name = "OrgEditReview", module = "lambda_aitia_rust", frozen)]
struct PythonOrgEditReview(aitia_runtime::OrgEditReview);

#[cfg(unix)]
#[pymethods]
impl PythonOrgEditReview {
    #[new]
    fn new(
        py: Python<'_>,
        source_id: String,
        source: &Bound<'_, PyBytes>,
        projected_sha256: String,
        edits: Vec<pyo3::PyRef<'_, PythonOrgEdit>>,
    ) -> PyResult<Self> {
        let edits = edits.iter().map(|edit| edit.0.clone()).collect();
        let source = source.as_bytes();
        let review = py.detach(move || {
            aitia_runtime::OrgEditReview::prepare(source_id, source, &projected_sha256, edits)
        })?;
        Ok(Self(review))
    }

    #[getter]
    fn source_id(&self) -> &str {
        self.0.source_id()
    }

    #[getter]
    fn source_sha256(&self) -> &str {
        self.0.source_sha256()
    }

    #[getter]
    fn edits(&self) -> Vec<PythonOrgEdit> {
        self.0.edits().iter().cloned().map(PythonOrgEdit).collect()
    }

    fn source_current(&self, py: Python<'_>, source: &Bound<'_, PyBytes>) -> bool {
        let source = source.as_bytes();
        py.detach(|| self.0.source_current(source))
    }
}

#[pyfunction]
#[pyo3(signature = (bundle_json, workspace_sysml_path=None))]
fn verify_portable_audit_bundle(
    py: Python<'_>,
    bundle_json: String,
    workspace_sysml_path: Option<String>,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_portable_audit_bundle_json(
            &bundle_json,
            workspace_sysml_path.as_deref().map(std::path::Path::new),
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn generate_repo_merkle_proof(
    py: Python<'_>,
    bundle_json: String,
    repo_id: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::generate_repo_merkle_proof_json(&bundle_json, &repo_id)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_repo_merkle_proof(
    py: Python<'_>,
    proof_json: String,
    expected_merkle_root: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_repo_merkle_proof_json(&proof_json, &expected_merkle_root)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn generate_consistency_proof(
    py: Python<'_>,
    entries_json: String,
    first_size: usize,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::generate_consistency_proof_json(&entries_json, first_size)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_consistency_proof(
    py: Python<'_>,
    proof_json: String,
    expected_first_root: String,
    expected_second_root: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_consistency_proof_json(
            &proof_json,
            &expected_first_root,
            &expected_second_root,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn sign_checkpoint(
    py: Python<'_>,
    origin: String,
    entries_json: String,
    origin_seed_hex: String,
    witness_specs_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::sign_checkpoint_json(
            &origin,
            &entries_json,
            &origin_seed_hex,
            &witness_specs_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_signed_checkpoint(
    py: Python<'_>,
    checkpoint_json: String,
    policy_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_signed_checkpoint_json(&checkpoint_json, &policy_json)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_checkpoint_transition(
    py: Python<'_>,
    first_checkpoint_json: String,
    second_checkpoint_json: String,
    proof_json: String,
    policy_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_checkpoint_transition_json(
            &first_checkpoint_json,
            &second_checkpoint_json,
            &proof_json,
            &policy_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
#[pyo3(signature = (left_checkpoint_json, right_checkpoint_json, policy_json, proof_json=None))]
fn detect_checkpoint_equivocation(
    py: Python<'_>,
    left_checkpoint_json: String,
    right_checkpoint_json: String,
    policy_json: String,
    proof_json: Option<String>,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::detect_checkpoint_equivocation_json(
            &left_checkpoint_json,
            &right_checkpoint_json,
            &policy_json,
            proof_json.as_deref(),
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn export_dsse_intoto_envelope(
    py: Python<'_>,
    attestation_json: String,
    signing_seeds_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::export_dsse_intoto_envelope_json(&attestation_json, &signing_seeds_json)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_dsse_intoto_envelope(
    py: Python<'_>,
    envelope_json: String,
    trust_root_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_dsse_intoto_envelope_json(&envelope_json, &trust_root_json)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
#[pyo3(signature = (spec_json, workspace_sysml_path=None))]
fn export_portable_audit_bundle(
    py: Python<'_>,
    spec_json: String,
    workspace_sysml_path: Option<String>,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::export_portable_audit_bundle_json(
            &spec_json,
            workspace_sysml_path.as_deref().map(std::path::Path::new),
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn export_sigstore_bundle_v03(
    py: Python<'_>,
    portable_bundle_json: String,
    trust_root_json: String,
    federated_policy_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::export_sigstore_bundle_v03_json(
            &portable_bundle_json,
            &trust_root_json,
            &federated_policy_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_sigstore_bundle_v03(
    py: Python<'_>,
    sigstore_bundle_json: String,
    trust_root_json: String,
    federated_policy_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_sigstore_bundle_v03_json(
            &sigstore_bundle_json,
            &trust_root_json,
            &federated_policy_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn capture_detached_audit_context(
    py: Python<'_>,
    repo_dir: String,
    base_ref: String,
    profile_json: String,
    deterministic_checks_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::capture_detached_audit_context_json(
            std::path::Path::new(&repo_dir),
            &base_ref,
            &profile_json,
            &deterministic_checks_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_ai_audit_and_conversation(
    py: Python<'_>,
    context_json: String,
    ai_reports_json: String,
    conversation_json: String,
    human_decision_json: String,
    profile_json: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_ai_audit_and_conversation_json(
            &context_json,
            &ai_reports_json,
            &conversation_json,
            &human_decision_json,
            &profile_json,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn build_nasa_sidecar_receipt(py: Python<'_>, spec_json: String) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::build_nasa_sidecar_receipt_json(&spec_json)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn assess_sidecar_audit_ascent(py: Python<'_>, request_json: String) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::assess_sidecar_audit_ascent_json(&request_json)
            .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn verify_de_formal_evidence(
    py: Python<'_>,
    formal_evidence_json: String,
    expected_context_digest: String,
) -> PyResult<String> {
    py.detach(move || {
        aitia_runtime::verify_de_formal_evidence_json(
            &formal_evidence_json,
            &expected_context_digest,
        )
        .map_err(|error| error.to_string())
    })
    .map_err(pyo3::exceptions::PyValueError::new_err)
}

#[pyfunction]
fn _shutdown_runtime(py: Python<'_>) {
    py.detach(aitia_runtime::shutdown_shared_owner);
}

#[pymodule]
fn lambda_aitia_rust(module: &Bound<'_, PyModule>) -> PyResult<()> {
    let shutdown_fn = pyo3::wrap_pyfunction!(_shutdown_runtime, module)?;
    module.add_function(shutdown_fn.clone())?;
    module
        .py()
        .import("atexit")?
        .call_method1("register", (shutdown_fn,))?;
    module.add_function(pyo3::wrap_pyfunction!(host_capabilities, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(dispatch_host_frames, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        verify_portable_audit_bundle,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(generate_repo_merkle_proof, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_repo_merkle_proof, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(generate_consistency_proof, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_consistency_proof, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(sign_checkpoint, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_signed_checkpoint, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        verify_checkpoint_transition,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        detect_checkpoint_equivocation,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(export_dsse_intoto_envelope, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_dsse_intoto_envelope, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        export_portable_audit_bundle,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(export_sigstore_bundle_v03, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_sigstore_bundle_v03, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        capture_detached_audit_context,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        verify_ai_audit_and_conversation,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(build_nasa_sidecar_receipt, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(assess_sidecar_audit_ascent, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(verify_de_formal_evidence, module)?)?;
    #[cfg(unix)]
    module.add_function(pyo3::wrap_pyfunction!(capture_source_tree, module)?)?;
    #[cfg(unix)]
    module.add_function(pyo3::wrap_pyfunction!(run_frozen_pytest, module)?)?;
    #[cfg(unix)]
    module.add_class::<PythonOrgEdit>()?;
    #[cfg(unix)]
    module.add_class::<PythonOrgEditReview>()?;
    module.add_class::<PythonSession>()
}
