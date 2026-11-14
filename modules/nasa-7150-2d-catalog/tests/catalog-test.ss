;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :clan/poo/object .get)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export catalog-test)

(def catalog-test
  (test-suite "NASA catalog publication"
    (yuanxu-test-case "the catalog exposes the Appendix C source digest"
      (let (digests (.get lambda-aitia.init.exports modules
                          nasa-7150-2d-catalog source-digests))
        (check-equal? (.get digests appendix-c)
                      "43db1ee92db397ab03d7e1446641154c9cbcc3c47505c33acb1c1f4ba2c81570")))))
