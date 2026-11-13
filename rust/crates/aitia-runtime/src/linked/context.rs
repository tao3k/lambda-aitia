// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Context catalog access and delivery reconciliation on the linked Scheme owner.

use gerbil_scheme::{CollectionKind, NativeError, ObjectKind, RootedSchemeObject};

use super::{AgentInputSupport, AitiaProgram};
use crate::MAX_REQUEST_BYTES;

/// The transport distinguishes a definite pre-send failure from lost confirmation.
#[derive(Debug)]
pub enum ContextTransportFailure<E> {
    NotSent(E),
    Indeterminate(E),
}

/// Result of sending a checked request from the live Lab Context catalog.
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
#[derive(Debug, serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ContextDeliveryAttempt {
    project: String,
    identity: String,
    reference: String,
    body_digest: String,
}

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
#[derive(Debug)]
pub struct PendingContextDelivery<'runtime> {
    prepared: RootedSchemeObject<'runtime>,
    attempt: ContextDeliveryAttempt,
}

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
#[derive(Debug)]
pub struct ContextDeliveryReceipt<'runtime> {
    prepared: RootedSchemeObject<'runtime>,
    attempt: ContextDeliveryAttempt,
}

impl ContextDeliveryReceipt<'_> {
    pub fn attempt(&self) -> &ContextDeliveryAttempt {
        &self.attempt
    }
}

impl<'runtime> AitiaProgram<'runtime> {
    /// Bind the linked application's Context catalog to its owning project.
    ///
    /// # Errors
    /// Refuses an empty identity or a different project after binding.
    pub fn bind_context_project(&self, project: &str) -> Result<(), NativeError> {
        self.call(
            &self.context_operation,
            &serde_json::json!({ "operation": "bind-project", "project": project }).to_string(),
        )?;
        Ok(())
    }

    fn context_project(&self) -> Result<String, NativeError> {
        self.call(&self.context_operation, r#"{"operation":"project"}"#)
    }

    /// Publish a source to the linked application's Lab Context catalog.
    ///
    /// # Errors
    /// Propagates Org Contract, generation and publication failures.
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
    pub fn context_checkpoint(&self) -> Result<String, NativeError> {
        self.call(&self.context_operation, r#"{"operation":"checkpoint"}"#)
    }

    /// Restore the owner-selected checkpoint into a fresh linked program.
    /// This restores Query observations. Delivery receipts remain process-local.
    ///
    /// # Errors
    /// Rejects digest mismatch, invalid or oversized recovery data, or an
    /// attempt to overwrite a live catalog.
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
}
