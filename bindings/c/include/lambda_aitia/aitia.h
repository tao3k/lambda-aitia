// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#ifndef LAMBDA_AITIA_AITIA_H
#define LAMBDA_AITIA_AITIA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public names stay stable; negotiate this metadata before calling. */
#define POO_FLOW_AITIA_ABI_REVISION 1u

typedef struct {
  int32_t status;
  /* Owned UTF-8 bytes, NUL-terminated; length excludes the NUL byte. */
  uint8_t *payload;
  size_t length;
} poo_flow_aitia_result;

int32_t poo_flow_aitia_runtime_init(void);
void poo_flow_aitia_runtime_shutdown(void);
void poo_flow_aitia_result_init(poo_flow_aitia_result *result);
void poo_flow_aitia_result_release(poo_flow_aitia_result *result);
uint32_t poo_flow_aitia_abi_revision(void);
int32_t poo_flow_aitia_descriptor(poo_flow_aitia_result *result);
int32_t poo_flow_aitia_gitops_evaluate(char *payload,
                                       poo_flow_aitia_result *result);

#ifdef __cplusplus
}
#endif

#endif
