// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#include "lambda_aitia/aitia.h"
#include "orgize.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE lambda_aitia_library;
typedef FARPROC lambda_aitia_symbol;
#define LAMBDA_AITIA_OPEN(path) LoadLibraryA(path)
#define LAMBDA_AITIA_SYMBOL(handle, name) GetProcAddress(handle, name)
#define LAMBDA_AITIA_CLOSE(handle) FreeLibrary(handle)
#else
#include <dlfcn.h>
typedef void *lambda_aitia_library;
typedef void *lambda_aitia_symbol;
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
typedef uint32_t (*orgize_revision_fn)(void);
typedef int32_t (*orgize_evaluate_fn)(const orgize_element_row *, uint32_t,
                                      int64_t, const char *, const char *,
                                      const char *, uint32_t, uint32_t,
                                      orgize_contract_result *);

typedef struct lambda_aitia_python_session {
  lambda_aitia_library library;
  lambda_aitia_runtime_shutdown_fn runtime_shutdown;
  lambda_aitia_result_init_fn result_init;
  lambda_aitia_result_release_fn result_release;
  lambda_aitia_descriptor_fn descriptor;
  lambda_aitia_evaluate_fn sdlc_flow_plan;
  lambda_aitia_evaluate_fn evaluate;
} lambda_aitia_python_session;

/* Gambit has one process runtime. A live session excludes transient calls. */
static atomic_flag lambda_aitia_runtime_lease = ATOMIC_FLAG_INIT;

static int lambda_aitia_load_symbol(lambda_aitia_library library,
                                    const char *name, void *destination,
                                    size_t destination_size) {
  lambda_aitia_symbol symbol = LAMBDA_AITIA_SYMBOL(library, name);
  if (symbol == NULL || destination_size != sizeof(symbol)) return 0;
  memcpy(destination, &symbol, sizeof(symbol));
  return 1;
}

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

lambda_aitia_python_session *lambda_aitia_python_open(
    const char *library_path, char *error, size_t error_capacity) {
  lambda_aitia_python_session *session;
  lambda_aitia_revision_fn revision;
  lambda_aitia_runtime_init_fn runtime_init;

  if (library_path == NULL || library_path[0] == '\0') {
    lambda_aitia_write_error(error, error_capacity, "invalid Aitia library path");
    return NULL;
  }
  if (atomic_flag_test_and_set(&lambda_aitia_runtime_lease)) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia runtime already has an active session");
    return NULL;
  }
  session = (lambda_aitia_python_session *)calloc(1, sizeof(*session));
  if (session == NULL) {
    lambda_aitia_write_error(error, error_capacity, "session allocation failed");
    goto fail_lease;
  }
  session->library = LAMBDA_AITIA_OPEN(library_path);
  if (session->library == NULL) {
    lambda_aitia_write_error(error, error_capacity, lambda_aitia_loader_error());
    goto fail_session;
  }
  if (!lambda_aitia_load_symbol(session->library, "poo_flow_aitia_abi_revision",
                                &revision, sizeof(revision)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_runtime_init",
                                &runtime_init, sizeof(runtime_init)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_runtime_shutdown",
                                &session->runtime_shutdown,
                                sizeof(session->runtime_shutdown)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_result_init",
                                &session->result_init, sizeof(session->result_init)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_result_release",
                                &session->result_release,
                                sizeof(session->result_release)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_descriptor",
                                &session->descriptor, sizeof(session->descriptor)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_sdlc_flow_plan",
                                &session->sdlc_flow_plan,
                                sizeof(session->sdlc_flow_plan)) ||
      !lambda_aitia_load_symbol(session->library, "poo_flow_aitia_gitops_evaluate",
                                &session->evaluate, sizeof(session->evaluate))) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia ABI symbol is absent");
    goto fail_library;
  }
  if (runtime_init() != 0) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia runtime initialization failed");
    goto fail_library;
  }
  if (revision() != POO_FLOW_AITIA_ABI_REVISION) {
    lambda_aitia_write_error(error, error_capacity,
                             "Lambda Aitia ABI revision mismatch");
    session->runtime_shutdown();
    goto fail_library;
  }
  return session;

fail_library:
  LAMBDA_AITIA_CLOSE(session->library);
fail_session:
  free(session);
fail_lease:
  atomic_flag_clear(&lambda_aitia_runtime_lease);
  return NULL;
}

void lambda_aitia_python_close(lambda_aitia_python_session *session) {
  if (session == NULL) return;
  session->runtime_shutdown();
  LAMBDA_AITIA_CLOSE(session->library);
  free(session);
  atomic_flag_clear(&lambda_aitia_runtime_lease);
}

void lambda_aitia_python_release(uint8_t *output) { free(output); }

int lambda_aitia_python_session_call(
    lambda_aitia_python_session *session, const char *operation,
    const uint8_t *payload, size_t payload_length, uint8_t **output,
    size_t *output_length, char *error, size_t error_capacity) {
  poo_flow_aitia_result result;
  char *input = NULL;
  int32_t status;

  if (session == NULL || output == NULL || output_length == NULL ||
      operation == NULL) {
    lambda_aitia_write_error(error, error_capacity, "invalid Aitia call");
    return -100;
  }
  *output = NULL;
  *output_length = 0;
  session->result_init(&result);
  if (strcmp(operation, "descriptor") == 0) {
    status = session->descriptor(&result);
  } else if (strcmp(operation, "sdlc-flow-plan") == 0 ||
             strcmp(operation, "gitops-evaluate") == 0) {
    if (payload == NULL || payload_length == 0 || payload_length == SIZE_MAX) {
      lambda_aitia_write_error(error, error_capacity,
                               "Aitia operation requires JSON input");
      status = -105;
      goto done;
    }
    input = (char *)malloc(payload_length + 1u);
    if (input == NULL) {
      lambda_aitia_write_error(error, error_capacity, "input allocation failed");
      status = -106;
      goto done;
    }
    memcpy(input, payload, payload_length);
    input[payload_length] = '\0';
    status = strcmp(operation, "sdlc-flow-plan") == 0
                 ? session->sdlc_flow_plan(input, &result)
                 : session->evaluate(input, &result);
  } else {
    lambda_aitia_write_error(error, error_capacity, "unknown Aitia operation");
    status = -107;
    goto done;
  }
  if (result.payload != NULL && result.length > 0) {
    *output = (uint8_t *)malloc(result.length);
    if (*output == NULL) {
      lambda_aitia_write_error(error, error_capacity,
                               "output allocation failed");
      status = -108;
      goto done;
    }
    memcpy(*output, result.payload, result.length);
    *output_length = result.length;
  }

done:
  free(input);
  session->result_release(&result);
  return status;
}

int lambda_aitia_python_session_org_contract(
    lambda_aitia_python_session *session, const orgize_element_row *rows,
    uint32_t row_count, int64_t scope_id, const char *query_kind,
    const char *field_name, const char *field_value, uint32_t expectation,
    uint32_t expected_count, orgize_contract_result *result,
    char *error, size_t error_capacity) {
  orgize_revision_fn revision;
  orgize_evaluate_fn evaluate;

  if (session == NULL || result == NULL) {
    lambda_aitia_write_error(error, error_capacity, "invalid Orgize call");
    return -100;
  }
  if (!lambda_aitia_load_symbol(session->library, "orgize_abi_revision",
                                &revision, sizeof(revision)) ||
      !lambda_aitia_load_symbol(session->library, "orgize_contract_evaluate",
                                &evaluate, sizeof(evaluate))) {
    lambda_aitia_write_error(error, error_capacity,
                             "Orgize ABI symbols are absent");
    return -101;
  }
  if (revision() != 1u) {
    lambda_aitia_write_error(error, error_capacity,
                             "Orgize ABI revision mismatch");
    return -102;
  }
  return evaluate(rows, row_count, scope_id, query_kind, field_name,
                  field_value, expectation, expected_count, result);
}

int lambda_aitia_python_call(const char *library_path, const char *operation,
                             const uint8_t *payload, size_t payload_length,
                             uint8_t **output, size_t *output_length,
                             char *error, size_t error_capacity) {
  lambda_aitia_python_session *session =
      lambda_aitia_python_open(library_path, error, error_capacity);
  int status;
  if (session == NULL) return -101;
  status = lambda_aitia_python_session_call(
      session, operation, payload, payload_length, output, output_length,
      error, error_capacity);
  lambda_aitia_python_close(session);
  return status;
}
