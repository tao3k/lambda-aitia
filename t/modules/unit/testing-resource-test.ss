;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-runtime-options-for)
        (only-in :agentic-ai-lab/lambda-aitia/testing-interface
                 +lambda-aitia-testing-interface+))
(export testing-resource-test)
(def testing-resource-test
  (test-suite "Native test resource profile propagation"
    (test-case "lifecycle receives the current bounded 2 GiB profile"
      (check (testing-interface-runtime-options-for
              +lambda-aitia-testing-interface+
              "t/formal/lifecycle-replay-test.ss")
             => '("-:max-heap=2048M")))
    (test-case "ordinary retirement checks retain their original bounded profile"
      (check (testing-interface-runtime-options-for
              +lambda-aitia-testing-interface+
              "t/formal/retirement-binding-test.ss")
             => '("-:max-heap=512M")))))
