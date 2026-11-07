;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .o)
        "types.ss" "func.ss" "objects.ss" "commit-evidence.ss" "project-config.ss")
(export Config)

(def Config
  (.o profile: OpenGitOpsProfile profile?: gitops-profile?
      change: gitops-change change?: gitops-change?
      check: gitops-check check?: gitops-check?
      decision?: gitops-decision?
      matches?: gitops-profile-matches? match-change: gitops-match-change
      evaluate: gitops-evaluate-default
      admit-commit-observation: gitops-admit-commit-observation
      commit-evidence: gitops-commit-evidence
      model-gaps: gitops-model-gaps
      project-config: gitops-project-config
      project-config-json: gitops-project-config-json))
