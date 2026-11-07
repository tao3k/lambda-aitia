// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Read-only workspace observations and project input discovery.

mod workspace;
pub use workspace::{
    JjObservationError, WorkspaceCut, git_project_root, observe_project_manifest,
    observe_workspace, read_recorded_file, recorded_sysml_paths,
};

#[cfg(all(test, feature = "real-jj"))]
mod tests;
