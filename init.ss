;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Product-owned selection. More Modules join here as their consumer migration closes.
(import :yuanxu/module-system/selection/init-syntax)
(yuanxu!
  :load-modules "./modules" mode: explicit
  (assurance)
  (ADR)
  (formal-methods)
  (gitops)
  (project-config)
  (nasa-7150-2d-catalog)
  (sdlc)
  :load-modules "./user-interface/profiles" mode: explicit rename: Profiles
  (delivery @ "./user-interface/profiles/gitops")
  (nasa-7150-2d @ "./user-interface/profiles/nasa")
  (software-engineering)
  :load-modules "./user-interface/scenarios" mode: explicit rename: scenarios
  (github-gitops)
  (aitia)
  (job-executor-retirement)
  (job-retirement-contract))
