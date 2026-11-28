;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :tao3k/yuanxu/profile-composition/profile-bundle
                 yuanxu-profile-export yuanxu-module-profiles)
        (only-in :tao3k/yuanxu/module-system/schema/relations yuanxu-semantic-identity)
        (only-in :tao3k/yuanxu/module-system/authoring/roles yuanxu-semantic-module)
        "actions.ss")
(export make-delivery-profile-module)

(def (make-delivery-profile-module dev staging production)
  (yuanxu-semantic-module
   (yuanxu-semantic-identity 'software-engineering 'delivery)
   profiles: (yuanxu-module-profiles
              (yuanxu-profile-export 'actions actions)
              (yuanxu-profile-export 'dev dev)
              (yuanxu-profile-export 'staging staging)
              (yuanxu-profile-export 'production production))))
