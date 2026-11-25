<!--
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-->

# Lambda Aitia Agent Architecture Rules

## Scheme / Rust Boundary (Thin Host Capability Frame Mapper)

- **Scheme (POO + ASCENT + FunFlow) owns all higher-order semantics**: workflow DAGs (`modules/workflow`), obligation reconciliation, scope merging, epistemic hypothesis competition, and effect authorization belong in Gerbil Scheme using native `gerbil-poo` prototypes, native `gerbil-ascent` relations, and strict nominal POO types (**zero `Any`** in typed workflow contracts).
- **Rust (`rust/crates/aitia-runtime`) is a thin Host Capability Frame Mapper**: Rust only hosts native OS/FFI boundaries (`jj-lib`, `opensysml`, `ring`, controlled subprocesses, `gerbil-scheme-rust` VM) and dispatches typed `CapabilityFrame` requests through `HostCapabilityRegistry` (`src/capability.rs`), returning raw attributable `HostReceipt` observations with `action_authorized == false`.
- **Do NOT add imperative workflow orchestration or policy mutation in Rust**:
  - Register new host effects as `HostCapability` implementations in `rust/crates/aitia-runtime/src/capability.rs` with explicit `HostEffectClass` (`HostRead` vs `FencedEffect`).
  - Never merge, rewrite, or synthesize Scheme policy objects (such as `naming.scopes`) in Rust; forward raw host receipts (`sysmlScopes`) to Scheme.
  - Legacy `cli.rs`, `cli_commit.rs`, and `cli_flow.rs` are locked under a monotonic line-count shrinkage ratchet enforced by `rust/crates/aitia-runtime/tests/unit/framework_boundary.rs` during `cargo test --workspace`.

## SysML v2 Single Source of Truth for Architectural Scopes

- Declare repository path ownership and commit scopes as native SysML v2 `CommitScope` parts in `dev/sysml/project-architecture.sysml`, projected at the recorded JJ cut via `opensysml`.
- Do NOT reintroduce a hand-maintained `naming.scopes` array into `.agents/aita/project.json` (mechanically forbidden by `framework_boundary.rs`).
