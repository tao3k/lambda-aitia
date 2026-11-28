// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Test-only policy support. Production members depend on this crate only
//! through their development dependency edge, never the Runtime graph.

/// ASP's upstream gate implementation; no local style scanner is maintained.
#[doc(hidden)]
pub use asp_rust;

mod policy;
pub use policy::workspace_policy;
