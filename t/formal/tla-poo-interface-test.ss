;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Consumer qualification of POO Flow's syntax receipt. The parser-owned
;;; artifact tests remain separate; neither test claims TLC or refinement.
(import (only-in :clan/poo/object .ref)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :std/test check-equal? check-exception test-case test-suite)
        (only-in :gerbil-parser/src/runtime/cst
                 syntax-node? syntax-node-kind syntax-node-start syntax-node-end)
        (only-in :poo-flow/src/modules/tla-plus/interface
                 PooFlowTlaLanguage. poo-flow-tla-document?
                 poo-flow-tla-parse-source poo-flow-tla-parser-cst))
(export tla-poo-interface-test)

(def tla-poo-interface-test
  (test-suite "Aitia TLA+ POO interface consumer"
    (test-case "all maintained models bind the same parser-owned syntax tree"
      (check-equal? (.ref PooFlowTlaLanguage. 'syntax-contract)
                    "tla-plus.native-core.v1")
      (for-each
       (lambda (name)
         (let* ((source
                 (call-with-input-file
                  (string-append "proof/tla/" name ".tla")
                  read-all-as-string))
                (document (poo-flow-tla-parse-source source))
                (root (poo-flow-tla-parser-cst document)))
           (check-equal? (poo-flow-tla-document? document) #t)
           (check-equal? (syntax-node? root) #t)
           (check-equal? (syntax-node-kind root) 'SourceFile)
           (check-equal? (syntax-node-start root) 0)
           (check-equal? (syntax-node-end root)
                         (u8vector-length (string->utf8 source)))
           (check-equal? (.ref document 'exact-roundtrip?) #t)
           (check-equal? (.ref document 'model-checking?) #f)))
       '("EffectAdmission" "AssuranceLifecycle" "WorkLifecycle"
         "RetirementReview" "RetirementIngress")))
    (test-case "rejected syntax cannot produce an accepted document"
      (check-exception
       (poo-flow-tla-parse-source
        "---- MODULE Broken ----\nWork == INSTANCE\n====\n")
       true))))
