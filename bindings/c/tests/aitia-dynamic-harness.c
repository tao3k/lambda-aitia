// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#include "lambda_aitia/aitia.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE library_handle;
typedef FARPROC library_symbol;
#define LIBRARY_OPEN(path) LoadLibraryA(path)
#define LIBRARY_SYMBOL(handle, name) GetProcAddress(handle, name)
#define LIBRARY_CLOSE(handle) FreeLibrary(handle)
#else
#include <dlfcn.h>
typedef void *library_handle;
typedef void *library_symbol;
#define LIBRARY_OPEN(path) dlopen(path, RTLD_NOW | RTLD_LOCAL)
#define LIBRARY_SYMBOL(handle, name) dlsym(handle, name)
#define LIBRARY_CLOSE(handle) dlclose(handle)
#endif

typedef uint32_t (*abi_revision_fn)(void);
typedef int32_t (*runtime_init_fn)(void);
typedef void (*runtime_shutdown_fn)(void);
typedef int32_t (*descriptor_fn)(poo_flow_aitia_result *);
typedef int32_t (*payload_operation_fn)(char *, poo_flow_aitia_result *);
typedef void (*result_init_fn)(poo_flow_aitia_result *);
typedef void (*result_release_fn)(poo_flow_aitia_result *);

static int load_symbol(library_handle library, const char *name,
                       void *destination, size_t destination_size) {
  library_symbol symbol = LIBRARY_SYMBOL(library, name);
  if (symbol == NULL || destination_size != sizeof(symbol)) return 0;
  memcpy(destination, &symbol, sizeof(symbol));
  return 1;
}

static void native_phase(const char *phase) {
  (void)fprintf(stderr, "[lambda-aitia-native] phase=%s\n", phase);
  (void)fflush(stderr);
}

int main(int argc, char **argv) {
  library_handle library;
  abi_revision_fn abi_revision;
  runtime_init_fn runtime_init;
  runtime_shutdown_fn runtime_shutdown;
  descriptor_fn descriptor;
  payload_operation_fn sdlc_flow_plan;
  result_init_fn result_init;
  result_release_fn result_release;
  poo_flow_aitia_result result;
  char plan_input[] = "{\"lifecycle-id\":\"release/42\"}";

  if (argc != 2) return 64;
  native_phase("library-open-start");
  library = LIBRARY_OPEN(argv[1]);
  if (library == NULL) {
#if defined(_WIN32)
    (void)fprintf(stderr, "unable to load Lambda Aitia library\n");
#else
    (void)fprintf(stderr, "%s\n", dlerror());
#endif
    return 1;
  }
  native_phase("library-open-complete");
  if (!load_symbol(library, "poo_flow_aitia_runtime_init", &runtime_init,
                   sizeof(runtime_init)) ||
      !load_symbol(library, "poo_flow_aitia_runtime_shutdown",
                   &runtime_shutdown, sizeof(runtime_shutdown)) ||
      !load_symbol(library, "poo_flow_aitia_abi_revision", &abi_revision,
                   sizeof(abi_revision)) ||
      !load_symbol(library, "poo_flow_aitia_descriptor", &descriptor,
                   sizeof(descriptor)) ||
      !load_symbol(library, "poo_flow_aitia_sdlc_flow_plan", &sdlc_flow_plan,
                   sizeof(sdlc_flow_plan)) ||
      !load_symbol(library, "poo_flow_aitia_result_init", &result_init,
                   sizeof(result_init)) ||
      !load_symbol(library, "poo_flow_aitia_result_release", &result_release,
                   sizeof(result_release))) {
    LIBRARY_CLOSE(library);
    return 2;
  }
  native_phase("symbols-complete");
  if (runtime_init() != 0) {
    LIBRARY_CLOSE(library);
    return 3;
  }
  native_phase("runtime-init-complete");
  if (abi_revision() != POO_FLOW_AITIA_ABI_REVISION) {
    runtime_shutdown();
    LIBRARY_CLOSE(library);
    return 4;
  }
  native_phase("abi-revision-complete");
  result_init(&result);
  if (descriptor(&result) != 0 || result.status != 0 ||
      result.payload == NULL || result.length == 0 ||
      strstr((const char *)result.payload, "lambda-aitia.native-descriptor") ==
          NULL) {
    result_release(&result);
    runtime_shutdown();
    LIBRARY_CLOSE(library);
    return 5;
  }
  native_phase("descriptor-complete");
  result_release(&result);
  if (result.payload != NULL || result.length != 0 || result.status != 0) {
    runtime_shutdown();
    LIBRARY_CLOSE(library);
    return 6;
  }
  native_phase("descriptor-release-complete");
  if (sdlc_flow_plan(plan_input, &result) != 0 || result.status != 0 ||
      result.payload == NULL ||
      strstr((const char *)result.payload, "lambda-aitia.sdlc-flow-plan") ==
          NULL ||
      strstr((const char *)result.payload, "release/42/effect") == NULL) {
    result_release(&result);
    runtime_shutdown();
    LIBRARY_CLOSE(library);
    return 7;
  }
  native_phase("sdlc-flow-plan-complete");
  result_release(&result);
  native_phase("sdlc-flow-plan-release-complete");
  runtime_shutdown();
  native_phase("runtime-shutdown-complete");
  LIBRARY_CLOSE(library);
  native_phase("library-close-complete");
  return 0;
}
