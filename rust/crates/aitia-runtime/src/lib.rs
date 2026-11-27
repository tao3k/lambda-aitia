// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! AITIA's owner-scoped execution boundary over the actual Scheme Runtime.
//! Scheme/POO remains the language for engineering declarations and semantics.
//! This boundary initializes a build-owned program; it issues no admission,
//! Human approval or effect authority and implements no replacement DSL.

mod capability;
pub use capability::{
    CapabilityError, CapabilityFrame, CapabilityId, HostCapability, HostCapabilityRegistry,
    HostEffectClass, HostReceipt,
};

#[cfg(any(feature = "linked-program", feature = "sysml"))]
mod limits;
#[cfg(any(feature = "linked-program", feature = "sysml"))]
use limits::MAX_REQUEST_BYTES;

#[cfg(feature = "linked-program")]
mod checks;
#[cfg(feature = "linked-program")]
mod cli;
#[cfg(feature = "linked-program")]
mod commit;
#[cfg(feature = "linked-program")]
mod project;
#[cfg(feature = "linked-program")]
mod protocol;
#[cfg(feature = "linked-program")]
mod review_provider;
#[cfg(feature = "linked-program")]
#[doc(hidden)]
pub use cli::run_cli;
#[cfg(feature = "linked-program")]
pub use commit::attestation::{
    ed25519_public_key_hex, enforce_sysml_tuf_policy, mint_release_attestation_bundle,
    mint_release_attestation_bundle_with_lineage, mint_release_attestation_bundle_with_quorum,
    mint_tuf_root_rotation, verify_attestation_lineage_chain, verify_release_attestation_bundle,
    verify_release_attestation_bundle_with_trust_root, verify_tuf_root_rotation_chain,
};
#[cfg(feature = "linked-program")]
pub use commit::audit::{verify_portable_audit_bundle, verify_portable_audit_bundle_json};
#[cfg(feature = "linked-program")]
pub use commit::dsse::{
    export_dsse_intoto_envelope_json, export_portable_audit_bundle_json,
    verify_dsse_intoto_envelope_json,
};
#[cfg(feature = "linked-program")]
pub use commit::merkle::{
    compute_links_merkle_root, generate_repo_merkle_proof, generate_repo_merkle_proof_json,
    verify_repo_merkle_proof, verify_repo_merkle_proof_json,
};
#[cfg(feature = "linked-program")]
pub use commit::transparency::{
    compute_log_root, generate_consistency_proof, generate_consistency_proof_json,
    verify_consistency_proof, verify_consistency_proof_json,
};
#[cfg(feature = "linked-program")]
pub use commit::witness::{
    detect_checkpoint_equivocation_json, sign_checkpoint_json, verify_checkpoint_transition_json,
    verify_signed_checkpoint_json,
};
#[cfg(feature = "linked-program")]
pub use protocol::{
    DEFAULT_WORKFLOW_CASE, MULTI_REPO_WORKFLOW_CASE, dispatch_host_frames_json,
    drive_multi_repo_protocol, drive_scheme_protocol, drive_single_repo_protocol,
    execute_multi_repo_protocol, execute_project_protocol, execute_project_protocol_fenced,
    host_capabilities_json, load_workspace_manifest,
};

#[cfg(feature = "linked-program")]
mod program;
#[cfg(feature = "linked-program")]
use program::with_program;

#[cfg(feature = "linked-program")]
#[allow(unsafe_code)]
mod linked;
#[cfg(all(unix, feature = "linked-program"))]
pub use linked::{
    AgentInputSupport, ContextDelivery, ContextDeliveryAttempt, ContextDeliveryReceipt,
    ContextTransportFailure, PendingContextDelivery, RecordedAgentInput,
    RecordedAgentInputObservation, ReplayAssessmentScope,
};
#[cfg(feature = "linked-program")]
pub use linked::{AitiaProgram, c_abi, with_linked_program};
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
#[cfg(all(unix, feature = "gitops"))]
pub use pytest::{RecordedPytestRun, run_recorded_pytest};

#[cfg(unix)]
mod source_tree;
#[cfg(unix)]
pub use source_tree::{FrozenSourceFile, FrozenWorkspace, capture_source_tree, decode_source_tree};

#[cfg(feature = "sysml")]
mod sysml;
#[cfg(feature = "sysml")]
pub use sysml::{
    RecordedSysmlError, SysmlCapabilitySpec, SysmlScopeProjection, SysmlWorkspaceRepo,
    extract_declared_capabilities, extract_declared_scopes, extract_declared_workspace_repos,
    parse_recorded_sysml, parse_sysml,
};
