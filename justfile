# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

export GERBIL_BUILD_CORES := env_var_or_default("GERBIL_BUILD_CORES", "12")

self_root := justfile_directory()
poo_flow_root := env_var_or_default("POO_FLOW_ROOT", self_root + "/../..")

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

# POO Flow owns the integration environment; Aitia owns the consumed ABI/Python sources.
[group('check')]
check-native:
    cd '{{ poo_flow_root }}' && just check-aitia-native

# Current repository closure. No recipe grants runtime authority.
[group('check')]
check: check-license-contract check-semantic check-native

# Validate the repository publication license contract.
[group('check')]
check-license-contract:
    python3 scripts/check_license_contract.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
