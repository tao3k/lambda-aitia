-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Lake
open Lake DSL

package «lambda-aitia-proof» where
  version := v!"0.1.0"

lean_lib LambdaAitiaProof where
  roots := #[`LambdaAitiaProof]

/-!
Module libraries mirror the Scheme owners under `modules`. Lake derives each
complete import closure from these roots; `LambdaAitiaProof` remains the
explicit repository-wide integration aggregate.
-/
@[default_target]
lean_lib LambdaAitiaModuleAssuranceProof where
  roots := #[`LambdaAitiaProof.Modules.Assurance]

lean_lib LambdaAitiaModuleSdlcProof where
  roots := #[`LambdaAitiaProof.Modules.Sdlc]
