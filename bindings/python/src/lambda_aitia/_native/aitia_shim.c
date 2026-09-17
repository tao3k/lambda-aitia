// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#include "lambda_aitia/aitia.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE lambda_aitia_library;
#define LAMBDA_AITIA_OPEN(path) LoadLibraryA(path)
#define LAMBDA_AITIA_SYMBOL(handle, name) GetProcAddress(handle, name)
#define LAMBDA_AITIA_CLOSE(handle) FreeLibrary(handle)
#else
#include <dlfcn.h>
typedef void *lambda_aitia_library;
#define LAMBDA_AITIA_OPEN(path) dlopen(path, RTLD_NOW | RTLD_LOCAL)
#define LAMBDA_AITIA_SYMBOL(handle, name) dlsym(handle, name)
#define LAMBDA_AITIA_CLOSE(handle) dlclose(handle)
#endif

typedef uint32_t (*lambda_aitia_revision_fn)(void);
typedef int32_t (*lambda_aitia_runtime_init_fn)(void);
typedef void (*lambda_aitia_runtime_shutdown_fn)(void);
typedef void (*lambda_aitia_result_init_fn)(poo_flow_aitia_result *);
typedef void (*lambda_aitia_result_release_fn)(poo_flow_aitia_result *);
typedef int32_t (*lambda_aitia_descriptor_fn)(poo_flow_aitia_result *);
typedef int32_t (*lambda_aitia_evaluate_fn)(char *, poo_flow_aitia_result *);

static void lambda_aitia_write_error(char *error, size_t capacity,
                                     const char *message) {
  if (error == NULL || capacity == 0) return;
  if (message == NULL) message = "unknown native loader error";
  (void)snprintf(error, capacity, "%s", message);
}

static const char *lambda_aitia_loader_error(void) {
#if defined(_WIN32)
  return "Windows native loader failure";
#else
  const char *message = dlerror();
  return message == NULL ? "native loader failure" : message;
#endif
}

void lambda_aitia_python_release(uint8_t *output) { free(output); }

int lambda_aitia_python_call(const char *library_path, const char *operation,
                             const uint8_t *payload, size_t payload_length,
                             uint8_t **output, size_t *output_length,
                             char *error, size_t error_capacity) {
  lambda_aitia_library library;
  lambda_aitia_revision_fn revision;
  lambda_aitia_runtime_init_fn runtime_init;
  lambda_aitia_runtime_shutdown_fn runtime_shutdown;
  lambda_aitia_result_init_fn result_init;
  lambda_aitia_result_release_fn result_release;
  lambda_aitia_descriptor_fn descriptor;
  lambda_aitia_evaluate_fn sdlc_flow_plan;
  lambda_aitia_evaluate_fn evaluate;
  poo_flow_aitia_result result;
  char *input = NULL;
  int32_t status;

  if (output == NULL || output_length == NULL || library_path == NULL ||
      operation == NULL) {
    lambda_aitia_write_error(error, error_capacity, "invalid Aitia call");
    return -100;
  }
  *output = NULL;
  *output_length = 0;
  library = LAMBDA_AITIA_OPEN(library_path);
  if (library == NULL) {
    lambda_aitia_write_error(error, error_capacity, lambda_aitia_loader_error());
    return -101;
  }
  revision = (lambda_aitia_revision_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_abi_revision");
  runtime_init = (lambda_aitia_runtime_init_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_runtime_init");
  runtime_shutdown = (lambda_aitia_runtime_shutdown_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_runtime_shutdown");
  result_init = (lambda_aitia_result_init_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_result_init");
  result_release = (lambda_aitia_result_release_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_result_release");
  descriptor = (lambda_aitia_descriptor_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_descriptor");
  sdlc_flow_plan = (lambda_aitia_evaluate_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_sdlc_flow_plan");
  evaluate = (lambda_aitia_evaluate_fn)LAMBDA_AITIA_SYMBOL(
      library, "poo_flow_aitia_gitops_evaluate");
  if (runtime_init == NULL || runtime_shutdown == NULL || revision == NULL ||
      result_init == NULL || result_release == NULL || descriptor == NULL ||
      sdlc_flow_plan == NULL || evaluate == NULL) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia ABI symbol is absent");
    LAMBDA_AITIA_CLOSE(library);
    return -102;
  }
  if (runtime_init() != 0) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia runtime initialization failed");
    LAMBDA_AITIA_CLOSE(library);
    return -103;
  }
  if (revision() != POO_FLOW_AITIA_ABI_REVISION) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia ABI revision mismatch");
    runtime_shutdown();
    LAMBDA_AITIA_CLOSE(library);
    return -104;
  }
  result_init(&result);
  if (strcmp(operation, "descriptor") == 0) {
    status = descriptor(&result);
  } else if (strcmp(operation, "sdlc-flow-plan") == 0 ||
             strcmp(operation, "gitops-evaluate") == 0) {
    if (payload == NULL || payload_length == 0 || payload_length == SIZE_MAX) {
      lambda_aitia_write_error(error, error_capacity,
                               "Aitia operation requires JSON input");
      result_release(&result);
      runtime_shutdown();
      LAMBDA_AITIA_CLOSE(library);
      return -105;
    }
    input = (char *)malloc(payload_length + 1u);
    if (input == NULL) {
      lambda_aitia_write_error(error, error_capacity, "input allocation failed");
      result_release(&result);
      runtime_shutdown();
      LAMBDA_AITIA_CLOSE(library);
      return -106;
    }
    memcpy(input, payload, payload_length);
    input[payload_length] = '\0';
    status = strcmp(operation, "sdlc-flow-plan") == 0
                 ? sdlc_flow_plan(input, &result)
                 : evaluate(input, &result);
    free(input);
  } else {
    lambda_aitia_write_error(error, error_capacity, "unknown Aitia operation");
    result_release(&result);
    runtime_shutdown();
    LAMBDA_AITIA_CLOSE(library);
    return -107;
  }
  if (result.payload != NULL && result.length > 0) {
    *output = (uint8_t *)malloc(result.length);
    if (*output == NULL) {
      result_release(&result);
      lambda_aitia_write_error(error, error_capacity,
                               "output allocation failed");
      runtime_shutdown();
      LAMBDA_AITIA_CLOSE(library);
      return -108;
    }
    memcpy(*output, result.payload, result.length);
    *output_length = result.length;
  }
  result_release(&result);
  runtime_shutdown();
  LAMBDA_AITIA_CLOSE(library);
  return status;
}
