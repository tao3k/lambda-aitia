# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", "12")

self_root := justfile_directory()
export GERBIL_PATH := env_var_or_default("GERBIL_PATH", self_root + "/.gerbil")
export GERBIL_LOADPATH := env_var_or_default("GERBIL_LOADPATH", self_root + ":" + GERBIL_PATH + "/lib")
native_root := GERBIL_PATH + "/native"
native_library := native_root + "/libpoo_flow_aitia.dylib"
gerbil_env := if os() == "macos" { "env -u SDKROOT" } else { "env" }
export UV_CACHE_DIR := env_var_or_default("UV_CACHE_DIR", self_root + "/.cache/uv")
darwin_cc := if os() == "macos" { "/usr/bin/cc" } else { "cc" }
darwin_target := if os() == "macos" { "26.0" } else { "" }
export CC := env_var_or_default("CC", darwin_cc)
export MACOSX_DEPLOYMENT_TARGET := env_var_or_default("MACOSX_DEPLOYMENT_TARGET", darwin_target)

[group('discovery')]
default:
    @just --list

# Build this Gerbil package against the installed POO Flow mechanisms.
[group('build')]
build-scheme:
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} gerbil build

# Run one Aitia-owned Scheme test module.
[group('test')]
test-scheme module="sdlc":
    test -d "t/{{ module }}"
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=5s 120s gxi -:max-heap=1G ./run-test.ss "t/{{ module }}"

# Run one exact Aitia-owned Scheme test.
[group('test')]
test-scheme-atomic module="sdlc" test_file="unit/nasa-certification-test.ss":
    test -f "t/{{ module }}/{{ test_file }}"
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} timeout --foreground --signal=TERM --kill-after=3s 60s gxi -:max-heap=1G ./run-test.ss "t/{{ module }}/{{ test_file }}"

# Build and execute Aitia's SDLC plus GitOps composition case.
[group('check')]
test-integration:
    just build-scheme
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} ./integration-build.ss compile
    just test-scheme bindings
    just test-scheme integration

# Reject POO slot self-reference before building or executing the contribution,
# then run the current Scheme semantic closure without widening into native delivery.
[group('check')]
check-semantic:
    just test-scheme-atomic sdlc source-admission-test.ss
    just build-scheme
    just test-scheme assurance
    just test-scheme ADR
    just test-scheme sdlc
    just test-scheme gitops
    just test-scheme modules

# Build the Aitia-owned assurance laws independently of POO Flow's proof package.
[group('check')]
check-proof:
    cd proof/lean && lake build LambdaAitiaModuleAssuranceProof LambdaAitiaModuleSdlcProof
    cd proof/lean && output="$(lake env lean AxiomAudit.lean)" && printf '%s\n' "$output" && ! grep -q 'sorryAx' <<< "$output"

# TLA_TOOLS_JAR is an explicit, checksum-verified input; the recipe never
# downloads tools or writes into the user's global Java environment.
[group('check')]
check-tla:
    python3 -m unittest discover -s bindings/python/tests -p 'tla_contract.py'

# Aitia owns its native ABI and Python Runtime checks.
[group('check')]
check-native:
    just build-scheme
    GERBIL_BUILD_VERBOSE=1 {{ gerbil_env }} ./integration-build.ss compile
    mkdir -p '{{ native_root }}'
    {{ gerbil_env }} python3 tools/build-native-library.py --output '{{ native_library }}'
    cc -std=c11 -Wall -Wextra -Werror -pedantic -Ibindings/c/include bindings/c/tests/aitia-header-harness.c -o '{{ native_root }}/aitia_header_harness'
    '{{ native_root }}/aitia_header_harness'
    cc -std=c11 -Wall -Wextra -Werror -pedantic -Ibindings/c/include bindings/c/tests/aitia-dynamic-harness.c -o '{{ native_root }}/aitia_dynamic_harness'
    '{{ native_root }}/aitia_dynamic_harness' '{{ native_library }}'
    just test-scheme bindings
    cd bindings/python && {{ gerbil_env }} uv lock --check
    cd bindings/python && {{ gerbil_env }} uv run --locked --extra test python src/lambda_aitia/_native/_build.py
    cd bindings/python && LAMBDA_AITIA_NATIVE_LIBRARY='{{ native_library }}' {{ gerbil_env }} uv run --locked --extra test pytest
    just build-python-wheel '{{ native_library }}'
    just check-installed-wheel

# Exercise the delivered wheel from a fresh environment outside the checkout.
[group('check')]
check-installed-wheel:
    cd bindings/python && {{ gerbil_env }} uv run --locked --extra test pytest tests/installed_wheel_qualification.py

# Build the production wheel from Aitia's locked uv environment. The preceding
# sync makes the declared PEP 517 backend available without a second isolated
# resolution, so the wheel build is deterministic and network-independent.
[group('build')]
build-python-wheel native_library:
    test -f '{{ native_library }}'
    cd bindings/python && LAMBDA_AITIA_NATIVE_LIBRARY='{{ native_library }}' env -u SDKROOT uv sync --locked --extra test
    cd bindings/python && LAMBDA_AITIA_NATIVE_LIBRARY='{{ native_library }}' env -u SDKROOT uv build --wheel --offline --no-build-isolation

# Current repository closure. No recipe grants runtime authority.
[group('check')]
check: check-license-contract check-semantic check-proof check-tla test-integration check-native

[group('check')]
check-all: check

# Validate the repository publication license contract.
[group('check')]
check-license-contract:
    python3 scripts/check_license_contract.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
