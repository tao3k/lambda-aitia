;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/misc/process run-process)
        (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-runtime-options-for)
        (only-in :agentic-ai-lab/lambda-aitia/testing-interface
                 +lambda-aitia-testing-interface+))
(export testing-resource-test)
(def testing-resource-test
  (test-suite "Native test resource profile propagation"
    (test-case "Just derives frontend and backend workers from this machine"
      (def justfile (path-expand "../../../justfile"
                                (path-directory (this-source-file))))
      (def observed
        (run-process
          (list "env" "-u" "GERBIL_BUILD_CORES" "just" "--justfile" justfile
                "--command" "gxi" "-:max-heap=2G" "-e"
                "(import :gerbil/compiler/base) (write (list (getenv \"GERBIL_BUILD_CORES\" #f) (available-build-cores)))")
          coprocess: read))
      (check observed => (list (number->string (##core-count)) (##core-count))))
    (test-case "Just preserves an explicit caller worker limit"
      (def justfile (path-expand "../../../justfile"
                                (path-directory (this-source-file))))
      (check
        (run-process
          (list "env" "GERBIL_BUILD_CORES=3" "just" "--justfile" justfile
                "--command" "gxi" "-:max-heap=2G" "-e"
                "(import :gerbil/compiler/base) (write (list (getenv \"GERBIL_BUILD_CORES\" #f) (available-build-cores)))")
          coprocess: read)
        => '("3" 3)))
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
