// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Own the linked Scheme runtime and route calls through its owner thread.

use gerbil_scheme::NativeError;
use std::sync::mpsc::{self, SyncSender};
use std::thread::{self, JoinHandle};

type Response = Result<String, NativeError>;

enum Operation {
    FlowGraph,
    GitOpsEvaluate,
    OrgContractEvaluate,
}

struct Request {
    operation: Operation,
    payload: String,
    reply: SyncSender<Response>,
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

/// Reuses one bridge-owned runtime on its own thread. Requests rendezvous with
/// the owner, and only Rust-owned strings cross threads.
pub struct AitiaSession {
    sender: Option<SyncSender<Request>>,
    owner: Option<JoinHandle<Result<(), NativeError>>>,
}

impl AitiaSession {
    /// Start the process's one-shot linked program and wait for initialization.
    ///
    /// # Errors
    ///
    /// Returns an error if the thread or Scheme runtime could not start.
    pub fn start() -> Result<Self, SessionError> {
        let (sender, requests) = mpsc::sync_channel::<Request>(0);
        let (ready, initialized) = mpsc::sync_channel(0);
        let owner = thread::Builder::new()
            .name("aitia-scheme-owner".into())
            .spawn(move || {
                crate::with_linked_program(|program| {
                    if ready.send(()).is_err() {
                        return Ok(());
                    }
                    for request in requests {
                        let response = match request.operation {
                            Operation::FlowGraph => program.flow_graph(&request.payload),
                            Operation::GitOpsEvaluate => program.gitops_evaluate(&request.payload),
                            Operation::OrgContractEvaluate => {
                                program.org_contract_evaluate(&request.payload)
                            }
                        };
                        let _ = request.reply.send(response);
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

    /// Read the published SDLC graph.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn flow_graph(&self, payload: String) -> Result<String, SessionError> {
        self.call(Operation::FlowGraph, payload)
    }

    /// Evaluate a GitOps change using the published Scenario.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn gitops_evaluate(&self, payload: String) -> Result<String, SessionError> {
        self.call(Operation::GitOpsEvaluate, payload)
    }

    /// Evaluate an Orgize Contract over supplied Element facts.
    ///
    /// # Errors
    ///
    /// Returns an operation or owner failure.
    pub fn org_contract_evaluate(&self, payload: String) -> Result<String, SessionError> {
        self.call(Operation::OrgContractEvaluate, payload)
    }

    /// End the session and wait for Scheme cleanup.
    ///
    /// # Errors
    ///
    /// Returns an error if the owner failed.
    pub fn close(mut self) -> Result<(), SessionError> {
        self.join()
    }

    fn call(&self, operation: Operation, payload: String) -> Result<String, SessionError> {
        let (reply, response) = mpsc::sync_channel(0);
        self.sender
            .as_ref()
            .ok_or(SessionError::OwnerStopped)?
            .send(Request {
                operation,
                payload,
                reply,
            })
            .map_err(|_| SessionError::OwnerStopped)?;
        response
            .recv()
            .map_err(|_| SessionError::OwnerStopped)?
            .map_err(SessionError::Scheme)
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
