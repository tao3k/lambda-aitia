;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: lightweight pure POO helpers for workflow domain specialization.
;;; Heavy FunFlow/GraphEngine reconciliation lives in compiled `reconcile.ss`.

(import (only-in :clan/poo/object .o)
        (only-in "./types.ss" workflow-domain-profile?))
(export workflow-specialize-domain)

(def (workflow-specialize-domain base domain-id max-branches: (max-branches 4))
  (unless (workflow-domain-profile? base)
    (error "invalid workflow domain profile" base))
  (.o (:: @ base)
      (domain-id := domain-id)
      (default-max-branches := max-branches)))
