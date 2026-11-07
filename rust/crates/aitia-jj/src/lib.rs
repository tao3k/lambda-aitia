// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

mod observation;
pub use observation::{
    JjObservationError, WorkspaceCut, git_project_root, observe_project_manifest,
    observe_workspace, read_recorded_file,
};
