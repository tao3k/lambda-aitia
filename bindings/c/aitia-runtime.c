// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/* ___VERSION and POO_FLOW_AITIA_LINKER come from the generated link unit. */
#include "gambit.h"

#include <stdint.h>
#include <stdio.h>

#ifndef POO_FLOW_AITIA_LINKER
#error "POO_FLOW_AITIA_LINKER must name the generated Gambit link-unit linker"
#endif

___BEGIN_NEW_LNK
___DEF_NEW_LNK(POO_FLOW_AITIA_LINKER)
___END_NEW_LNK

static int poo_flow_aitia_runtime_initialized = 0;

int32_t poo_flow_aitia_runtime_init(void) {
  ___setup_params_struct setup_params;
  ___SCMOBJ status;

  if (poo_flow_aitia_runtime_initialized) return 0;
  ___setup_params_reset(&setup_params);
  setup_params.version = ___VERSION;
  setup_params.linker = POO_FLOW_AITIA_LINKER;
  /* Embedded callers must report uncaught Scheme errors without a REPL. */
  setup_params.debug_settings = ___DEBUG_SETTINGS_INITIAL;
  status = ___setup(&setup_params);
  if (status != ___FIX(___NO_ERR)) {
    (void)fprintf(stderr, "[lambda-aitia-native] setup-error=%ld\n",
                  (long)___INT(status));
    return -1;
  }
  poo_flow_aitia_runtime_initialized = 1;
  return 0;
}

void poo_flow_aitia_runtime_shutdown(void) {
  if (!poo_flow_aitia_runtime_initialized) return;
  ___cleanup();
  poo_flow_aitia_runtime_initialized = 0;
}
