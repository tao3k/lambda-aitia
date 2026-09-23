;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; C receives copied UTF-8 JSON bytes only; no Gerbil object crosses the ABI
;;; and the caller releases every result. Pure semantics live in aitia-contract.
(import (only-in :std/ffi
                 C-declare C-ffi-macrology
                 def-C-lambda def-C-type)
        :poo-flow/lambda-aitia/bindings/c/aitia-contract)

(export aitia-c-round-trip)

(C-ffi-macrology)

(C-declare #<<END-C
#include <stdint.h>
#include <stdio.h>
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
int32_t poo_flow_aitia_sdlc_flow_plan(char *payload,
                                      poo_flow_aitia_result *result);
int32_t poo_flow_aitia_gitops_evaluate(char *payload,
                                       poo_flow_aitia_result *result);

static void poo_flow_aitia_native_phase(int32_t phase) {
  fprintf(stderr, "[lambda-aitia-native] scheme-phase=%d\n", phase);
  fflush(stderr);
}

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
  static const char plan_input[] = "{\"lifecycle-id\":\"release/42\"}";
  if (poo_flow_aitia_abi_revision() != 2u) return 1;
  poo_flow_aitia_result_init(&result);
  if (poo_flow_aitia_descriptor(&result) != 0 || result.payload == NULL ||
      strstr((const char *)result.payload,
             "lambda-aitia.native-descriptor") == NULL)
    return 2;
  poo_flow_aitia_result_release(&result);
  if (poo_flow_aitia_sdlc_flow_plan((char *)plan_input, &result) != 0 ||
      result.payload == NULL ||
      strstr((const char *)result.payload,
             "lambda-aitia.sdlc-flow-plan") == NULL ||
      strstr((const char *)result.payload,
             "release/42/effect") == NULL) {
    poo_flow_aitia_result_release(&result);
    return 3;
  }
  poo_flow_aitia_result_release(&result);
  if (poo_flow_aitia_gitops_evaluate((char *)input, &result) != 0 ||
      result.payload == NULL ||
      strstr((const char *)result.payload, "\"accepted\":true") == NULL) {
    poo_flow_aitia_result_release(&result);
    return 4;
  }
  poo_flow_aitia_result_release(&result);
  return 0;
}
END-C
)

(def-C-type poo_flow_aitia_result "poo_flow_aitia_result")
(def-C-type poo_flow_aitia_result-borrowed-ptr*
  (pointer poo_flow_aitia_result
           (poo_flow_aitia_result-borrowed-ptr*)))

(def-C-lambda poo_flow_aitia_result-status
  (poo_flow_aitia_result-borrowed-ptr*) int32
  "___return (___arg1->status);")

(def-C-lambda poo_flow_aitia_result-status-set!
  (poo_flow_aitia_result-borrowed-ptr* int32) void
  "___arg1->status = ___arg2; ___return;")

(def-C-lambda poo-flow-aitia-native-phase
  (int32) void
  "poo_flow_aitia_native_phase(___arg1); ___return;")

(def-C-lambda poo-flow-aitia-result-set-bytes!
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

(def-C-lambda aitia-c-round-trip () int
  "poo_flow_aitia_c_round_trip")

(begin-foreign
  (c-define (poo-flow-aitia-abi-revision)
    () unsigned-int32 "poo_flow_aitia_abi_revision" "extern"
    (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-abi-revision))

  (c-define (poo-flow-aitia-descriptor result)
    (poo_flow_aitia_result-borrowed-ptr*) int32
    "poo_flow_aitia_descriptor" "extern"
    (with-exception-catcher
     (lambda (exception)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result -1)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-error-payload
                 exception)))
       -1)
     (lambda ()
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-native-phase 101)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result 0)
       (let* ((payload
               (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-descriptor-payload))
              (_ (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-native-phase 102))
              (bytes (string->utf8 payload)))
         (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-native-phase 103)
         (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
          result bytes)
         (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-native-phase 104))
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status result))))

  (c-define (poo-flow-aitia-gitops-evaluate payload result)
    (UTF-8-string poo_flow_aitia_result-borrowed-ptr*) int32
    "poo_flow_aitia_gitops_evaluate" "extern"
    (with-exception-catcher
     (lambda (exception)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result -1)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-error-payload
                 exception)))
       -1)
     (lambda ()
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result 0)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result
        (string->utf8
         (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-gitops-evaluate-payload
          payload)))
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status result))))

  (c-define (poo-flow-aitia-sdlc-flow-plan payload result)
    (UTF-8-string poo_flow_aitia_result-borrowed-ptr*) int32
    "poo_flow_aitia_sdlc_flow_plan" "extern"
    (with-exception-catcher
     (lambda (exception)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result -1)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result (string->utf8
                (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-error-payload
                 exception)))
       -1)
     (lambda ()
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status-set! result 0)
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo-flow-aitia-result-set-bytes!
        result
        (string->utf8
         (poo-flow/lambda-aitia/bindings/c/aitia-contract#aitia-sdlc-flow-plan-payload
          payload)))
       (poo-flow/lambda-aitia/bindings/c/aitia-native#poo_flow_aitia_result-status result)))))
