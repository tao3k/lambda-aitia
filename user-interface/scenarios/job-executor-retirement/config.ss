;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .o) "objects.ss")
(export Config)

(def Config
  (.o before: job-retirement-before candidate: job-retirement-candidate
      relations: job-retirement-relations event-graph: job-retirement-event-graph
      incomplete-event-graph: job-retirement-incomplete-event-graph))
