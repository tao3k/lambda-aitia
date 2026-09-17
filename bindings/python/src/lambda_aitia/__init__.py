# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
#
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

"""Python access to Lambda Aitia's Scheme-owned assurance decisions."""

from .native import AitiaNativeError, descriptor, evaluate_gitops

__all__ = ["AitiaNativeError", "descriptor", "evaluate_gitops"]
