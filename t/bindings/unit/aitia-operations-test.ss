;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/encoding/json JSONReadOptions string->json)
        (only-in :lambda-aitia/bindings/operations
                 aitia-org-contract-evaluate-payload aitia-gitops-evaluate-payload))
(export aitia-operations-test)

(def +aitia-operations-test-json-read-options+
  (JSONReadOptions key-as-symbol: #f
                   array-as-vector: #f
                   object-as-hash: #t))

(def (read-aitia-json payload)
  (string->json payload +aitia-operations-test-json-read-options+))

(def +accepted-change+
  "{\"event\":\"pull-request\",\"repository\":\"tao3k/agentic-ai-lab\",\"revision\":\"0123456789abcdef\",\"source-ref\":\"feature/aitia\",\"target-ref\":\"develop\",\"pull-request\":42,\"checks\":[{\"name\":\"commit-policy\",\"conclusion\":\"success\"},{\"name\":\"build\",\"conclusion\":\"success\"},{\"name\":\"unit-test\",\"conclusion\":\"success\"},{\"name\":\"nasa/sdlc/npr-7150.2\",\"conclusion\":\"success\",\"standardEdition\":\"D\",\"sourceLockDigest\":\"sha256:68113744771506840ed6d7abb4873f87fc6b490d405b9637d446ba4b2ba39108\"}]}")

(def aitia-operations-test
  (test-suite "Aitia Scheme transport"
    (test-case "Orgize evaluates supplied Element facts through the Scheme transport"
      (let* ((request (string-append
                       "{\"rows\":[{\"id\":0,\"parentId\":-1,\"kind\":\"org-data\",\"fieldName\":\"\",\"fieldValue\":\"\"},"
                       "{\"id\":1,\"parentId\":0,\"kind\":\"headline\",\"fieldName\":\"title\",\"fieldValue\":\"Evidence\"}],"
                       "\"scopeId\":0,\"queryKind\":\"headline\",\"fieldName\":\"title\",\"fieldValue\":\"Evidence\","
                       "\"expectation\":\"exactly\",\"expectedCount\":1}"))
             (result (read-aitia-json (aitia-org-contract-evaluate-payload request))))
        (check (hash-get result "matchedCount") => 1)
        (check (hash-get result "passed") => #t)))
    (test-case "Scheme remains the GitOps decision owner"
      (let (decision
            (read-aitia-json
             (aitia-gitops-evaluate-payload +accepted-change+)))
        (check (hash-get decision "accepted") => #t)
        (check (hash-get decision "profile") => "dev")
        (check (hash-get decision "revision") => "0123456789abcdef")))
    ))
