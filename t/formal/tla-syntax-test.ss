;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Source qualification only; neither TLC nor semantic refinement is inferred.
;;; Explicit formal lane; run from the Aitia root with the qualified parser.
(import :std/test
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil-parser/languages/tla-plus/v1/parser
                 +tla-plus-syntax-contract+ parse-tla-plus-v1)
        (only-in :gerbil-parser/src/runtime/artifact
                 parse-artifact-success? parse-artifact-valid?
                 parse-artifact-roundtrip))
(export tla-syntax-test)

(def tla-syntax-test
  (test-suite "Aitia formal source syntax qualification"
    (test-case "all maintained models bind native syntax and original bytes"
      (check +tla-plus-syntax-contract+ => "tla-plus.native-core.v1")
      (for-each
       (lambda (name)
         (let* ((path (string-append "proof/tla/" name ".tla"))
                (source (call-with-input-file path read-all-as-string))
                (artifact (parse-tla-plus-v1 source)))
           (check (list name (parse-artifact-success? artifact)
                        (parse-artifact-valid? artifact))
                  => (list name #t #t))
           (check (parse-artifact-roundtrip artifact) => source)))
       '("EffectAdmission" "AssuranceLifecycle" "WorkLifecycle"
         "RetirementReview" "RetirementIngress")))
    (test-case "lossless diagnostic artifacts do not imply syntax admission"
      (let* ((source "---- MODULE Broken ----\nWork == INSTANCE\n====\n")
             (artifact (parse-tla-plus-v1 source)))
        (check (parse-artifact-success? artifact) => #f)
        (check (parse-artifact-roundtrip artifact) => source)))))
