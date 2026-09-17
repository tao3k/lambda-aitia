;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme owns the GitOps decision.  C receives copied UTF-8 JSON bytes only;
;;; no Gerbil object crosses the ABI and the caller releases every result.
(import (only-in :std/foreign begin-ffi c-define)
        (only-in :std/text/json json-object->string string->json-object)
        (only-in :clan/poo/object .ref)
        (only-in :gerbil/gambit call-with-output-string display-exception)
        (only-in :poo-flow/lambda-aitia/user-interface/config
                 github-gitops-sdlc)
        (only-in :poo-flow/lambda-aitia/user-interface/scenarios/github-gitops
                 github-change github-check github-run-gitops))

(export aitia-abi-revision
        aitia-descriptor-payload
        aitia-gitops-evaluate-payload
        aitia-c-round-trip)

(def +aitia-abi-revision+ 1)
(def +aitia-descriptor-schema+ "lambda-aitia.native-descriptor")
(def +aitia-decision-schema+ "lambda-aitia.gitops-decision")
(def +aitia-error-schema+ "lambda-aitia.native-error")
(def +aitia-max-input-bytes+ (* 4 1024 1024))

(def (aitia-abi-revision) +aitia-abi-revision+)

(def (aitia-descriptor-payload)
  (json-object->string
   (hash (schema +aitia-descriptor-schema+)
         (abiRevision +aitia-abi-revision+)
         (maximumInputBytes +aitia-max-input-bytes+)
         (operations ["gitops-evaluate"])
         (semanticOwner "lambda-aitia")
         (resultOwnership "caller-release"))))

(def (aitia-error-payload exception)
  (json-object->string
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

(def (decision->json decision)
  (json-object->string
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
         (reasons (symbols->json (.ref decision 'reasons))))))

(def (aitia-gitops-evaluate-payload payload)
  (when (> (string-length payload) +aitia-max-input-bytes+)
    (error "Aitia input exceeds maximum bytes" (string-length payload)))
  (let* ((object (string->json-object payload))
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

(begin-ffi
  ((struct poo_flow_aitia_result status)
   poo-flow-aitia-result-set-bytes!
   poo-flow-aitia-abi-revision
   poo-flow-aitia-descriptor
   poo-flow-aitia-gitops-evaluate
   aitia-c-round-trip)

  (c-declare #<<END-C
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int32_t status;
  uint8_t *payload;
  size_t length;
} poo_flow_aitia_result;

void poo_flow_aitia_result_init(poo_flow_aitia_result *result) {
  if (result == NULL) return;
  result->status = 0;
  result->payload = NULL;
  result->length = 0;
}

void poo_flow_aitia_result_release(poo_flow_aitia_result *result) {
  if (result == NULL) return;
  free(result->payload);
  result->status = 0;
  result->payload = NULL;
  result->length = 0;
}

uint32_t poo_flow_aitia_abi_revision(void);
int32_t poo_flow_aitia_descriptor(poo_flow_aitia_result *result);
int32_t poo_flow_aitia_gitops_evaluate(char *payload,
                                       poo_flow_aitia_result *result);

static int poo_flow_aitia_c_round_trip(void) {
  static const char input[] =
    "{\"event\":\"pull-request\",\"repository\":\"tao3k/poo-flow\","
    "\"revision\":\"0123456789abcdef\",\"source-ref\":\"feature/aitia\","
    "\"target-ref\":\"develop\",\"pull-request\":42,\"checks\":["
    "{\"name\":\"commit-policy\",\"conclusion\":\"success\"},"
    "{\"name\":\"build\",\"conclusion\":\"success\"},"
    "{\"name\":\"unit-test\",\"conclusion\":\"success\"},"
    "{\"name\":\"nasa-7150-2d\",\"conclusion\":\"success\"}]}";
  poo_flow_aitia_result result;
  if (poo_flow_aitia_abi_revision() != 1u) return 1;
  poo_flow_aitia_result_init(&result);
  if (poo_flow_aitia_descriptor(&result) != 0 || result.payload == NULL ||
      strstr((const char *)result.payload,
             "lambda-aitia.native-descriptor") == NULL)
    return 2;
  poo_flow_aitia_result_release(&result);
  if (poo_flow_aitia_gitops_evaluate((char *)input, &result) != 0 ||
      result.payload == NULL ||
      strstr((const char *)result.payload, "\"accepted\":true") == NULL) {
    poo_flow_aitia_result_release(&result);
    return 3;
  }
  poo_flow_aitia_result_release(&result);
  return 0;
}
END-C
  )

  (define-c-struct poo_flow_aitia_result
    ((status . int32))
    #f #f #t)

  (define-c-lambda poo-flow-aitia-result-set-bytes!
    (poo_flow_aitia_result-borrowed-ptr* scheme-object) void
    #<<END-C
free(___arg1->payload);
___arg1->payload = NULL;
___arg1->length = U8_LEN(___arg2);
if (___arg1->length > 0) {
  ___arg1->payload = (uint8_t *)malloc(___arg1->length + 1u);
  if (___arg1->payload == NULL) {
    ___arg1->length = 0;
    ___arg1->status = -1;
    ___return;
  }
  memcpy(___arg1->payload, U8_DATA(___arg2), ___arg1->length);
  ___arg1->payload[___arg1->length] = 0;
}
___return;
END-C
    )

  (define-c-lambda aitia-c-round-trip () int
    "poo_flow_aitia_c_round_trip")

  (c-define (poo-flow-aitia-abi-revision)
    () unsigned-int32 "poo_flow_aitia_abi_revision" "extern"
    (poo-flow/lambda-aitia/bindings/c/aitia-native#aitia-abi-revision))

  (c-define (poo-flow-aitia-descriptor result)
    (poo_flow_aitia_result-borrowed-ptr*) int32
    "poo_flow_aitia_descriptor" "extern"
    (with-exception-catcher
     (lambda (exception)
       (poo_flow_aitia_result-status-set! result -1)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-native#aitia-error-payload
                 exception)))
       -1)
     (lambda ()
       (poo_flow_aitia_result-status-set! result 0)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-native#aitia-descriptor-payload)))
       (poo_flow_aitia_result-status result))))

  (c-define (poo-flow-aitia-gitops-evaluate payload result)
    (UTF-8-string poo_flow_aitia_result-borrowed-ptr*) int32
    "poo_flow_aitia_gitops_evaluate" "extern"
    (with-exception-catcher
     (lambda (exception)
       (poo_flow_aitia_result-status-set! result -1)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-native#aitia-error-payload
                 exception)))
       -1)
     (lambda ()
       (poo_flow_aitia_result-status-set! result 0)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result
        (string->utf8
         (poo-flow/lambda-aitia/bindings/c/aitia-native#aitia-gitops-evaluate-payload
          payload)))
       (poo_flow_aitia_result-status result)))))
