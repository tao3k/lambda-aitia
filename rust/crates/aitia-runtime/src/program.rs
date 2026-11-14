// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Scope actual Scheme program execution to its bridge-owned Runtime lifetime.
use gerbil_scheme::{GerbilRuntime, LinkedGerbilProgram, NativeError};

/// Execute an application operation while the linked Scheme program is alive.
///
/// The bridge owns ABI checks, GC roots, owner affinity and ordinary cleanup.
/// A result cannot borrow the local runtime. Callers must supply a qualified
/// program and enforce the selected operation's own admission/authority rules.
/// Initialization is one-shot according to the upstream runtime contract;
/// this function does not make a second initialization or retry safe.
///
/// # Errors
///
/// Propagates initialization or operation errors without substituting a result
/// or skipping the runtime's ordinary resource destruction.
pub fn with_program<T>(
    program: LinkedGerbilProgram,
    operation: impl for<'runtime> FnOnce(&'runtime GerbilRuntime) -> Result<T, NativeError>,
) -> Result<T, NativeError> {
    let runtime = GerbilRuntime::initialize_program(program)?;
    operation(&runtime)
}
