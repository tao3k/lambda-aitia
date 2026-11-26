// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#[cfg(feature = "extension-module")]
mod python;

#[cfg(feature = "extension-module")]
pub use aitia_runtime::c_abi::{
    AitiaBuffer, AitiaSessionHandle, aitia_abi_version, aitia_buffer_free,
    aitia_dispatch_host_frames, aitia_host_capabilities, aitia_session_call, aitia_session_close,
    aitia_session_start,
};
