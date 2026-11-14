// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

mod observation;
pub use observation::{
    JjObservationError, RecordedConfigurationAudit, RecordedPathChange, RecordedProjectSources,
    RecordedReviewBookmark, RecordedSource, RecordedTreeEntry, WorkspaceCut,
    audit_recorded_configuration, git_project_root, observe_project_sources,
    observe_recorded_sources, observe_workspace, read_recorded_file, read_recorded_files,
    read_revision_files, recorded_changes, recorded_review_bookmarks,
    recorded_revision_source_entries, recorded_sysml_paths,
};

mod description;
pub use description::{
    AppliedDescriptionEvidence, DescriptionOrigin, DescriptionOutcome, DescriptionReceipt,
    DescriptionRecovery, PreparedDescription, observe_description_origin, prepare_description,
    prepare_reviewed_description, read_applied_description_evidence, reconcile_description,
    reopen_description, reopen_reviewed_description,
};

pub use observation::PushRemote;

mod push;
pub use push::{PushReceipt, push_reviewed_description, recover_reviewed_push};
