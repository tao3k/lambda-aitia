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

On Darwin, the repository `justfile` selects `/usr/bin/cc`, unsets `SDKROOT`
for Gerbil invocations, and keeps the deployment metadata consistent with the
installed Gerbil/Gambit native objects. The large Gambit closure uses DWARF
unwind on arm64 because its function offsets exceed compact-unwind encoding;
this architecture-specific linker choice is not a macOS-version support
boundary.
