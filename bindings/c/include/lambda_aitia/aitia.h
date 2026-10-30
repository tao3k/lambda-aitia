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
#define AGENTIC_AI_LAB_AITIA_ABI_REVISION 2u

typedef struct {
  int32_t status;
  /* Owned UTF-8 bytes, NUL-terminated; length excludes the NUL byte. */
  uint8_t *payload;
  size_t length;
} agentic_ai_lab_aitia_result;

int32_t agentic_ai_lab_aitia_runtime_init(void);
void agentic_ai_lab_aitia_runtime_shutdown(void);
void agentic_ai_lab_aitia_result_init(agentic_ai_lab_aitia_result *result);
void agentic_ai_lab_aitia_result_release(agentic_ai_lab_aitia_result *result);
uint32_t agentic_ai_lab_aitia_abi_revision(void);
int32_t agentic_ai_lab_aitia_descriptor(agentic_ai_lab_aitia_result *result);
int32_t agentic_ai_lab_aitia_sdlc_flow_plan(char *payload,
                                      agentic_ai_lab_aitia_result *result);
int32_t agentic_ai_lab_aitia_gitops_evaluate(char *payload,
                                       agentic_ai_lab_aitia_result *result);

#ifdef __cplusplus
}
#endif

#endif
