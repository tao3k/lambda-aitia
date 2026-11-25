;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later


(import (only-in :clan/poo/object .def)
        "types.ss"
        "objects.ss")
(export Feature)

(.def Feature
  refine: enable-github
  contract: GitHubFeatureContract)
