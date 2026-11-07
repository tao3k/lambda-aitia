# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# The SDK derives its default from the host; preserve caller-supplied limits.
# GAMBOPT heap limits apply per process, not to the whole compiler tree.
export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", `gxi -:max-heap=2G -e '(display (##core-count))'`)

self_root := justfile_directory()
export GERBIL_PATH := env_var_or_default("GERBIL_PATH", self_root + "/.gerbil")
export GERBIL_LOADPATH := env_var_or_default("GERBIL_LOADPATH", self_root + ":" + GERBIL_PATH + "/lib")
native_root := GERBIL_PATH + "/native"
gerbil_env := if os() == "macos" { "env -u SDKROOT" } else { "env" }
gerbil_test_runtime_options := "-:max-heap=512M"
export UV_CACHE_DIR := env_var_or_default("UV_CACHE_DIR", self_root + "/.cache/uv")
darwin_cc := if os() == "macos" { "/usr/bin/cc" } else { "cc" }
darwin_target := if os() == "macos" { "26.0" } else { "" }
export CC := env_var_or_default("CC", darwin_cc)
export MACOSX_DEPLOYMENT_TARGET := env_var_or_default("MACOSX_DEPLOYMENT_TARGET", darwin_target)

[group('discovery')]
default:
    @just --list

import 'rust/workspace.just'

# Exercise the pinned SDK against a local OpenSysML service.
[group('rust')]
test-sysml-model:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features sysml --test sysml_model

# Exercise the linked CLI against a real recorded manifest and SysML service.
[group('rust')]
test-project-sysml: stage-rust-program
    test -x "${AITIA_JJ_BIN:?set AITIA_JJ_BIN}"
    gerbil_home="$({{ gerbil_env }} gxi -e '(displayln (gerbil-home))')"; GERBIL_HOME="$gerbil_home" AITIA_PROGRAM_MANIFEST='{{ native_root }}/aitia-program/program.json' {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --test sysml_model

[group('rust')]
test-jj-observation:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-jj --features real-jj --test workspace_cut

[group('check')]
test-jj-commit-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    export AITIA_JJ_REPLAY_CUTS="$scratch/cuts.json"
    just test-jj-observation
    just test-proof-scheme jj-commit-evidence-test.ss

# Build this Gerbil package against the installed Agentic AI Lab mechanisms.
[group('build')]
build-scheme:
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --signal=TERM --kill-after=5s 180s gerbil build

[group('build')]
build-user-interface:
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} ./build.ss compile --modules github-gitops

# Stage the bridge-owned AOT inputs using the installed Scheme/Rust bridge.
[group('rust')]
stage-rust-program: build-user-interface
    mkdir -p '{{ native_root }}/aitia-program'
    AITIA_PROGRAM_OUTPUT='{{ native_root }}/aitia-program' {{ gerbil_env }} gxi -e '(import :gerbil/compiler :gerbil-scheme-rust/scheme/program-build) (for-each (lambda (source) (compile-module source [output-dir: (path-expand "lib" (getenv "GERBIL_PATH")) invoke-gsc: #t optimize: #t static: #t])) ["init.ss" "bindings/operations.ss" "rust/scheme/program.ss"]) (gerbil-rs-stage-program "rust/scheme/program.ss" (getenv "AITIA_PROGRAM_OUTPUT"))'

[group('rust')]
build-rust-cli features="linked-program": stage-rust-program
    gerbil_home="$({{ gerbil_env }} gxi -e '(displayln (gerbil-home))')"; GERBIL_HOME="$gerbil_home" AITIA_PROGRAM_MANIFEST='{{ native_root }}/aitia-program/program.json' {{ gerbil_env }} cargo build --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features {{ quote(features) }} --bin aitia

[group('rust')]
test-rust-linked-program: stage-rust-program
    gerbil_home="$({{ gerbil_env }} gxi -e '(displayln (gerbil-home))')"; GERBIL_HOME="$gerbil_home" AITIA_PROGRAM_MANIFEST='{{ native_root }}/aitia-program/program.json' {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program --test linked_program -- --nocapture

[group('rust')]
build-rust-wheel profile="release" out=(native_root + "/aitia-wheels"): stage-rust-program
    gerbil_home="$({{ gerbil_env }} gxi -e '(displayln (gerbil-home))')"; cd rust/crates/aitia-python && GERBIL_HOME="$gerbil_home" AITIA_PROGRAM_MANIFEST='{{ native_root }}/aitia-program/program.json' {{ gerbil_env }} maturin build --profile {{ quote(profile) }} --locked --auditwheel repair --out {{ quote(out) }}

# Exercise a Maturin wheel outside the checkout with the paired Gerbil SDK.
[group('rust')]
check-installed-rust-wheel wheel:
    #!/usr/bin/env bash
    set -euo pipefail
    wheel={{ quote(wheel) }}
    wheel="$(cd "$(dirname "$wheel")" && pwd -P)/$(basename "$wheel")"
    export GERBIL_HOME="$({{ gerbil_env }} gxi -e '(displayln (gerbil-home))')"
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    cd "$scratch"
    python3 -m venv venv
    venv/bin/python -m pip --disable-pip-version-check --no-cache-dir install --no-index --no-deps "$wheel"
    args=()
    if [[ -n "${AITIA_PYTEST_PYTHON:-}" ]]; then args+=("$AITIA_PYTEST_PYTHON"); fi
    timeout --foreground --signal=TERM --kill-after=3s 60s venv/bin/python -I "{{ self_root }}/rust/crates/aitia-python/tests/integration/wheel_smoke.py" "${args[@]}"

# Run one Aitia-owned Scheme test module.
[group('test')]
test-scheme module="sdlc":
    #!/usr/bin/env bash
    set -euo pipefail
    module={{ quote(module) }}
    test -d "t/$module"
    # Bound four child heaps at 2 GiB each, plus the 1 GiB launcher.
    if [[ "$module" == sdlc ]] &&
       ! [[ "$GERBIL_BUILD_CORES" =~ ^[1-4]$ ]]; then
      export GERBIL_BUILD_CORES=4
    fi
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s gxi -:max-heap=1G ./run-test.ss "t/$module"

# Run the tests published by a selected Yuanxu Module.
[group('test')]
test-module module:
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s gxi -:max-heap=1G ./run-module-test.ss {{ quote(module) }}

# Run one exact Aitia-owned Scheme test.
[group('test')]
test-scheme-atomic module="sdlc" test_file="unit/nasa-certification-test.ss":
    just _test-scheme-file "t/{{ module }}/{{ test_file }}"

[group('test')]
test-proof-scheme test_file:
    just _test-scheme-file "dev/proof/scheme/{{ test_file }}"

_test-scheme-file path:
    test -f {{ quote(path) }}
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s gxi -:max-heap=1G ./run-test.ss {{ quote(path) }}

# Check native compiler products with the existing CI heap and deadline.
[group('test')]
test-native-products:
    {{ gerbil_env }} timeout --signal=TERM --kill-after=5s 180s gxi -:max-heap=2G,debug=q -e '(import (prefix-in :gerbil/tools/gxtest test.)) (exit (test.main "t/native-products-test.ss"))'

# Build and execute Aitia's SDLC plus GitOps composition case.
[group('check')]
test-integration:
    just build-scheme
    just build-user-interface
    just test-scheme bindings
    just test-scheme integration

# Reject POO slot self-reference before building or executing the contribution,
# then run the current Scheme semantic closure without widening into native delivery.
[group('check')]
check-semantic:
    just test-proof-scheme source-admission-test.ss
    just build-scheme
    just test-scheme assurance
    just test-scheme ADR
    just test-scheme sdlc
    just test-module sdlc
    just test-module nasa-7150-2d-catalog
    just test-scheme gitops
    just test-module lambda-aitia/modules/gitops/interface
    just test-scheme modules

# Build the Aitia-owned assurance laws independently of Agentic AI Lab's proof package.
[group('check')]
check-proof:
    cd dev/proof/lean && lake build LambdaAitiaModuleAssuranceProof LambdaAitiaModuleSdlcProof LambdaAitiaModuleGitOpsProof
    cd dev/proof/lean && output="$(lake env lean AxiomAudit.lean)" && printf '%s\n' "$output" && ! grep -q 'sorryAx' <<< "$output"

# Quint 0.33.0 and its Apalache 0.62.1 TLC backend are explicit inputs.
# The checker exhausts each bounded model and requires negative-control traces.
[group('check')]
check-quint module='all':
    python3 dev/proof/quint/check_contract.py '{{module}}'

# Execute the independent commit evidence witnesses.
[group('check')]
check-quint-commit:
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/CommitEvidence.qnt
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/GitOpsWriteRecovery.qnt
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/GitOpsAttemptCompetition.qnt

# Exercise the assurance-objective selection and evidence-currentness cases.
[group('check')]
check-quint-ai-assurance:
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/AiAssuranceObjectives.qnt

# Build the standalone JavaScript adapter from its Gerbil source.
[group('build')]
stage-quint-js out=(native_root + "/quint-driver.js"):
    #!/usr/bin/env bash
    set -euo pipefail
    out={{ quote(out) }}
    mkdir -p "$(dirname "$out")"
    out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
    scratch="$(mktemp -d)"
    stage=""
    trap 'rm -rf -- "$scratch"; if [[ -n "$stage" ]]; then rm -f -- "$stage"; fi' EXIT
    gambit="$(gxi -e '(displayln (path-expand "bin/gsc" (gerbil-home)))')"
    cp dev/proof/quint/quint-driver.ss "$scratch/quint-driver.ss"
    (
      cd "$scratch"
      mkdir lib
      GERBIL_PATH="$scratch" gxc -s -S quint-driver.ss
      "$gambit" -target js -c -o module.js -postlude '(quint-driver#invoke)' lib/quint-driver~0.scm
      "$gambit" -target js -link -flat -o runtime.js module.js
      cat runtime.js module.js > driver.js
    )
    stage="$(mktemp "$(dirname "$out")/.quint-js.XXXXXX")"
    cat "$scratch/driver.js" > "$stage"
    mv "$stage" "$out"

# Qualify the generated JavaScript adapter with the pinned Quint checker.
[group('check')]
check-quint-commit-js:
    #!/usr/bin/env bash
    set -euo pipefail
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    quint_bin="${AITIA_QUINT_BIN:-$PWD/dev/proof/quint/node_modules/.bin/quint}"
    just stage-quint-js "$scratch/driver.js"
    timeout --foreground --signal=TERM --kill-after=3s 60s node "$scratch/driver.js" "$quint_bin" "$PWD/dev/proof/quint/CommitEvidence.qnt"
    status=0
    timeout --foreground --signal=TERM --kill-after=3s 60s node "$scratch/driver.js" "$quint_bin" "$scratch/absent.qnt" >"$scratch/refusal" 2>&1 || status=$?
    if [[ "$status" != 1 ]] || ! grep -Fq 'absent.qnt' "$scratch/refusal"; then
      cat "$scratch/refusal" >&2
      exit 1
    fi

# Exercise the same adapter through the Rust engineering command.
[group('check')]
check-rust-quint: build-rust-cli stage-quint-js
    #!/usr/bin/env bash
    set -euo pipefail
    quint_bin="${AITIA_QUINT_BIN:-$PWD/dev/proof/quint/node_modules/.bin/quint}"
    target="${CARGO_TARGET_DIR:-rust/target}"
    driver='{{ native_root }}/quint-driver.js'
    "$target/debug/aitia" quint-check "$driver" "$quint_bin" dev/proof/quint/CommitEvidence.qnt
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    printf 'module Refusal { run rejectedAssertionTest = assert(false) }\n' > "$scratch/Refusal.qnt"
    status=0
    "$target/debug/aitia" quint-check "$driver" "$quint_bin" "$scratch/Refusal.qnt" >"$scratch/refusal" 2>&1 || status=$?
    cat "$scratch/refusal"
    test "$status" -eq 1
    grep -Fq 'rejectedAssertionTest' "$scratch/refusal"
    grep -Fq 'Error [QNT508]: Assertion failed' "$scratch/refusal"
    grep -Fq 'Quint execution failed: exit status: 1' "$scratch/refusal"

# Pinned Quint MBT traces, native Scheme execution, and explicit fault refusals.
[group('check')]
check-quint-scheme:
    python3 dev/proof/quint/check_scheme_replay.py

# Compare Scheme with reachable action witnesses and fault refusals.
[group('check')]
check-lifecycle-scheme mode="": build-scheme
    {{ gerbil_env }} gxc -d '{{ GERBIL_PATH }}/lib' dev/proof/scheme/lifecycle-fixture.ss
    {{ gerbil_env }} gxc -d '{{ GERBIL_PATH }}/lib' dev/proof/scheme/lifecycle-replay-test.ss
    python3 dev/proof/quint/test_lifecycle_replay.py
    python3 dev/proof/quint/check_lifecycle_replay.py {{ mode }}

# Explicit robustness run over the full bounded state cover.
[group('check')]
stress-lifecycle-scheme:
    just check-lifecycle-scheme --stress

# The replay supervisor already owns per-batch process isolation and watchdogs.
[group('test')]
test-lifecycle-batch:
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s gxi {{ gerbil_test_runtime_options }} -e '(import :lambda-aitia/dev/proof/scheme/lifecycle-replay-test) (exit (run-lifecycle-replay))'

# Check model properties and focused implementation controls independently.
[group('check')]
check-formal:
    python3 dev/proof/quint/test_scheme_replay.py
    just test-proof-scheme retirement-binding-test.ss
    just test-proof-scheme retirement-execution-test.ss
    just check-quint
    just check-quint-commit
    just check-quint-ai-assurance
    just check-proof

# Run the external-interpreter case separately from the default Cargo suite.
[group('rust')]
test-rust-frozen-pytest:
    test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --lib -- pytest::tests::observes_real_pytest_and_detects_source_mutation --ignored --exact

# Qualify the linked program, Quint consumer and the exact wheel built here.
[group('check')]
check-rust-delivery:
    #!/usr/bin/env bash
    set -euo pipefail
    test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    just test-rust-frozen-pytest test-rust-linked-program check-rust-quint build-rust-wheel release "$scratch"
    shopt -s nullglob
    wheels=("$scratch"/*.whl)
    test "${#wheels[@]}" -eq 1
    just check-installed-rust-wheel "${wheels[0]}"

# Current repository closure. No recipe grants runtime authority.
[group('check')]
check: check-license-contract check-semantic check-formal test-integration test-jj-commit-evidence check-rust-format check-rust-lint test-rust-workspace check-rust-delivery

[group('check')]
check-all: check

# Validate the repository publication license contract.
[group('check')]
check-license-contract:
    python3 scripts/check_license_contract.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
