// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! AITIA's owner-scoped execution boundary over the actual Scheme Runtime.
//! Scheme/POO remains the language for engineering declarations and semantics.
//! This boundary initializes a build-owned program; it issues no admission,
//! Human approval or effect authority and implements no replacement DSL.

#[cfg(feature = "linked-program")]
mod cli;
#[cfg(feature = "linked-program")]
#[doc(hidden)]
pub use cli::run_cli;

#[cfg(feature = "linked-program")]
mod program;
#[cfg(feature = "linked-program")]
use program::with_program;

#[cfg(feature = "linked-program")]
#[allow(unsafe_code)]
mod linked;
#[cfg(feature = "linked-program")]
pub use linked::{AitiaProgram, with_linked_program};
#[cfg(feature = "linked-program")]
mod session;
#[cfg(feature = "linked-program")]
pub use session::{AitiaSession, SessionError};

#[cfg(unix)]
mod org_edit;
#[cfg(unix)]
pub use org_edit::{OrgEdit, OrgEditReview};

#[cfg(unix)]
mod pytest;
#[cfg(unix)]
pub use pytest::{PytestExit, PytestReport, PytestRun, PytestVerdict, run_frozen_pytest};

#[cfg(unix)]
mod source_tree;
#[cfg(unix)]
pub use source_tree::{FrozenSourceFile, FrozenWorkspace, capture_source_tree, decode_source_tree};

#[cfg(feature = "sysml")]
mod sysml;
#[cfg(feature = "sysml")]
pub use sysml::{RecordedSysmlError, parse_recorded_sysml, parse_sysml};
