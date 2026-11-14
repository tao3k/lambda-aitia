// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Bind AITIA operations to the compiled Scheme program.

mod binding;
#[cfg(unix)]
mod context;
mod review_input;

#[cfg(unix)]
pub use binding::{
    AgentInputSupport, RecordedAgentInput, RecordedAgentInputObservation, ReplayAssessmentScope,
};
pub use binding::{AitiaProgram, with_linked_program};
#[cfg(unix)]
pub use context::{
    ContextDelivery, ContextDeliveryAttempt, ContextDeliveryReceipt, ContextTransportFailure,
    PendingContextDelivery,
};
