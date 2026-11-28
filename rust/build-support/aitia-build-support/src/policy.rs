// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Shared policy over Cargo's own workspace membership and dependency graph.

/// Keep upstream blocking and advisory enforcement unchanged.
#[must_use]
pub fn workspace_policy() -> asp_rust::AspRustWorkspacePolicy {
    asp_rust::AspRustWorkspacePolicy::new("aitia", asp_rust::default_asp_rust_config())
}

/// Mount ASP's workspace admission in a member's test dependency graph.
#[macro_export]
macro_rules! asp_workspace_policy_gate {
    () => {
        $crate::asp_rust::asp_rust_workspace_dev_gate!(
            mode = deny,
            policy = $crate::workspace_policy()
        );
    };
}
