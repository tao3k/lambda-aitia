# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", "12")

self_root := justfile_directory()
poo_flow_root := env_var_or_default("POO_FLOW_ROOT", self_root + "/../..")
export UV_CACHE_DIR := env_var_or_default("UV_CACHE_DIR", self_root + "/.cache/uv")
darwin_cc := if os() == "macos" { "/usr/bin/cc" } else { "cc" }
darwin_target := if os() == "macos" { "26.0" } else { "" }
export CC := env_var_or_default("CC", darwin_cc)
export MACOSX_DEPLOYMENT_TARGET := env_var_or_default("MACOSX_DEPLOYMENT_TARGET", darwin_target)

[group('discovery')]
default:
    @just --list

# Build the Scheme contribution through POO Flow's source-owned adapter.
[group('build')]
build-scheme:
    cd '{{ poo_flow_root }}' && just build-contribute lambda-aitia

# Run one Aitia-owned Scheme test module.
[group('test')]
test-scheme module="sdlc":
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia "{{ module }}"

# Run one exact Aitia-owned Scheme test.
[group('test')]
test-scheme-atomic module="sdlc" test_file="unit/nasa-certification-test.ss":
    cd '{{ poo_flow_root }}' && just test-contribute-atomic lambda-aitia "{{ module }}" "{{ test_file }}"

# Build and execute Aitia's SDLC plus GitOps composition case.
[group('check')]
test-integration:
    cd '{{ poo_flow_root }}' && just check-aitia-integration

# Run the current Scheme semantic closure without widening into native delivery.
[group('check')]
check-semantic: build-scheme
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia assurance
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia ADR
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia sdlc
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia gitops
    cd '{{ poo_flow_root }}' && just test-contribute lambda-aitia modules

# POO Flow owns the integration environment; Aitia owns the consumed ABI/Python sources.
[group('check')]
check-native:
    cd '{{ poo_flow_root }}' && just check-aitia-native

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
check: check-license-contract check-semantic test-integration check-native

[group('check')]
check-all: check

# Validate the repository publication license contract.
[group('check')]
check-license-contract:
    python3 scripts/check_license_contract.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
