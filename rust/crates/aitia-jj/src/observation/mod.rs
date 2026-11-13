// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Read-only workspace observations and project input discovery.

pub(crate) mod review_bookmarks;
pub(crate) mod workspace;
pub use review_bookmarks::{PushRemote, RecordedReviewBookmark, recorded_review_bookmarks};
pub use workspace::{
    JjObservationError, RecordedConfigurationAudit, RecordedPathChange, RecordedProjectSources,
    RecordedSource, RecordedTreeEntry, WorkspaceCut, audit_recorded_configuration,
    git_project_root, observe_project_sources, observe_recorded_sources, observe_workspace,
    read_recorded_file, read_recorded_files, read_revision_files, recorded_changes,
    recorded_revision_source_entries, recorded_sysml_paths,
};

#[cfg(all(test, feature = "real-jj"))]
mod tests;
