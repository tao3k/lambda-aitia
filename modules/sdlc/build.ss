;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;; Package-owned Scheme entrypoints consumed by the Rust program builder.
(def Build
  (.o kind: 'module/build roots: '()
      library-roots: '(lambda-aitia/bindings/operations
                       lambda-aitia/rust/scheme/program)))
