// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#include "lambda_aitia/aitia.h"

#include <stddef.h>

_Static_assert(offsetof(agentic_ai_lab_aitia_result, status) == 0u,
               "status must be the first field");
_Static_assert(offsetof(agentic_ai_lab_aitia_result, payload) >
                   offsetof(agentic_ai_lab_aitia_result, status),
               "payload must follow status");
_Static_assert(offsetof(agentic_ai_lab_aitia_result, length) >
                   offsetof(agentic_ai_lab_aitia_result, payload),
               "length must follow payload");

int main(void) { return AGENTIC_AI_LAB_AITIA_ABI_REVISION == 2u ? 0 : 1; }
