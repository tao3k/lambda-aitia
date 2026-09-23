;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Pure Scheme contract behind the native transport. This module is directly
;;; testable; aitia-native.ss owns only C declarations and owned-byte transfer.
(import (only-in :std/encoding/json
                 JSONReadOptions json->string string->json)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil/core call-with-output-string display-exception)
        (only-in :poo-flow/lambda-aitia/user-interface/config
                 github-gitops-sdlc)
        (only-in :poo-flow/lambda-aitia/modules/sdlc/funs
                 sdlc-flow-plan)
        (only-in :poo-flow/lambda-aitia/user-interface/scenarios/github-gitops
                 github-change github-check github-run-gitops))

(export aitia-abi-revision
        aitia-descriptor-payload
        aitia-error-payload
        aitia-sdlc-flow-plan-payload
        aitia-gitops-evaluate-payload)

(def +aitia-abi-revision+ 2)
(def +aitia-descriptor-schema+ "lambda-aitia.native-descriptor")
(def +aitia-sdlc-flow-plan-schema+ "lambda-aitia.sdlc-flow-plan")
(def +aitia-decision-schema+ "lambda-aitia.gitops-decision")
(def +aitia-error-schema+ "lambda-aitia.native-error")
(def +aitia-max-input-bytes+ (* 4 1024 1024))
(def +aitia-json-read-options+
  (JSONReadOptions key-as-symbol: #f
                   array-as-vector: #f
                   object-as-hash: #t))

(def (aitia-abi-revision) +aitia-abi-revision+)

(def (aitia-descriptor-payload)
  (json->string
   (hash (schema +aitia-descriptor-schema+)
         (abiRevision +aitia-abi-revision+)
         (maximumInputBytes +aitia-max-input-bytes+)
         (operations ["sdlc-flow-plan" "gitops-evaluate"])
         (semanticOwner "lambda-aitia")
         (resultOwnership "caller-release"))))

(def (aitia-error-payload exception)
  (json->string
   (hash (schema +aitia-error-schema+)
         (message
          (call-with-output-string
           (lambda (port) (display-exception exception port)))))))

(def (json-required object field)
  (or (hash-get object field)
      (error "missing Aitia input field" field)))

(def (json-symbol object field)
  (string->symbol (json-required object field)))

(def (json-list object field)
  (let (value (json-required object field))
    (cond
     ((list? value) value)
     ((vector? value) (vector->list value))
     (else (error "Aitia input field must be an array" field)))))

(def (json-check object repository revision)
  (github-check
   (json-symbol object "name") repository revision
   (json-symbol object "conclusion")))

(def (symbols->json values)
  (list->vector (map symbol->string values)))

(def (maybe-symbols->json values)
  (and values (symbols->json values)))

(def (aitia-sdlc-flow-plan-payload payload)
  (when (> (string-length payload) +aitia-max-input-bytes+)
    (error "Aitia input exceeds maximum bytes" (string-length payload)))
  (let* ((object (string->json payload +aitia-json-read-options+))
         (lifecycle-id (json-required object "lifecycle-id"))
         (plan (sdlc-flow-plan lifecycle-id))
         (topological-order (.ref plan 'topological-order)))
    (json->string
     (hash (schema +aitia-sdlc-flow-plan-schema+)
           (lifecycleId lifecycle-id)
           (stages (symbols->json (.ref plan 'stages)))
           (topologicalOrder (maybe-symbols->json topological-order))
           (cyclePath (maybe-symbols->json (.ref plan 'cycle-path)))
           (accepted (.ref plan 'accepted?))
           (semanticOwner (symbol->string (.ref plan 'semantic-owner)))
           (runtimeOwner (symbol->string (.ref plan 'runtime-owner)))
           (releaseAuthorized (.ref plan 'release-authorized?))
           (runtimeExecuted (.ref plan 'runtime-executed?))))))

(def (decision->json decision)
  (json->string
   (hash (schema +aitia-decision-schema+)
         (repository (.ref decision 'repository))
         (revision (.ref decision 'revision))
         (profile (symbol->string (.ref decision 'profile)))
         (environment (symbol->string (.ref decision 'environment)))
         (accepted (.ref decision 'accepted))
         (nextProfile (symbol->string (.ref decision 'next-profile)))
         (requiredChecks (symbols->json (.ref decision 'required-checks)))
         (standards (symbols->json (.ref decision 'standards)))
         (missingChecks (symbols->json (.ref decision 'missing-checks)))
         (failedChecks (symbols->json (.ref decision 'failed-checks)))
         (staleChecks (symbols->json (.ref decision 'stale-checks)))
         (reasons (symbols->json (.ref decision 'reasons)))
         (semanticOwner "lambda-aitia")
         (runtimeOwner "poo-flow")
         (authorityStatus "not-evaluated")
         (releaseAuthorized #f)
         (runtimeExecuted #f))))

(def (aitia-gitops-evaluate-payload payload)
  (when (> (string-length payload) +aitia-max-input-bytes+)
    (error "Aitia input exceeds maximum bytes" (string-length payload)))
  (let* ((object (string->json payload +aitia-json-read-options+))
         (repository (json-required object "repository"))
         (revision (json-required object "revision"))
         (change
          (github-change
           (json-symbol object "event") repository revision
           (json-required object "source-ref")
           (json-required object "target-ref")
           (or (hash-get object "pull-request") #f)))
         (checks
          (map (lambda (check) (json-check check repository revision))
               (json-list object "checks"))))
    (decision->json
     (github-run-gitops github-gitops-sdlc change checks))))
