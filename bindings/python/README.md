<!--
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-->

# Lambda Aitia Python binding

This package is the Python consumer of Lambda Aitia's Scheme-native C ABI.
Scheme remains the semantic owner of GitOps and SDLC decisions; Python only
serializes JSON input and decodes the returned JSON result.

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
  env -u SDKROOT uv build --wheel
```
