;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :clan/poo/object "types.ss" "objects.ss" "func.ss")
(export Config)

;;; One POO scope; the Module System owns loading, linking and admission.
(def Config
  (.o profile: ADRProfile profile?: ADR-profile?
      contracts: (.o link: ADRLink option: ADROption
                     consequence: ADRConsequence record: ADRRecord)
      record: ADR-record option: ADR-option link: ADR-link
      consequence: ADR-consequence
      record?: ADR-record? record-valid?: ADR-record-valid?
      transition: ADR-transition supersede: ADR-supersede
      canonical: ADR-canonical))
