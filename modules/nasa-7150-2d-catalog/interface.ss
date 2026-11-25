;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .def))
(.def NasaCatalog
  identity: 'nasa-7150-2d-catalog
  tags: '(software-engineering standards)
  core: (.o scope-contract: NasaCatalogScopeContract
            exports: Config)
  features: (.o))
