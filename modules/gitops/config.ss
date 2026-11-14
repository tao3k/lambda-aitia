;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
(import (only-in :clan/poo/object .o)
        "types.ss" "func.ss" "objects.ss" "commit-evidence.ss" "commit-admission.ss"
        "commit-semantics.ss" "review-association.ss" "review-lineage.ss" "review-query.ss")
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
      replay-receipt: gitops-replay-receipt
      commit-intent: gitops-commit-intent
      record-commit-approval!: gitops-record-commit-approval!
      revoke-commit-approval!: gitops-revoke-commit-approval!
      consume-commit-admission!: gitops-consume-commit-admission!
      commit-admission: gitops-commit-admission
      commit-check-receipt: gitops-commit-check-receipt
      commit-review-association: gitops-commit-review-association
      commit-model-assessment: gitops-commit-model-assessment
      commit-semantics: gitops-commit-semantics
      nasa-draft-requirements: gitops-nasa-draft-requirements
      nasa-commit-description: gitops-nasa-commit-description
      commit-evidence: gitops-commit-evidence
      review-lineage: gitops-review-lineage
      review-query: gitops-review-query
      model-gaps: gitops-model-gaps))
