// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Thin Rust Host Capability Frame Mapper boundary.

#[cfg(feature = "linked-program")]
mod interface;
#[cfg(feature = "linked-program")]
mod jj;
#[cfg(feature = "linked-program")]
mod python;
mod registry;
#[cfg(feature = "linked-program")]
mod review;
#[cfg(feature = "linked-program")]
mod sysml;

pub use registry::{
    CapabilityError, CapabilityFrame, CapabilityId, HostCapability, HostCapabilityRegistry,
    HostEffectClass, HostReceipt,
};
