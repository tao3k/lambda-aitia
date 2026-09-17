;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :poo-flow/src/module-system/contribution/testing)
;;; Authoring qualification uses Gerbil's parser, not a query execution engine.
(import :std/test :std/misc/ports
        (only-in :gerbil-parser/languages/gql/iso-39075-2024/parser
                 parse-gql-iso-39075-2024)
        (only-in :gerbil-parser/src/runtime/artifact
                 parse-artifact-success? parse-artifact-valid?
                 parse-artifact-roundtrip))

(def sources '("modules/ADR/expired-references.gql"))
(export gql-source-check)

(def gql-source-check
  (test-suite "ADR GQL source authoring through gerbil-parser"
    (test-case "the contributed query preserves its complete native source"
      (for-each
       (lambda (path)
         (let* ((source (call-with-input-file path read-all-as-string))
                (artifact (parse-gql-iso-39075-2024 source)))
           (check-equal? (parse-artifact-success? artifact) #t)
           (check-equal? (parse-artifact-valid? artifact) #t)
           (check-equal? (parse-artifact-roundtrip artifact) source)))
       sources))
    (test-case "malformed queries are rejected"
      (check-equal?
       (parse-artifact-success?
        (parse-gql-iso-39075-2024 "MATCH ( RETURN"))
       #f))))
