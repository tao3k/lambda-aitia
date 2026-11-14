;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json write-json)
        (only-in :clan/poo/object .get .o))
(export fixture-cut evidence-fields observation-source)

;; Build Scheme fixture values from cuts captured by the Rust JJ adapter.
(def (fixture-cut project-id row)
  (.o project: project-id
      workspace: (hash-ref row "workspace_name")
      change: (hash-ref row "change_id")
      operation: (hash-ref row "operation_id")
      commit: (hash-ref row "commit_id")
      tree: (hash-ref row "tree_id")
      parents: (hash-ref row "parent_ids")))

(def (evidence-fields cut producer (identity "fixture-pass") (outcome "passed") (obligation "check"))
  (list (cons "PROJECT" (.get cut project))
        (cons "WORKSPACE" (.get cut workspace))
        (cons "CHANGE" (.get cut change))
        (cons "OPERATION" (.get cut operation))
        (cons "COMMIT" (.get cut commit))
        (cons "TREE" (.get cut tree))
        (cons "PARENTS" (call-with-output-string
                         (lambda (port)
                           (write-json port (list->vector (.get cut parents))))))
        (cons "PRODUCER" producer)
        (cons "ID" identity)
        (cons "OBLIGATION" obligation)
        (cons "OUTCOME" outcome)))

(def (observation-source fields)
  (let (record (make-hash-table))
    (for-each (lambda (field) (hash-put! record (car field) (cdr field))) fields)
    (call-with-output-string (lambda (port) (write-json port record)))))
