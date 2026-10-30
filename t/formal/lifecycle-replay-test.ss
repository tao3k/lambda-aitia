;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        :agentic-ai-lab/lambda-aitia/t/formal/lifecycle-fixture)
(export lifecycle-replay-test)
(def lifecycle-replay-test
  (test-suite "Full bounded Quint lifecycle / real Scheme API graph replay"
    (test-case "every supplied edge has the same projected Scheme state"
      (let (file (getenv "AITIA_LIFECYCLE_REPLAY" #f))
        (unless file (error "run through just check-lifecycle-scheme"))
        (let (traces (call-with-input-file file read))
          (check-lifecycle-traces! traces))))))
