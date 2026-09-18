;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/text/json string->json-object)
        (only-in :poo-flow/lambda-aitia/bindings/c/aitia-contract
                 aitia-abi-revision
                 aitia-descriptor-payload
                 aitia-sdlc-flow-plan-payload
                 aitia-gitops-evaluate-payload))
(export aitia-native-test)

(def +accepted-change+
  "{\"event\":\"pull-request\",\"repository\":\"tao3k/poo-flow\",\"revision\":\"0123456789abcdef\",\"source-ref\":\"feature/aitia\",\"target-ref\":\"develop\",\"pull-request\":42,\"checks\":[{\"name\":\"commit-policy\",\"conclusion\":\"success\"},{\"name\":\"build\",\"conclusion\":\"success\"},{\"name\":\"unit-test\",\"conclusion\":\"success\"},{\"name\":\"nasa-7150-2d\",\"conclusion\":\"success\"}]}")

(def aitia-native-test
  (test-suite "Aitia Scheme-native C ABI"
    (test-case "descriptor keeps version out of the public namespace"
      (let (descriptor (string->json-object (aitia-descriptor-payload)))
        (check (aitia-abi-revision) => 2)
        (check (hash-get descriptor "schema") => "lambda-aitia.native-descriptor")
        (check (hash-get descriptor "semanticOwner") => "lambda-aitia")
        (check (hash-get descriptor "operations")
               => '("sdlc-flow-plan" "gitops-evaluate"))))
    (test-case "Scheme publishes the complete inert SDLC DAG plan"
      (let (plan
            (string->json-object
             (aitia-sdlc-flow-plan-payload
              "{\"lifecycle-id\":\"release/42\"}")))
        (check (hash-get plan "schema") => "lambda-aitia.sdlc-flow-plan")
        (check (hash-get plan "lifecycleId") => "release/42")
        (check (hash-get plan "stages")
               => '("change" "invalidate" "plan" "verify" "admit"
                    "decide" "authorize" "effect"))
        (check (hash-get plan "topologicalOrder")
               => '("release/42/change" "release/42/invalidate"
                    "release/42/plan" "release/42/verify" "release/42/admit"
                    "release/42/decide" "release/42/authorize"
                    "release/42/effect"))
        (check (hash-get plan "semanticOwner") => "lambda-aitia")
        (check (hash-get plan "runtimeOwner") => "poo-flow")
        (check (hash-get plan "releaseAuthorized") => #f)
        (check (hash-get plan "runtimeExecuted") => #f)))
    (test-case "Scheme remains the GitOps decision owner"
      (let (decision
            (string->json-object
             (aitia-gitops-evaluate-payload +accepted-change+)))
        (check (hash-get decision "accepted") => #t)
        (check (hash-get decision "profile") => "dev")
        (check (hash-get decision "revision") => "0123456789abcdef")))
    ))
