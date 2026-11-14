# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

# Gerbil derives its default from the host; preserve caller-supplied limits.
# GAMBOPT heap limits apply per process, not to the whole compiler tree.
export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", `gxi -:max-heap=2G -e '(display (##core-count))'`)

self_root := justfile_directory()
export GERBIL_PATH := env_var_or_default("GERBIL_PATH", self_root + "/.gerbil")
export GERBIL_LOADPATH := env_var_or_default("GERBIL_LOADPATH", self_root + ":" + GERBIL_PATH + "/lib")
build_root := GERBIL_PATH + "/build"
gerbil_env := if os() == "macos" { "env -u SDKROOT" } else { "env" }
gerbil_test_runtime_options := "-:max-heap=512M"
export UV_CACHE_DIR := env_var_or_default("UV_CACHE_DIR", self_root + "/.cache/uv")

[group('discovery')]
default:
    @just --list

import 'rust/workspace.just'

# Exercise the OpenSysML SDK against a local service.
[group('rust')]
test-sysml-model:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features sysml --test sysml_model

# Exercise the linked CLI against a real recorded manifest and SysML service.
[group('rust')]
test-project-sysml: stage-rust-program
    test -x "${AITIA_JJ_BIN:?set AITIA_JJ_BIN}"
    AITIA_PROGRAM_MANIFEST='{{ build_root }}/aitia-program/program.json' timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --test sysml_model

[group('rust')]
test-jj-observation:
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-jj --features real-jj --lib --test workspace_cut

[group('check')]
test-jj-commit-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    export AITIA_JJ_REPLAY_CUTS="$scratch/cuts.json"
    just test-jj-observation
    just test-commit-semantics dev/proof/scheme/jj-commit-evidence-test.ss

# Build this Gerbil package against the installed Agentic AI Lab mechanisms.
[group('build')]
build-scheme:
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} gerbil build

# Compile through the standard package entry, then stage admitted program products.
[group('rust')]
stage-rust-program program="aitia-program":
    #!/usr/bin/env bash
    set -euo pipefail
    export AITIA_PROGRAM_OUTPUT={{ quote(build_root + "/" + program) }}
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 600s gxi -e '
      (import (only-in "./build.ss" aitia-build-projection aitia-make)
              (only-in :clan/poo/object .get .call)
              (only-in :std/misc/process run-process/batch)
              (only-in :tao3k/yuanxu/module-system/source/admission
                       module-source-read module-source-admit-current!)
              (only-in :tao3k/yuanxu/module-system/building/products call-with-selected-output-lock)
              (only-in :tao3k/yuanxu/module-system/building/artifacts admit-build-artifact-publication!))
      (def output (getenv "AITIA_PROGRAM_OUTPUT"))
      (def products (path-expand "lib" output))
      (def stage (path-expand "link" output))
      (def manifest (path-expand "program.json" output))
      (def staged-manifest (path-expand "program.json" stage))
      (def dependency-path (getenv "GERBIL_LOADPATH"))
      (def (stage-program!)
        (when (file-exists? manifest) (delete-file manifest))
        (def declaration (getenv "AITIA_PROJECT_DECLARATION" #f))
        (def declaration-inputs
          (if declaration
              (let (path (path-normalize (path-expand declaration)))
                (setenv "AITIA_PROJECT_DECLARATION" path)
                (list (cons path (module-source-read path))))
              (quote ())))
        (def (admit-declaration!)
          (module-source-admit-current! declaration-inputs "project declaration changed during staging"))
        (def projection (aitia-build-projection))
        (.call projection .compile products
          (lambda ()
            (dynamic-wind admit-declaration!
              (lambda () (aitia-make (.get projection spec) "compile"))
              admit-declaration!)))
        (def graph (.get projection build-graph))
        (def (admit-stage-inputs!)
          (admit-declaration!)
          (admit-build-artifact-publication! graph))
        (create-directory* stage)
        (when (file-exists? staged-manifest) (delete-file staged-manifest))
        (dynamic-wind
          admit-stage-inputs!
          (lambda ()
            (run-process/batch
              (list "env"
                (string-append "AITIA_PROGRAM_OUTPUT=" stage)
                (string-append "GERBIL_LOADPATH=" products ":" dependency-path)
                (path-expand "bin/gxi" (gerbil-home)) "-e"
                "(import (only-in :gerbil/expander core-resolve-library-module-path) :gerbil-scheme-rust/scheme/program-build) (gerbil-rs-stage-program (core-resolve-library-module-path (quote :lambda-aitia/rust/scheme/program)) (getenv \"AITIA_PROGRAM_OUTPUT\"))")))
          admit-stage-inputs!)
        (rename-file staged-manifest manifest))
      (call-with-selected-output-lock output stage-program!)'

[group('rust')]
build-rust-cli features="linked-program,sysml": stage-rust-program
    AITIA_PROGRAM_MANIFEST='{{ build_root }}/aitia-program/program.json' cargo build --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features {{ quote(features) }} --bin aitia

[group('rust')]
build-rust-linked-tests program="aitia-program": (stage-rust-program program)
    AITIA_PROGRAM_MANIFEST={{ quote(build_root + "/" + program + "/program.json") }} cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --test linked_program --no-run

[group('rust')]
test-rust-linked-program: build-rust-linked-tests
    test -x "${AITIA_JJ_BIN:?set AITIA_JJ_BIN}" && test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    AITIA_PROGRAM_MANIFEST='{{ build_root }}/aitia-program/program.json' cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --lib --no-run
    AITIA_PROGRAM_MANIFEST='{{ build_root }}/aitia-program/program.json' timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --lib --test linked_program -- --nocapture

[group('rust')]
test-rust-project-declaration:
    test -x "${AITIA_JJ_BIN:?set AITIA_JJ_BIN}"
    AITIA_PROJECT_DECLARATION={{ quote(self_root + "/dev/qualification/project-declaration.ss") }} just build-rust-linked-tests aitia-project-declaration
    AITIA_PROGRAM_MANIFEST={{ quote(build_root + "/aitia-project-declaration/program.json") }} timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features linked-program,sysml --test linked_program -- --ignored --exact compiled_project_declaration_requires_its_recorded_source --nocapture

[group('rust')]
build-rust-wheel profile="release" out=(build_root + "/aitia-wheels"): stage-rust-program
    cd rust/crates/aitia-python && AITIA_PROGRAM_MANIFEST='{{ build_root }}/aitia-program/program.json' maturin build --profile {{ quote(profile) }} --locked --auditwheel repair --out {{ quote(out) }}

# Exercise a Maturin wheel outside the checkout with the installed Gerbil.
[group('rust')]
check-installed-rust-wheel wheel:
    #!/usr/bin/env bash
    set -euo pipefail
    wheel={{ quote(wheel) }}
    wheel="$(cd "$(dirname "$wheel")" && pwd -P)/$(basename "$wheel")"
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    cd "$scratch"
    python3 -m venv venv
    venv/bin/python -m pip --disable-pip-version-check --no-cache-dir install --no-index --no-deps "$wheel"
    args=()
    if [[ -n "${AITIA_PYTEST_PYTHON:-}" ]]; then args+=("$AITIA_PYTEST_PYTHON"); fi
    timeout --foreground --signal=TERM --kill-after=3s 60s venv/bin/python -I "{{ self_root }}/dev/qualification/wheel_smoke.py" "${args[@]}"

# Run the development suites through Gerbil's standard test runner.
[group('test')]
test-dev:
    #!/usr/bin/env bash
    set -euo pipefail
    output="$(mktemp)"
    trap 'rm -f -- "$output"' EXIT
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s gerbil -:max-heap=1G test dev.ss 2>&1 | tee "$output"
    grep -Fxq 'MODULE-OK dev.ss' "$output"
    grep -Fxq 'HARNESS-OK ("dev.ss")' "$output"
    grep -Fxq 'OK' "$output"
    ! grep -Eq 'ERROR (CASE|CHECK|MODULE|HARNESS)|Heap overflow|Stack overflow' "$output"

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

# Exercise the complete affected test directories with Gerbil's standard runner.
[group('test')]
test-commit-semantics path="":
    #!/usr/bin/env bash
    set -euo pipefail
    output="$(mktemp)"
    trap 'rm -f -- "$output"' EXIT
    paths=(modules/gitops/tests modules/project-config/tests)
    if [[ -n {{ quote(path) }} ]]; then paths=({{ quote(path) }}); fi
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s gerbil {{ gerbil_test_runtime_options }} test "${paths[@]}" 2>&1 | tee "$output"
    grep -q '^MODULE-OK ' "$output"
    grep -q '^HARNESS-OK ' "$output"
    grep -Fxq 'OK' "$output"
    ! grep -Eq 'ERROR (CASE|CHECK|MODULE|HARNESS)|Heap overflow|Stack overflow' "$output"

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

# Build and execute Aitia's SDLC plus GitOps composition case.
[group('check')]
test-integration: build-scheme _test-integration

_test-integration:
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
    just test-module project-config
    just test-scheme modules

# Reuse the package built by check-semantic for development and integration tests.
[group('check')]
check-scheme: check-semantic test-dev test-commit-semantics _test-retirement _test-integration

_test-retirement:
    just test-proof-scheme retirement-binding-test.ss
    just test-proof-scheme retirement-execution-test.ss

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
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/CommitReviewCurrentness.qnt
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/GitOpsWriteRecovery.qnt
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/GitOpsAttemptCompetition.qnt

# Exercise the assurance-objective selection and evidence-currentness cases.
[group('check')]
check-quint-ai-assurance:
    quint_bin="${AITIA_QUINT_BIN:-dev/proof/quint/node_modules/.bin/quint}"; timeout --foreground --signal=TERM --kill-after=3s 60s "$quint_bin" test --backend=typescript dev/proof/quint/AiAssuranceObjectives.qnt

# Build the standalone JavaScript adapter from its Gerbil source.
[group('build')]
stage-quint-js out=(build_root + "/quint-driver.js"):
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
    for model in CommitEvidence CommitReviewCurrentness; do
      timeout --foreground --signal=TERM --kill-after=3s 60s node "$scratch/driver.js" "$quint_bin" "$PWD/dev/proof/quint/$model.qnt"
    done
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
    driver='{{ build_root }}/quint-driver.js'
    for model in CommitEvidence CommitReviewCurrentness; do
      "$target/debug/aitia" quint-check "$driver" "$quint_bin" "dev/proof/quint/$model.qnt"
    done
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
    #!/usr/bin/env bash
    set -euo pipefail
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    export GERBIL_LOADPATH='{{ GERBIL_PATH }}/lib:{{ GERBIL_LOADPATH }}'
    {{ gerbil_env }} gxc -d '{{ GERBIL_PATH }}/lib' modules/assurance/cedar-preflight.ss modules/assurance/effect-host.ss dev/proof/scheme/lifecycle-fixture.ss
    libraries="$(gxi -:max-heap=512M -e '(import (only-in :std/make pkg-config-libs)) (display (pkg-config-libs "openssl"))')"
    if [[ "$(uname -s)" == Darwin ]]; then
      export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    fi
    timeout --foreground --signal=TERM --kill-after=5s 600s gxc -exe -ld-options "$libraries" -o "$scratch/lifecycle-replay" dev/proof/scheme/lifecycle-replay-test.ss
    python3 dev/proof/quint/test_lifecycle_replay.py
    python3 dev/proof/quint/check_lifecycle_replay.py --worker "$scratch/lifecycle-replay" {{ mode }}

# Explicit robustness run over the full bounded state cover.
[group('check')]
stress-lifecycle-scheme:
    just check-lifecycle-scheme --stress

# Keep the original heap and per-batch process guard.
[group('test')]
test-lifecycle-batch worker:
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s {{ quote(worker) }} {{ gerbil_test_runtime_options }}

# Check model properties and focused implementation controls independently.
[group('check')]
check-formal: _test-retirement
    python3 dev/proof/quint/test_scheme_replay.py
    just check-quint
    just check-quint-commit
    just check-quint-ai-assurance
    just check-proof

# Run the external-interpreter case separately from the default Cargo suite.
[group('rust')]
test-rust-frozen-pytest:
    test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --lib -- pytest::tests::observes_real_pytest_and_detects_source_mutation --ignored --exact

[group('check')]
test-jj-recorded-evidence:
    #!/usr/bin/env bash
    set -euo pipefail
    test -x "${AITIA_JJ_BIN:?set AITIA_JJ_BIN}"
    test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    export AITIA_ADR_REPLAY_EVIDENCE="$scratch/evidence.json"
    timeout --foreground --signal=TERM --kill-after=5s 120s cargo test --locked --manifest-path rust/Cargo.toml -p aitia-runtime --features gitops --lib -- pytest::tests::observes_adr_0008_at_a_recorded_cut --ignored --exact
    {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s gxi {{ gerbil_test_runtime_options }} -e '(import (only-in :gerbil/tools/gxtest main)) (let (status (main "dev/proof/scheme/jj-recorded-evidence-test.ss")) (unless (zero? status) (error "Gerbil tests failed" status)))'

# Qualify the linked program, Quint consumer and the exact wheel built here.
[group('check')]
check-rust-delivery:
    #!/usr/bin/env bash
    set -euo pipefail
    test -x "${AITIA_PYTEST_PYTHON:?set AITIA_PYTEST_PYTHON to the verifier Python}"
    scratch="$(mktemp -d)"
    trap 'rm -rf -- "$scratch"' EXIT
    just test-rust-frozen-pytest test-jj-recorded-evidence test-rust-linked-program test-rust-project-declaration check-rust-quint build-rust-wheel release "$scratch"
    shopt -s nullglob
    wheels=("$scratch"/*.whl)
    test "${#wheels[@]}" -eq 1
    just check-installed-rust-wheel "${wheels[0]}"

# Current repository closure. No recipe grants runtime authority.
[group('check')]
check: check-scheme check-formal test-jj-commit-evidence check-rust-format check-rust-lint test-rust-workspace check-rust-delivery

[group('check')]
check-all: check
