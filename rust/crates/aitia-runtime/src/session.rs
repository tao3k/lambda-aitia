// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Own the linked Scheme runtime and route calls through its owner thread.

use crate::AitiaProgram;
use gerbil_scheme::NativeError;
use std::sync::mpsc::{self, SyncSender};
use std::thread::{self, JoinHandle};

type Task = Box<dyn FnOnce(&AitiaProgram<'_>) + Send + 'static>;

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

/// Reuses one bridge-owned runtime on its own thread. Requests rendezvous with
/// the owner, and only Rust-owned values cross threads.
pub struct AitiaSession {
    sender: Option<SyncSender<Task>>,
    owner: Option<JoinHandle<Result<(), NativeError>>>,
}

impl AitiaSession {
    /// Start the process's one-shot linked program and wait for initialization.
    ///
    /// # Errors
    ///
    /// Returns an error if the thread or Scheme runtime could not start.
    pub fn start() -> Result<Self, SessionError> {
        let (sender, requests) = mpsc::sync_channel::<Task>(0);
        let (ready, initialized) = mpsc::sync_channel(0);
        let owner = thread::Builder::new()
            .name("aitia-scheme-owner".into())
            .spawn(move || {
                crate::with_linked_program(|program| {
                    if ready.send(()).is_err() {
                        return Ok(());
                    }
                    for task in requests {
                        task(&program);
                    }
                    Ok(())
                })
            })
            .map_err(SessionError::Spawn)?;
        let mut session = Self {
            sender: Some(sender),
            owner: Some(owner),
        };
        if initialized.recv().is_err() {
            session.join()?;
            return Err(SessionError::OwnerStopped);
        }
        Ok(session)
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

    /// Execute one Scheme-owned 4-state inversion-of-control workflow protocol step.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn workflow_protocol_step(&self, payload: String) -> Result<String, SessionError> {
        self.call_string(move |program| program.workflow_protocol_step(&payload))
    }

    /// End the session and wait for Scheme cleanup.
    ///
    /// # Errors
    ///
    /// Returns an error if the owner failed.
    pub fn close(mut self) -> Result<(), SessionError> {
        self.join()
    }

    fn call_string<F>(&self, operation: F) -> Result<String, SessionError>
    where
        F: FnOnce(&AitiaProgram<'_>) -> Result<String, NativeError> + Send + 'static,
    {
        self.execute(operation)?.map_err(SessionError::Scheme)
    }

    fn join(&mut self) -> Result<(), SessionError> {
        drop(self.sender.take());
        if let Some(owner) = self.owner.take() {
            owner
                .join()
                .map_err(|_| SessionError::OwnerPanicked)?
                .map_err(SessionError::Scheme)?;
        }
        Ok(())
    }
}

impl Drop for AitiaSession {
    fn drop(&mut self) {
        let _ = self.join();
    }
}
