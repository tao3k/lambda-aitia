;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .o)
        "types.ss" "func.ss" "objects.ss" "commit-evidence.ss" "commit-admission.ss")
(export Config)

(def Config
  (.o profile: OpenGitOpsProfile profile?: gitops-profile?
      change: gitops-change change?: gitops-change?
      check: gitops-check check?: gitops-check?
      decision?: gitops-decision?
      matches?: gitops-profile-matches? match-change: gitops-match-change
      evaluate: gitops-evaluate-default
      admit-commit-observation: gitops-admit-commit-observation
      assess-replay-observation: gitops-assess-replay-observation
      replay-org: gitops-replay-org
      commit-intent: gitops-commit-intent
      record-commit-approval!: gitops-record-commit-approval!
      revoke-commit-approval!: gitops-revoke-commit-approval!
      consume-commit-admission!: gitops-consume-commit-admission!
      commit-admission: gitops-commit-admission
      commit-check-org: gitops-commit-check-org
      nasa-draft-requirements: gitops-nasa-draft-requirements
      nasa-commit-description: gitops-nasa-commit-description
      commit-evidence: gitops-commit-evidence
      model-gaps: gitops-model-gaps))
