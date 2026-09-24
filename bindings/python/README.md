<!--
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-->

# Lambda Aitia Python SDLC Runtime

This is Lambda Aitia's production Python project, not an example package.  It
is the Python runtime surface for the complete SDLC lifecycle:

```text
change -> invalidate -> plan -> verify -> admit -> decide -> authorize -> effect
```

Lambda Aitia Scheme owns the lifecycle vocabulary, assurance semantics,
decisions and receipts. POO Flow owns the reusable Graph/DAG and runtime
mechanisms. The Python package consumes those contracts through the stable C
ABI and does not reimplement either owner's semantics.

The current production surface publishes and validates the canonical lifecycle
DAG through `SdlcRuntime.plan()`. The returned receipt is deliberately inert:
it cannot claim release authorization or runtime execution. Stage execution is
added only as each real Scheme operation and attributable receipt becomes
available; the package will never simulate completion with Python callbacks.

`lambda_aitia.verification.run_pytest` is a production subprocess observation
surface, not a Host-issued admission. It preserves exit status, selected test
count, JUnit digest and source-tree digest; zero collected tests, skipped-only
runs, timeouts, missing reports and source drift do not pass its obligation.
It captures a bounded, canonical source-byte payload and executes pytest only
from a separately materialized copy; selectors cannot escape that copy.
`capture_source_tree` and `run_pytest_frozen` expose the same payload boundary
for a future Host-owned source reader. This still does not prove repository
provenance, interpreter independence, or trusted external services. The
Assurance Host owns admission, revocation and execution authority.
The POSIX verifier runs pytest in its own process group and stops that group
on timeout or output overflow. `max_output_bytes` defaults to 8 MiB; only the
last 8 KiB is retained in the observation. Cleanup uncertainty is reported as
`control-error`, never as a passing result.

`AitiaNativeSession` keeps one Gambit transport runtime alive across calls to
`SdlcRuntime(session=...)` and `evaluate_gitops(..., session=...)`. It is
process-exclusive and thread-affine; use it as a context manager. It does not
issue Host verification seals or admission capabilities. A separate Scheme
Host operation and opaque ABI handles are still required before Python
observations can be admitted.

```python
from lambda_aitia import SdlcRuntime

plan = SdlcRuntime().plan("release/42")
assert plan.topological_order[-1] == "release/42/effect"
assert not plan.release_authorized
assert not plan.runtime_executed
```

Builds require `LAMBDA_AITIA_NATIVE_LIBRARY` to identify the qualified native
library that will be bundled into the wheel.

The binding is an independent uv project owned entirely by Lambda Aitia. From
this directory, synchronize and test the locked environment with:

```sh
env -u SDKROOT uv sync --locked --extra test
env -u SDKROOT uv run --locked --extra test pytest
```

Build the distributable wheel after producing the Scheme-native library:

```sh
LAMBDA_AITIA_NATIVE_LIBRARY=/absolute/path/to/libpoo_flow_aitia.dylib \
  env -u SDKROOT uv sync --locked --extra test
LAMBDA_AITIA_NATIVE_LIBRARY=/absolute/path/to/libpoo_flow_aitia.dylib \
  env -u SDKROOT uv build --wheel --offline --no-build-isolation
```

`just check-native` also installs that wheel in a fresh uv environment outside
the repository, runs the native plan, reproduces a lost-acknowledgement bug in
two real worker processes and a loopback HTTP service, checks the corrected
worker, then rejects the old observation after a source edit. This is a known
fault-injection qualification case, not a newly discovered production defect
or an Assurance Host seal.

On Darwin, the repository `justfile` selects `/usr/bin/cc`, unsets `SDKROOT`
for Gerbil invocations, and keeps the deployment metadata consistent with the
installed Gerbil/Gambit native objects. The large Gambit closure uses DWARF
unwind on arm64 because its function offsets exceed compact-unwind encoding;
this architecture-specific linker choice is not a macOS-version support
boundary.
