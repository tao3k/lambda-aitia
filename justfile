# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

self_root := justfile_directory()

# Build the Scheme contribution through POO Flow's source-owned adapter.
build-scheme:
    cd '{{ self_root }}/../..' && just build-contribute lambda-aitia

# Run one Aitia-owned Scheme test module.
test-scheme module="sdlc":
    cd '{{ self_root }}/../..' && just test-contribute lambda-aitia "{{ module }}"

# Run one exact Aitia-owned Scheme test.
test-scheme-atomic module="sdlc" test_file="unit/nasa-certification-test.ss":
    cd '{{ self_root }}/../..' && just test-contribute-atomic lambda-aitia "{{ module }}" "{{ test_file }}"

# Build and execute Aitia's SDLC plus GitOps composition case.
test-integration:
    cd '{{ self_root }}/../..' && just check-aitia-integration

# Validate the repository publication license contract.
check-license-contract:
    python3 scripts/check_license_contract.py
    python3 -m unittest discover -s scripts/tests -p 'test_*.py'
