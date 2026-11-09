// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bind AITIA operations to the compiled Scheme program.

#[cfg(unix)]
use gerbil_scheme::{CollectionKind, ObjectKind, RootedSchemeObject};
use gerbil_scheme::{GerbilRuntime, LinkedGerbilProgram, LinkedObjectExport, NativeError};
use gerbil_scheme_sys::{GerbilGlobalState, GerbilModuleOrLink};

pub(crate) const MAX_REQUEST_BYTES: u64 = 4 * 1024 * 1024;

unsafe extern "C" {
    fn ___LNK_aitia__program(state: *mut GerbilGlobalState) -> *mut GerbilModuleOrLink;
    fn aitia_program_flow_graph(request: i64) -> i64;
    fn aitia_program_gitops_evaluate(request: i64) -> i64;
    fn aitia_program_org_contract_evaluate(request: i64) -> i64;
    fn aitia_program_project_config_validate(request: i64) -> i64;
    fn aitia_program_commit_journal(request: i64) -> i64;
    fn aitia_program_nasa_draft(request: i64) -> i64;
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
    runtime: &'runtime GerbilRuntime,
    flow_graph: LinkedObjectExport<'runtime>,
    gitops_evaluate: LinkedObjectExport<'runtime>,
    org_contract_evaluate: LinkedObjectExport<'runtime>,
    project_config_validate: LinkedObjectExport<'runtime>,
    commit_journal: LinkedObjectExport<'runtime>,
    nasa_draft: LinkedObjectExport<'runtime>,
    agent_input_check: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    agent_input_assess: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    pytest_assess: LinkedObjectExport<'runtime>,
    #[cfg(unix)]
    context_operation: LinkedObjectExport<'runtime>,
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

/// The transport distinguishes a definite pre-send failure from lost confirmation.
#[cfg(unix)]
#[derive(Debug)]
pub enum ContextTransportFailure<E> {
    NotSent(E),
    Indeterminate(E),
}

/// Result of sending a checked request from the live Lab Context catalog.
#[cfg(unix)]
#[derive(Debug)]
pub enum ContextDelivery<'runtime, T, E> {
    Refused,
    NotSent(E),
    Indeterminate {
        error: E,
        pending: PendingContextDelivery<'runtime>,
    },
    Delivered {
        result: T,
        receipt: ContextDeliveryReceipt<'runtime>,
    },
}

/// Correlation metadata for an actual transport attempt.
#[cfg(unix)]
#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContextDeliveryAttempt {
    project: String,
    identity: String,
    reference: String,
    body_digest: String,
}

#[cfg(unix)]
impl ContextDeliveryAttempt {
    pub fn project(&self) -> &str {
        &self.project
    }

    pub fn identity(&self) -> &str {
        &self.identity
    }

    pub fn body_digest(&self) -> &str {
        &self.body_digest
    }

    /// Encode inert correlation data for the application's write-ahead journal.
    /// Persist it before sending. The record carries no effect authority.
    ///
    /// # Errors
    /// Propagates serialization failures.
    pub fn recovery_record(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    fn matches(&self, identity: &str, body_digest: &str) -> bool {
        self.identity == identity && self.body_digest == body_digest
    }
}

/// An unconfirmed delivery. It holds no support receipt or send operation.
#[cfg(unix)]
#[derive(Debug)]
pub struct PendingContextDelivery<'runtime> {
    prepared: RootedSchemeObject<'runtime>,
    attempt: ContextDeliveryAttempt,
}

#[cfg(unix)]
impl<'runtime> PendingContextDelivery<'runtime> {
    pub fn attempt(&self) -> &ContextDeliveryAttempt {
        &self.attempt
    }

    /// Reconcile using the independently observed Provider acknowledgement.
    /// The application authenticates the acknowledgement before handing it over.
    ///
    /// # Errors
    /// Returns the still-pending delivery if the acknowledgement does not match.
    pub fn confirm(
        self,
        identity: &str,
        body_digest: &str,
    ) -> Result<ContextDeliveryReceipt<'runtime>, Self> {
        if !self.attempt.matches(identity, body_digest) {
            return Err(self);
        }
        Ok(ContextDeliveryReceipt {
            prepared: self.prepared,
            attempt: self.attempt,
        })
    }
}

/// The runtime-owned assessor of one completed Context delivery.
#[cfg(unix)]
#[derive(Debug)]
pub struct ContextDeliveryReceipt<'runtime> {
    prepared: RootedSchemeObject<'runtime>,
    attempt: ContextDeliveryAttempt,
}

#[cfg(unix)]
impl ContextDeliveryReceipt<'_> {
    pub fn attempt(&self) -> &ContextDeliveryAttempt {
        &self.attempt
    }
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
        self.call(&self.project_config_validate, request)
    }

    pub(crate) fn commit_journal(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.commit_journal, request)
    }

    pub(crate) fn nasa_draft(&self, request: &str) -> Result<String, NativeError> {
        self.call(&self.nasa_draft, request)
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

    /// Bind the linked application's Context catalog to its owning project.
    ///
    /// # Errors
    /// Refuses an empty identity or a different project after binding.
    #[cfg(unix)]
    pub fn bind_context_project(&self, project: &str) -> Result<(), NativeError> {
        self.call(
            &self.context_operation,
            &serde_json::json!({ "operation": "bind-project", "project": project }).to_string(),
        )?;
        Ok(())
    }

    #[cfg(unix)]
    fn context_project(&self) -> Result<String, NativeError> {
        self.call(&self.context_operation, r#"{"operation":"project"}"#)
    }

    /// Publish a source to the linked application's Lab Context catalog.
    ///
    /// # Errors
    /// Propagates Org Contract, generation and publication failures.
    #[cfg(unix)]
    pub fn publish_context_source(
        &self,
        source_id: &str,
        generation: u64,
        source: &str,
    ) -> Result<(), NativeError> {
        self.call(
            &self.context_operation,
            &serde_json::json!({
                "operation": "publish",
                "sourceId": source_id,
                "generation": generation,
                "source": source,
            })
            .to_string(),
        )?;
        Ok(())
    }

    /// Withdraw a source in the same Lab Context catalog.
    ///
    /// # Errors
    /// Propagates invalid source and generation errors.
    #[cfg(unix)]
    pub fn withdraw_context_source(
        &self,
        source_id: &str,
        generation: u64,
    ) -> Result<(), NativeError> {
        self.call(
            &self.context_operation,
            &serde_json::json!({
                "operation": "withdraw",
                "sourceId": source_id,
                "generation": generation,
            })
            .to_string(),
        )?;
        Ok(())
    }

    /// Run the Lab Context Query over an Org Element identified by its ID.
    ///
    /// # Errors
    /// Propagates source, Query and Scheme transport failures.
    #[cfg(unix)]
    pub fn observe_context_element(
        &self,
        source_id: &str,
        element_id: &str,
    ) -> Result<String, NativeError> {
        self.call(
            &self.context_operation,
            &serde_json::json!({
                "operation": "observe",
                "sourceId": source_id,
                "elementId": element_id,
            })
            .to_string(),
        )
    }

    /// Capture the live Lab catalog using its inert recovery codec.
    /// The application owns durable storage and the current checkpoint identity.
    ///
    /// # Errors
    /// Propagates recovery encoding and size-limit failures.
    #[cfg(unix)]
    pub fn context_checkpoint(&self) -> Result<String, NativeError> {
        self.call(&self.context_operation, r#"{"operation":"checkpoint"}"#)
    }

    /// Restore the owner-selected checkpoint into a fresh linked program.
    /// This restores Query observations. Delivery receipts remain process-local.
    ///
    /// # Errors
    /// Rejects digest mismatch, invalid or oversized recovery data, or an
    /// attempt to overwrite a live catalog.
    #[cfg(unix)]
    pub fn restore_context_checkpoint(
        &self,
        checkpoint: &str,
        expected_digest: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if checkpoint.len() > MAX_REQUEST_BYTES as usize
            || crate::source_tree::sha256(checkpoint.as_bytes()) != expected_digest
        {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "checkpoint does not match the current owner-selected digest",
            )
            .into());
        }
        self.call(
            &self.context_operation,
            &serde_json::json!({
                "operation": "restore",
                "checkpoint": checkpoint,
            })
            .to_string(),
        )?;
        Ok(())
    }

    /// Send the exact request body checked against the live Context observation.
    /// The application supplies a distinct attempt identity and owns the
    /// transport. An indeterminate result needs an independently observed
    /// acknowledgement before assessment.
    ///
    /// # Errors
    /// Propagates Scheme preparation and transport-boundary conversion errors.
    #[cfg(unix)]
    pub fn deliver_context_request<T, E>(
        &self,
        reference: &str,
        attempt_id: &str,
        settings: &serde_json::Map<String, serde_json::Value>,
        input: &serde_json::Value,
        send: impl FnOnce(&ContextDeliveryAttempt, &str) -> Result<T, ContextTransportFailure<E>>,
    ) -> Result<ContextDelivery<'runtime, T, E>, NativeError> {
        if attempt_id.is_empty()
            || attempt_id.len() > 128
            || !attempt_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
        {
            return Ok(ContextDelivery::Refused);
        }
        let command = serde_json::json!({
            "operation": "prepare",
            "reference": reference,
            "settings": settings,
            "input": input,
        });
        let Some(prepared) = self.prepare_context_command(&command)? else {
            return Ok(ContextDelivery::Refused);
        };
        let prepared = prepared.into_collection(CollectionKind::Vector)?;
        let body = prepared
            .element(0)?
            .into_string()?
            .to_string()
            .into_result()?;
        let attempt = ContextDeliveryAttempt {
            project: self.context_project()?,
            identity: attempt_id.to_owned(),
            reference: reference.to_owned(),
            body_digest: crate::source_tree::sha256(body.as_bytes()),
        };
        Ok(match send(&attempt, &body) {
            Ok(result) => ContextDelivery::Delivered {
                result,
                receipt: ContextDeliveryReceipt {
                    prepared: prepared.into_object(),
                    attempt,
                },
            },
            Err(ContextTransportFailure::NotSent(error)) => ContextDelivery::NotSent(error),
            Err(ContextTransportFailure::Indeterminate(error)) => ContextDelivery::Indeterminate {
                error,
                pending: PendingContextDelivery {
                    prepared: prepared.into_object(),
                    attempt,
                },
            },
        })
    }

    /// Reconcile a pre-send record with an independently authenticated Provider
    /// observation after restoring the Lab catalog. The application supplies the
    /// trusted record digest and the exact body retained by the Provider.
    ///
    /// The returned receipt requires a current source. This operation has no
    /// transport callback and cannot send or renew an old Host lease.
    ///
    /// # Errors
    /// Rejects invalid recovery data or propagates failures from Scheme.
    #[cfg(unix)]
    pub fn recover_context_delivery(
        &self,
        record: &str,
        expected_record_digest: &str,
        provider_body: &str,
        provider_attempt: &str,
        provider_body_digest: &str,
    ) -> Result<Option<ContextDeliveryReceipt<'runtime>>, Box<dyn std::error::Error>> {
        if record.len() > MAX_REQUEST_BYTES as usize
            || provider_body.len() > MAX_REQUEST_BYTES as usize
            || crate::source_tree::sha256(record.as_bytes()) != expected_record_digest
        {
            return Ok(None);
        }
        let attempt: ContextDeliveryAttempt = serde_json::from_str(record)?;
        if attempt.project() != self.context_project()?
            || !attempt.matches(provider_attempt, provider_body_digest)
            || crate::source_tree::sha256(provider_body.as_bytes()) != provider_body_digest
        {
            return Ok(None);
        }
        let command = serde_json::json!({
            "operation": "recover-delivery",
            "reference": attempt.reference,
            "body": provider_body,
        });
        Ok(self
            .prepare_context_command(&command)?
            .map(|prepared| ContextDeliveryReceipt { prepared, attempt }))
    }

    #[cfg(unix)]
    fn prepare_context_command(
        &self,
        command: &serde_json::Value,
    ) -> Result<Option<RootedSchemeObject<'runtime>>, NativeError> {
        let command = self
            .runtime
            .string_from_utf8(&command.to_string())?
            .into_object();
        let prepared = self.context_operation.call(&command).into_result()?;
        Ok((prepared.as_ref().kind()? != ObjectKind::Boolean).then_some(prepared))
    }

    /// Recheck the original live Context and assess the delivered request.
    ///
    /// # Errors
    /// Propagates Scheme and assessment decoding failures.
    #[cfg(unix)]
    pub fn assess_context_delivery(
        &self,
        receipt: &ContextDeliveryReceipt<'runtime>,
    ) -> Result<AgentInputSupport, Box<dyn std::error::Error>> {
        let response = self
            .context_operation
            .call(&receipt.prepared)
            .into_result()?
            .into_string()?
            .to_string()
            .into_result()?;
        match serde_json::from_str::<Option<serde_json::Value>>(&response)? {
            Some(assessment) => Ok(AgentInputSupport::Assessed(assessment)),
            None => Ok(AgentInputSupport::Reopened),
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
        org_source: &str,
        run: &crate::RecordedPytestRun,
    ) -> Result<Option<serde_json::Value>, Box<dyn std::error::Error>> {
        self.assess_pytest_replay(scope, Some(org_source), run)
    }

    #[cfg(unix)]
    pub(crate) fn assess_pytest_replay(
        &self,
        scope: ReplayAssessmentScope<'_>,
        org_source: Option<&str>,
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
            "source": org_source,
            "generateOrg": org_source.is_none(),
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
        // SAFETY: Scheme owns the rooted request and result.
        let commit_journal = unsafe { runtime.bind_object_export(aitia_program_commit_journal) }?;
        // SAFETY: Scheme owns the rooted request and result.
        let nasa_draft = unsafe { runtime.bind_object_export(aitia_program_nasa_draft) }?;
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
