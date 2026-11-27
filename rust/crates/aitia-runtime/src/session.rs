// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Own the linked Scheme runtime and route calls through its single process-global owner thread.

use crate::AitiaProgram;
use gerbil_scheme::NativeError;
use std::sync::mpsc::{self, SyncSender};
use std::sync::{Arc, OnceLock};
use std::thread;

type Task = Box<dyn FnOnce(&AitiaProgram<'_>) + Send + 'static>;

static SHARED_OWNER: OnceLock<Result<Arc<SyncSender<Task>>, String>> = OnceLock::new();

fn shared_sender() -> Result<Arc<SyncSender<Task>>, SessionError> {
    let init = SHARED_OWNER.get_or_init(|| {
        let (sender, requests) = mpsc::sync_channel::<Task>(0);
        let (ready, initialized) = mpsc::sync_channel(0);
        thread::Builder::new()
            .name("aitia-scheme-owner".into())
            .spawn(move || {
                let _ = crate::with_linked_program(|program| {
                    if ready.send(()).is_err() {
                        return Ok(());
                    }
                    for task in requests {
                        task(&program);
                    }
                    Ok(())
                });
            })
            .map_err(|e| format!("could not start AITIA owner: {e}"))?;
        if initialized.recv().is_err() {
            return Err("AITIA owner stopped during initialization".to_owned());
        }
        Ok(Arc::new(sender))
    });
    match init {
        Ok(sender) => Ok(Arc::clone(sender)),
        Err(msg) => Err(SessionError::Spawn(std::io::Error::other(msg.clone()))),
    }
}

/// Errors at the Rust session boundary.
#[derive(Debug)]
pub enum SessionError {
    Spawn(std::io::Error),
    Scheme(NativeError),
    OwnerStopped,
    OwnerPanicked,
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Spawn(error) => write!(formatter, "could not start AITIA owner: {error}"),
            Self::Scheme(error) => write!(formatter, "{error}"),
            Self::OwnerStopped => formatter.write_str("AITIA owner stopped"),
            Self::OwnerPanicked => formatter.write_str("AITIA owner panicked"),
        }
    }
}

impl std::error::Error for SessionError {}

/// Reuses the process's single Gambit runtime on its dedicated owner thread.
/// Multiple sessions and free functions share the live owner safely without
/// ever attempting a second Gambit initialization.
pub struct AitiaSession {
    sender: Option<Arc<SyncSender<Task>>>,
}

impl AitiaSession {
    /// Obtain a handle bound to the process's single live linked Scheme owner.
    ///
    /// # Errors
    ///
    /// Returns an error if the owner thread or Scheme runtime could not start.
    pub fn start() -> Result<Self, SessionError> {
        Ok(Self {
            sender: Some(shared_sender()?),
        })
    }

    /// Execute an operation against the live linked Scheme program on its owner
    /// thread without re-initializing the Gambit runtime.
    ///
    /// # Errors
    ///
    /// Returns `SessionError::OwnerStopped` if the session has closed or failed.
    pub fn execute<T, F>(&self, operation: F) -> Result<T, SessionError>
    where
        T: Send + 'static,
        F: FnOnce(&AitiaProgram<'_>) -> T + Send + 'static,
    {
        let (reply, response) = mpsc::sync_channel(0);
        let task: Task = Box::new(move |program| {
            let _ = reply.send(operation(program));
        });
        self.sender
            .as_ref()
            .ok_or(SessionError::OwnerStopped)?
            .send(task)
            .map_err(|_| SessionError::OwnerStopped)?;
        response.recv().map_err(|_| SessionError::OwnerStopped)
    }

    /// Read the published SDLC graph.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn flow_graph(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.flow_graph(&payload))
    }

    /// Evaluate a GitOps change using the published Scenario.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn gitops_evaluate(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.gitops_evaluate(&payload))
    }

    /// Evaluate an Orgize Contract over supplied Element facts.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn org_contract_evaluate(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.org_contract_evaluate(&payload))
    }

    /// Validate a recorded project configuration envelope through the Yuanxu Contract.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn project_config_validate(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.project_config_validate(&payload))
    }

    /// Project an evidence lineage graph (and optional GQL query selection) over verified JJ facts.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn evidence_lineage(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.evidence_lineage(&payload))
    }

    /// Reconcile a GitOps/SDLC ObligationGraph through native ASCENT and FunFlow CAS DAG.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn workflow_reconcile(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.workflow_reconcile(&payload))
    }

    /// Execute one Scheme-owned 5-state inversion-of-control workflow protocol step.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn workflow_protocol_step(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.workflow_protocol_step(&payload))
    }

    /// Evaluate detached sidecar NASA obligations and Native AI / Marlin handoffs via Scheme ASCENT.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn sidecar_audit_assess(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.sidecar_audit_assess(&payload))
    }

    /// Evaluate unified Git diffs with composable POO subdomain rule packs and temporal causality via Scheme.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn diff_defense_audit(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.diff_defense_audit(&payload))
    }

    /// Drive the Scheme-owned single-repository 5-state IoC protocol against `directory` inside
    /// this live session without re-initializing the Gambit runtime.
    ///
    /// # Errors
    ///
    /// Returns a session or protocol failure string when observation, overlay parsing,
    /// capability dispatch, or evidence verification fails.
    pub fn drive_protocol(
        &self,
        directory: String,
        case_id: String,
        overlay_json: Option<String>,
        execute_fenced: bool,
    ) -> Result<String, String> {
        let overlay: Option<serde_json::Value> = overlay_json
            .as_deref()
            .map(serde_json::from_str)
            .transpose()
            .map_err(|error| error.to_string())?;
        let step = self
            .execute(move |program| {
                crate::drive_single_repo_protocol(
                    program,
                    std::path::Path::new(&directory),
                    &case_id,
                    overlay.as_ref(),
                    execute_fenced,
                )
                .map_err(|error| error.to_string())
            })
            .map_err(|error| error.to_string())??;
        serde_json::to_string(&step).map_err(|error| error.to_string())
    }

    /// Drive the Scheme-owned multi-repository GitOps 5-state IoC protocol inside this
    /// live session without re-initializing the Gambit runtime.
    ///
    /// # Errors
    ///
    /// Returns a session or protocol failure string when the manifest is invalid,
    /// capability dispatch fails, or the session is closed.
    pub fn drive_multi_repo_protocol(
        &self,
        request_json: String,
        execute_fenced: bool,
    ) -> Result<String, String> {
        let request: serde_json::Value =
            serde_json::from_str(&request_json).map_err(|error| error.to_string())?;
        let step = self
            .execute(move |program| {
                crate::drive_multi_repo_protocol(program, &request, execute_fenced)
                    .map_err(|error| error.to_string())
            })
            .map_err(|error| error.to_string())??;
        serde_json::to_string(&step).map_err(|error| error.to_string())
    }

    /// Release this handle; subsequent calls on this handle fail with `OwnerStopped`.
    ///
    /// # Errors
    ///
    /// Returns `Ok(())` after releasing the handle.
    pub fn close(mut self) -> Result<(), SessionError> {
        drop(self.sender.take());
        Ok(())
    }

    fn call_string<F>(&self, operation: F) -> Result<String, SessionError>
    where
        F: FnOnce(&AitiaProgram<'_>) -> Result<String, NativeError> + Send + 'static,
    {
        self.execute(operation)?.map_err(SessionError::Scheme)
    }
}

impl Drop for AitiaSession {
    fn drop(&mut self) {
        drop(self.sender.take());
    }
}
