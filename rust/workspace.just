# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

# Test the default Rust workspace, including the development-only ASP gate.
[group('rust')]
test-rust-workspace:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --workspace --lib --tests --manifest-path rust/Cargo.toml

[group('rust')]
check-rust-format:
    cargo fmt --all --check --manifest-path rust/Cargo.toml

[group('rust')]
check-rust-lint:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo clippy --locked --workspace --all-targets --manifest-path rust/Cargo.toml -- -D warnings
