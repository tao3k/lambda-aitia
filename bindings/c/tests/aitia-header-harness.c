// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
//
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#include "lambda_aitia/aitia.h"

#include <stddef.h>

_Static_assert(offsetof(poo_flow_aitia_result, status) == 0u,
               "status must be the first field");
_Static_assert(offsetof(poo_flow_aitia_result, payload) >
                   offsetof(poo_flow_aitia_result, status),
               "payload must follow status");
_Static_assert(offsetof(poo_flow_aitia_result, length) >
                   offsetof(poo_flow_aitia_result, payload),
               "length must follow payload");

int main(void) { return POO_FLOW_AITIA_ABI_REVISION == 1u ? 0 : 1; }
