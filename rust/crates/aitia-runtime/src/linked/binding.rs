// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bind AITIA operations to the compiled Scheme program.

use gerbil_scheme::{
    CollectionKind, GerbilRuntime, LinkedGerbilProgram, LinkedObjectExport, NativeError,
    RootedSchemeCollection, RootedSchemeObject,
};
use gerbil_scheme_sys::{
    GerbilGlobalState, GerbilModuleOrLink, gerbil_scheme_rust_take_call_error_raw,
};

#[cfg(unix)]
use crate::MAX_REQUEST_BYTES;

// Adapt the bridge's argument-free, one-shot diagnostic export to its safe
// bytevector owner API. The input is unused and never retained.
unsafe extern "C" fn linked_call_error(_: *const u8, _: usize) -> i64 {
    // SAFETY: callers bind this only on the initialized Scheme owner, after
    // a failed rooted call. The bridge transfers at most one diagnostic root.
    unsafe { gerbil_scheme_rust_take_call_error_raw() }
}

unsafe extern "C" {
    fn ___LNK_aitia__program(state: *mut GerbilGlobalState) -> *mut GerbilModuleOrLink;
    fn aitia_program_flow_graph(request: i64) -> i64;
    fn aitia_program_gitops_evaluate(request: i64) -> i64;
    fn aitia_program_org_contract_evaluate(request: i64) -> i64;
    fn aitia_program_project_config_validate(request: i64) -> i64;
    fn aitia_program_commit_journal(request: i64) -> i64;
    fn aitia_program_nasa_draft(request: i64) -> i64;
    fn aitia_program_evidence_lineage(request: i64) -> i64;
    fn aitia_program_agent_input_check(request: i64) -> i64;
    #[cfg(unix)]
    fn aitia_program_agent_input_assess(request: i64) -> i64;
    #[cfg(unix)]
    fn aitia_program_pytest_assess(request: i64) -> i64;
    #[cfg(unix)]
    fn aitia_program_context_operation(request: i64) -> i64;
}

/// Operations borrowed from the live Scheme program.
pub struct AitiaProgram<'runtime> {
    pub(super) runtime: &'runtime GerbilRuntime,
    flow_graph: LinkedObjectExport<'runtime>,
    gitops_evaluate: LinkedObjectExport<'runtime>,
    org_contract_evaluate: LinkedObjectExport<'runtime>,
    project_config_validate: LinkedObjectExport<'runtime>,
    commit_journal: LinkedObjectExport<'runtime>,
    nasa_draft: LinkedObjectExport<'runtime>,
    evidence_lineage: LinkedObjectExport<'runtime>,
    agent_input_check: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    agent_input_assess: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    pytest_assess: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    pub(super) context_operation: LinkedObjectExport<'runtime>,
}

/// Outcome at the recorded Agent input delivery boundary.
#[cfg(unix)]
#[derive(Debug)]
pub enum RecordedAgentInput<T, E> {
    Refused,
    ConsumerFailed(E),
    Delivered {
        result: T,
        observation: RecordedAgentInputObservation,
    },
}

/// An inert Host assessment or an obligation reopened by a changed JJ cut.
#[cfg(unix)]
#[derive(Debug)]
pub enum AgentInputSupport {
    Assessed(serde_json::Value),
    Reopened,
}

/// Owner declaration for a recorded replay assessment.
#[cfg(unix)]
pub struct ReplayAssessmentScope<'a> {
    pub project: &'a str,
    pub workspace: &'a std::path::Path,
    pub obligation: &'a str,
    pub selector: &'a str,
    pub deployment_profile: Option<&'a str>,
}

/// Observation of a successful consumer call over a checked packet at a
/// recorded workspace cut. Currentness is evaluated when the observation is used.
#[cfg(unix)]
#[derive(Debug)]
pub struct RecordedAgentInputObservation {
    project: String,
    cut: Box<aitia_jj::WorkspaceCut>,
    history_path: String,
    source_digest: String,
    packet_digest: String,
    provider_request: bool,
}

#[cfg(unix)]
impl RecordedAgentInputObservation {
    pub fn project(&self) -> &str {
        &self.project
    }

    pub fn cut(&self) -> &aitia_jj::WorkspaceCut {
        &self.cut
    }

    pub fn history_path(&self) -> &str {
        &self.history_path
    }

    pub fn source_digest(&self) -> &str {
        &self.source_digest
    }

    pub fn packet_digest(&self) -> &str {
        &self.packet_digest
    }

    /// Revalidate the workspace cut before using the observation as evidence.
    ///
    /// # Errors
    /// Refuses a changed workspace cut or an unreadable repository.
    pub fn require_current(&self) -> Result<(), aitia_jj::JjObservationError> {
        require_current_cut(&self.cut)
    }
}

#[cfg(unix)]
fn require_current_cut(cut: &aitia_jj::WorkspaceCut) -> Result<(), aitia_jj::JjObservationError> {
    if aitia_jj::observe_workspace(cut.workspace_root())? != *cut {
        return Err(aitia_jj::JjObservationError::ChangedOperation);
    }
    Ok(())
}

impl<'runtime> AitiaProgram<'runtime> {
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
        self.resolve_project_config(request)
            .map(|(_, projection)| projection)
    }

    pub(crate) fn resolve_project_config(
        &self,
        request: &str,
    ) -> Result<(RootedSchemeCollection<'runtime>, String), NativeError> {
        let request = self.runtime.string_from_utf8(request)?.into_object();
        let config = self
            .call_rooted(&self.project_config_validate, &request)?
            .into_collection(CollectionKind::Pair)?;
        let projection = config
            .element(1)?
            .into_string()?
            .to_string()
            .into_result()?;
        Ok((config, projection))
    }

    pub(crate) fn commit_journal(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.commit_journal, request)
    }

    pub(crate) fn evidence_lineage(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.evidence_lineage, request)
    }

    pub(crate) fn nasa_draft(
        &self,
        config: &RootedSchemeCollection<'_>,
        request: &serde_json::Value,
    ) -> Result<serde_json::Value, NativeError> {
        let review_configuration = config.element(0)?;
        let payload = super::review_input::to_scheme(self.runtime, request)?;
        let input = self
            .runtime
            .collection_from_objects(CollectionKind::Pair, &[&review_configuration, &payload])?;
        let result = self.call_rooted(&self.nasa_draft, &input.into_object())?;
        super::review_input::from_scheme(result)
    }

    /// Check the projected input against owner-supplied history and deliver
    /// the exact serialized packet to the consumer on acceptance.
    ///
    /// A refusal returns `None` without invoking the consumer. The checked
    /// packet is borrowed only for the call. This check conveys no tool or
    /// effect authority.
    ///
    /// # Errors
    /// Propagates Scheme transport or evaluation failures before delivery.
    pub fn with_verified_agent_input<T>(
        &self,
        source: &serde_json::Value,
        projected: &serde_json::Value,
        consume: impl FnOnce(&str) -> T,
    ) -> Result<Option<T>, NativeError> {
        Ok(self
            .checked_agent_input(&source.to_string(), projected, false)?
            .as_deref()
            .map(consume))
    }

    /// Read the original history at a recorded JJ cut and deliver only an
    /// accepted projection. Successful delivery yields a historical observation.
    ///
    /// A consumer failure is returned separately from a refusal before delivery.
    /// The observation describes the callback boundary and conveys no authority.
    ///
    /// # Errors
    /// Refuses stale or unreadable history and propagates Scheme call errors.
    #[cfg(unix)]
    pub fn with_verified_recorded_agent_input<T, E>(
        &self,
        project: &str,
        cut: &aitia_jj::WorkspaceCut,
        history_path: &str,
        projected: &serde_json::Value,
        consume: impl FnOnce(&str) -> Result<T, E>,
    ) -> Result<RecordedAgentInput<T, E>, Box<dyn std::error::Error>> {
        self.deliver_recorded_agent_input(project, cut, history_path, projected, false, consume)
    }

    /// Build a provider request with owner-selected settings and deliver the
    /// exact checked request body to the provider transport.
    ///
    /// The renderer supplies only the input. A template with an input is
    /// refused. The owner remains responsible for the transport and authority.
    ///
    /// # Errors
    /// Propagates the recorded-input and Scheme errors before delivery.
    #[cfg(unix)]
    pub fn with_verified_recorded_provider_request<T, E>(
        &self,
        project: &str,
        cut: &aitia_jj::WorkspaceCut,
        history_path: &str,
        request_settings: &serde_json::Map<String, serde_json::Value>,
        projected_input: serde_json::Value,
        send: impl FnOnce(&str) -> Result<T, E>,
    ) -> Result<RecordedAgentInput<T, E>, Box<dyn std::error::Error>> {
        if request_settings.contains_key("input") {
            return Ok(RecordedAgentInput::Refused);
        }
        let mut request = request_settings.clone();
        request.insert("input".into(), projected_input);
        self.deliver_recorded_agent_input(
            project,
            cut,
            history_path,
            &serde_json::Value::Object(request),
            true,
            send,
        )
    }

    #[cfg(unix)]
    fn deliver_recorded_agent_input<T, E>(
        &self,
        project: &str,
        cut: &aitia_jj::WorkspaceCut,
        history_path: &str,
        projected: &serde_json::Value,
        provider_request: bool,
        consume: impl FnOnce(&str) -> Result<T, E>,
    ) -> Result<RecordedAgentInput<T, E>, Box<dyn std::error::Error>> {
        if project.trim().is_empty() {
            return Ok(RecordedAgentInput::Refused);
        }
        let files =
            aitia_jj::read_recorded_files(cut, &[history_path], MAX_REQUEST_BYTES as usize)?;
        let source = std::str::from_utf8(&files[0])?;
        let Some(packet) = self.checked_agent_input(source, projected, provider_request)? else {
            return Ok(RecordedAgentInput::Refused);
        };
        let observation = RecordedAgentInputObservation {
            project: project.to_owned(),
            cut: Box::new(cut.clone()),
            history_path: history_path.to_owned(),
            source_digest: crate::source_tree::sha256(source.as_bytes()),
            packet_digest: crate::source_tree::sha256(packet.as_bytes()),
            provider_request,
        };
        require_current_cut(cut)?;
        Ok(match consume(&packet) {
            Ok(result) => RecordedAgentInput::Delivered {
                result,
                observation,
            },
            Err(error) => RecordedAgentInput::ConsumerFailed(error),
        })
    }

    /// Assess a successful delivery through the Scheme Assurance Host.
    ///
    /// The projection describes support at the checked cut. Reassessment
    /// uses the original observation and never repeats delivery. The assessor
    /// supplies the expected project and a path inside the expected workspace.
    ///
    /// # Errors
    /// Rejects a different project, workspace or packet and propagates source and Host errors.
    #[cfg(unix)]
    pub fn assess_recorded_agent_input(
        &self,
        project: &str,
        workspace: &std::path::Path,
        observation: &RecordedAgentInputObservation,
        delivered_packet: &str,
    ) -> Result<AgentInputSupport, Box<dyn std::error::Error>> {
        if delivered_packet.len() > MAX_REQUEST_BYTES as usize
            || crate::source_tree::sha256(delivered_packet.as_bytes()) != observation.packet_digest
        {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "packet does not match the recorded delivery",
            )
            .into());
        }

        let cut = observation.cut();
        if project != observation.project()
            || aitia_jj::observe_workspace(workspace)?.workspace_root() != cut.workspace_root()
        {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "project or workspace does not match the recorded delivery",
            )
            .into());
        }
        let files = match aitia_jj::read_recorded_files(
            cut,
            &[observation.history_path()],
            MAX_REQUEST_BYTES as usize,
        ) {
            Ok(files) => files,
            Err(aitia_jj::JjObservationError::ChangedOperation) => {
                return Ok(AgentInputSupport::Reopened);
            }
            Err(error) => return Err(error.into()),
        };
        let source = std::str::from_utf8(&files[0])?;
        let request = serde_json::json!({
            "project": observation.project(),
            "operation": cut.operation_id(),
            "revision": cut.commit_id(),
            "historyPath": observation.history_path(),
            "source": source,
            "sourceDigest": observation.source_digest(),
            "packet": delivered_packet,
            "packetDigest": observation.packet_digest(),
            "providerRequest": observation.provider_request,
        });
        let response = self.call(&self.agent_input_assess, &request.to_string())?;
        match observation.require_current() {
            Ok(()) => Ok(AgentInputSupport::Assessed(serde_json::from_str(
                &response,
            )?)),
            Err(aitia_jj::JjObservationError::ChangedOperation) => Ok(AgentInputSupport::Reopened),
            Err(error) => Err(error.into()),
        }
    }

    /// Match an Org observation to an actual, single-case recorded pytest run
    /// and derive the disposition of its declared obligation at the live cut.
    ///
    /// The owner supplies the expected project, workspace and declared selector.
    /// A refusal returns `None` for mismatched evidence, selection or incomplete execution.
    /// The report has no effect authority.
    ///
    /// # Errors
    /// Propagates workspace and Scheme failures. A concurrent workspace change
    /// during assessment requires a fresh assessment of the same historical run.
    #[cfg(unix)]
    pub fn assess_recorded_pytest(
        &self,
        scope: ReplayAssessmentScope<'_>,
        receipt_source: &str,
        run: &crate::RecordedPytestRun,
    ) -> Result<Option<serde_json::Value>, Box<dyn std::error::Error>> {
        self.assess_pytest_replay(scope, Some(receipt_source), run)
    }

    #[cfg(unix)]
    pub(crate) fn assess_pytest_replay(
        &self,
        scope: ReplayAssessmentScope<'_>,
        receipt_source: Option<&str>,
        run: &crate::RecordedPytestRun,
    ) -> Result<Option<serde_json::Value>, Box<dyn std::error::Error>> {
        use crate::{PytestExit, PytestVerdict};
        let process = run.observation();
        let Some(report) = &process.report else {
            return Ok(None);
        };
        if run.project() != scope.project || process.selectors != [scope.selector] {
            return Ok(None);
        }
        let outcome = match process.verdict() {
            PytestVerdict::Passed if report.passed == 1 => "passed",
            PytestVerdict::ProcessFailed
                if matches!(process.exit, PytestExit::Exited(status) if status.code() == Some(1))
                    && report.passed == 0
                    && report.failed == 1
                    && report.errors == 0
                    && report.skipped == 0 =>
            {
                "failed"
            }
            _ => return Ok(None),
        };

        let recorded = run.cut();
        let current = aitia_jj::observe_workspace(scope.workspace)?;
        if current.workspace_root() != recorded.workspace_root() {
            return Ok(None);
        }
        let cut_fields = |cut: &aitia_jj::WorkspaceCut| {
            serde_json::json!({
                "workspace": cut.workspace_name(),
                "change": cut.change_id(),
                "operation": cut.operation_id(),
                "commit": cut.commit_id(),
                "tree": cut.tree_id(),
                "parents": cut.parent_ids(),
            })
        };
        let mut request = serde_json::json!({
            "project": run.project(),
            "current": cut_fields(&current),
            "recorded": cut_fields(recorded),
            "obligation": scope.obligation,
            "identity": report.sha256,
            "outcome": outcome,
            "selector": scope.selector,
            "source": receipt_source,
            "generateReceipt": receipt_source.is_none(),
            "sourceDigest": process.source_sha256,
            "reportDigest": report.sha256,
        });
        if let [message] = report.failure_messages.as_slice()
            && let Some(line) = message.lines().next()
        {
            request["failureMessage"] = serde_json::Value::String(line.to_owned());
        }
        if let Some(profile) = scope.deployment_profile {
            request["deploymentProfile"] = serde_json::Value::String(profile.to_owned());
        }
        if current == *recorded {
            use std::fmt::Write;
            let frozen = run.recorded_source()?;
            if frozen.len() > (MAX_REQUEST_BYTES as usize) / 2 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "recorded source exceeds the assessment transport budget",
                )
                .into());
            }
            if crate::source_tree::sha256(&frozen) != process.source_sha256 {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "recorded source does not match the executed replay",
                )
                .into());
            }
            let mut encoded = String::with_capacity(frozen.len() * 2);
            for byte in frozen {
                write!(&mut encoded, "{byte:02x}")?;
            }
            request["frozenSource"] = serde_json::Value::String(encoded);
        }
        let response = self.call(&self.pytest_assess, &request.to_string())?;
        require_current_cut(&current)?;
        Ok(serde_json::from_str(&response)?)
    }

    fn checked_agent_input(
        &self,
        source: &str,
        projected: &serde_json::Value,
        provider_request: bool,
    ) -> Result<Option<String>, NativeError> {
        let packet = projected.to_string();
        let request = serde_json::json!({
            "source": source,
            "projected": &packet,
            "providerRequest": provider_request,
        });
        let verdict = self.call(&self.agent_input_check, &request.to_string())?;
        Ok((verdict == "true").then_some(packet))
    }

    pub(super) fn call(
        &self,
        operation: &LinkedObjectExport<'_>,
        request: &str,
    ) -> Result<String, NativeError> {
        let request = self.runtime.string_from_utf8(request)?.into_object();
        self.call_rooted(operation, &request)?
            .into_string()?
            .to_string()
            .into_result()
    }

    fn call_rooted(
        &self,
        operation: &LinkedObjectExport<'runtime>,
        request: &RootedSchemeObject<'_>,
    ) -> Result<RootedSchemeObject<'runtime>, NativeError> {
        let response = operation.call(request).into_result();
        if response.is_err() {
            // SAFETY: the existing bridge export belongs to this initialized
            // archive and consumes only this owner's immediately preceding error.
            let diagnostic = unsafe { self.runtime.bind_bytes_export(linked_call_error) }
                .and_then(|export| export.call(&[]).into_result())
                .and_then(|bytes| bytes.to_vec().into_result());
            if let Ok(message) = diagnostic {
                eprintln!("{}", String::from_utf8_lossy(&message));
            }
        }
        response
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
        // SAFETY: Scheme owns the rooted request and result.
        let commit_journal = unsafe { runtime.bind_object_export(aitia_program_commit_journal) }?;
        // SAFETY: Scheme owns the rooted request and result.
        let nasa_draft = unsafe { runtime.bind_object_export(aitia_program_nasa_draft) }?;
        // SAFETY: this symbol belongs to the same initialized linked program.
        let evidence_lineage =
            unsafe { runtime.bind_object_export(aitia_program_evidence_lineage) }?;
        // SAFETY: The input check uses the same bridge-owned rooted call.
        let agent_input_check =
            unsafe { runtime.bind_object_export(aitia_program_agent_input_check) }?;
        // SAFETY: The private assessment export has the same rooted-call contract.
        #[cfg(unix)]
        let agent_input_assess =
            unsafe { runtime.bind_object_export(aitia_program_agent_input_assess) }?;
        // SAFETY: The replay assessment uses the same rooted-call contract.
        #[cfg(unix)]
        let pytest_assess = unsafe { runtime.bind_object_export(aitia_program_pytest_assess) }?;
        // SAFETY: The same bridge owns the command and delivery roots.
        #[cfg(unix)]
        let context_operation =
            unsafe { runtime.bind_object_export(aitia_program_context_operation) }?;
        operation(AitiaProgram {
            runtime,
            flow_graph,
            gitops_evaluate,
            org_contract_evaluate,
            project_config_validate,
            commit_journal,
            nasa_draft,
            evidence_lineage,
            agent_input_check,
            #[cfg(unix)]
            agent_input_assess,
            #[cfg(unix)]
            pytest_assess,
            #[cfg(unix)]
            context_operation,
        })
    })
}
