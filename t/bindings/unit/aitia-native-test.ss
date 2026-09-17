;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/text/json string->json-object)
        (only-in :poo-flow/lambda-aitia/bindings/c/aitia-native
                 aitia-abi-revision
                 aitia-descriptor-payload
                 aitia-gitops-evaluate-payload
                 aitia-c-round-trip))
(export aitia-native-test)

(def +accepted-change+
  "{\"event\":\"pull-request\",\"repository\":\"tao3k/poo-flow\",\"revision\":\"0123456789abcdef\",\"source-ref\":\"feature/aitia\",\"target-ref\":\"develop\",\"pull-request\":42,\"checks\":[{\"name\":\"commit-policy\",\"conclusion\":\"success\"},{\"name\":\"build\",\"conclusion\":\"success\"},{\"name\":\"unit-test\",\"conclusion\":\"success\"},{\"name\":\"nasa-7150-2d\",\"conclusion\":\"success\"}]}")

(def aitia-native-test
  (test-suite "Aitia Scheme-native C ABI"
    (test-case "descriptor keeps version out of the public namespace"
      (let (descriptor (string->json-object (aitia-descriptor-payload)))
        (check (aitia-abi-revision) => 1)
        (check (hash-get descriptor "schema") => "lambda-aitia.native-descriptor")
        (check (hash-get descriptor "semanticOwner") => "lambda-aitia")))
    (test-case "Scheme remains the GitOps decision owner"
      (let (decision
            (string->json-object
             (aitia-gitops-evaluate-payload +accepted-change+)))
        (check (hash-get decision "accepted") => #t)
        (check (hash-get decision "profile") => "dev")
        (check (hash-get decision "revision") => "0123456789abcdef")))
    (test-case "C calls the exported Scheme functions and releases bytes"
      (check (aitia-c-round-trip) => 0))))
