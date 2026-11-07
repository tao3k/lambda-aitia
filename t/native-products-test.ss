;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test (only-in :std/error Error?)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/process run-process)
        (only-in :yuanxu/module-system/building/artifacts
                 require-build-products! repair-build-products!))
(export native-products-test)
(def native-products-test
  (test-suite "Native compiler product custody"
    (test-case "Actual ASCENT macro phase is required independently of SSI"
      (def libdir (path-expand "lib" (gerbil-path)))
      (def identity 'gerbil-ascent/table/eqrel)
      (require-build-products! (list identity) libdir)
      (call-with-temporary-directory "aitia-native-products"
        (lambda (temporary)
          (def directory (path-expand "gerbil-ascent/table" temporary))
          (create-directory* directory)
          ;; Copy real compiler products; never invent an SSI or object.
          (for-each
            (lambda (name)
              (when (string-prefix? "eqrel." name)
                (copy-file (path-expand name (path-expand "gerbil-ascent/table" libdir))
                           (path-expand name directory)))
              (when (string-prefix? "eqrel~" name)
                (copy-file (path-expand name (path-expand "gerbil-ascent/table" libdir))
                           (path-expand name directory))))
            (directory-files (path-expand "gerbil-ascent/table" libdir)))
          (require-build-products! (list identity) temporary)
          (delete-file (path-expand "eqrel~1.o1" directory))
          (check-exception (require-build-products! (list identity) temporary) Error?)
          (repair-build-products! (list identity) temporary)
          (check-exception (require-build-products! (list identity) temporary) Error?)
          ;; Invalidating an incomplete unit must preserve genuine evidence.
          (check (file-exists? (path-expand "eqrel.ssi" directory)) => #t)
          (check (file-exists? (path-expand "eqrel~1.scm" directory)) => #t))))
    (test-case "Generated compiler products are absent from the Git source set"
      (check
       (run-process
        '("git" "ls-files" "*.ssi" "*.ssxi.ss" "*.o[0-9]*" "*.gxc-complete")
        coprocess: (lambda (port) (read-line port)))
       => #!eof))))
