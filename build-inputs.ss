;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Both native package specs consume one generated-input declaration.
(import (only-in :asp-gerbil-scheme/src/build-api/generated-module-projection
                 asp-gerbil-scheme-verified-generated-module))
(export lambda-aitia-generated-build-inputs)
(def lambda-aitia-generated-build-inputs
  (list
   (asp-gerbil-scheme-verified-generated-module
    module: "modules/sdlc/standards/sources.ss"
    extra-inputs: '("modules/sdlc/standards/source.lock.ss"))))
