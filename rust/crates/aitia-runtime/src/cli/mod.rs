// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Ultra-thin CLI adapter layer.

mod dispatch;
mod flow;
mod jj;

pub use dispatch::run_cli;
use dispatch::{print_json, read_json_stdin, read_request};
