// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        // Wheel repair rewrites dylib load commands with longer packaged paths.
        println!("cargo:rustc-link-arg-cdylib=-Wl,-headerpad_max_install_names");
    }
}
