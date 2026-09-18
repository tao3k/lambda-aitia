;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: official identity for the maintained Aitia Composition.
;;; Invariant: domain assembly remains Aitia-owned; identity rules come from
;;; the POO Flow profile-composition mechanism.

(import (only-in :poo-flow/src/module-system/profile-composition/interface
                 poo-flow-official-composition-identity))

(export aitia-composition-identity)

(def aitia-composition-identity
  (poo-flow-official-composition-identity 'aitia))
