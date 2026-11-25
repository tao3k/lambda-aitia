;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Product-owned selection. More Modules join here as their consumer migration closes.
(import :tao3k/yuanxu/module-system/selection/init-syntax)
(yuanxu!
  :build-roots ("bindings/operations" "rust/scheme/program")
  :load-modules "./modules" mode: explicit :test-dir "./t"
  (assurance)
  (ADR)
  (formal-methods)
  (gitops +github)
  (project-config)
  (nasa-7150-2d-catalog)
  (sdlc)
  (workflow)
  :load-modules "./user-interface/profiles" mode: explicit mount: Profiles :test-dir "./t"
  (delivery @ "./user-interface/profiles/gitops")
  (nasa-7150-2d @ "./user-interface/profiles/nasa")
  (software-engineering)
  :load-modules "./user-interface/scenarios" mode: explicit mount: scenarios :test-dir "./t"
  (github-gitops)
  (aitia)
  (job-executor-retirement)
  (job-retirement-contract))
