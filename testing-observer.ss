;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/list/list
        (only-in :clan/poo/object .call .get)
        (only-in :gerbil/core string-contains string-prefix? string-suffix?)
        (only-in :std/string/misc string-trim-prefix)
        (only-in :asp-gerbil-scheme/testing-api
                 testing-interface-run-test-files!)
        (only-in :asp-gerbil-scheme/testing-runner-api
                 testing-interface-test-files)
        (only-in "./testing-interface.ss"
                 +lambda-aitia-testing-interface+
                 lambda-aitia-sdlc-unit-testing-interface
                 lambda-aitia-sdlc-unit-test-order))

(export run-observed-test
        run-observed-module-tests
        lambda-aitia-selected-test-files)

(def (emit phase test-path)
  (display "[lambda-aitia-testing] phase=")
  (display phase)
  (display " test=")
  (display test-path)
  (newline)
  (force-output))

(def (emit-selection test-path file-count)
  (display "[lambda-aitia-testing] phase=selection-complete test=")
  (display test-path)
  (display " fileCount=")
  (display file-count)
  (newline)
  (force-output))

(def (lambda-aitia-selected-test-files test-path)
  (let* ((normalized-test-path (string-trim-prefix "./" test-path))
         (test-files
        (if (and (string-suffix? ".ss" normalized-test-path)
                 (file-exists? normalized-test-path))
          (list normalized-test-path)
          (let* ((package-local?
                  (or (equal? normalized-test-path "t")
                      (string-prefix? "t/" normalized-test-path)))
                 (test-boundary
                  (and (not package-local?)
                       (string-contains normalized-test-path "/t/"))))
            (unless (or package-local? (fixnum? test-boundary))
              (error "Lambda Aitia test directory is outside a package t/ tree"
                     normalized-test-path))
            (let* ((package-root
                    (if package-local?
                      "."
                      (if (fixnum? test-boundary)
                        (substring normalized-test-path 0 test-boundary)
                        (error "Lambda Aitia test boundary is not an index"
                               normalized-test-path))))
                   (directory-prefix
                    (string-append
                     (if package-local? "./" "")
                     normalized-test-path
                     (if (string-suffix? "/" normalized-test-path) "" "/"))))
              (filter
               (lambda (path) (string-prefix? directory-prefix path))
               (testing-interface-test-files
                +lambda-aitia-testing-interface+
                normalized-test-path
                pkgdir: package-root)))))))
    (when (null? test-files)
      (error "no Lambda Aitia test files selected" test-path))
    test-files))

(def (run-observed-files label test-files)
  (emit-selection label (length test-files))
  (if (and (equal? label "t/sdlc")
           (every (lambda (path) (string-prefix? "./t/sdlc/unit/" path)) test-files))
    (let (testing (lambda-aitia-sdlc-unit-testing-interface test-files))
      (testing-interface-run-test-files!
       testing (lambda-aitia-sdlc-unit-test-order testing test-files)))
    (testing-interface-run-test-files! +lambda-aitia-testing-interface+ test-files)))

(def (run-observed-test test-path)
  (emit 'native-test-process-start test-path)
  (run-observed-files test-path (lambda-aitia-selected-test-files test-path))
  (emit 'native-test-process-complete test-path))

(def (run-observed-module-tests init-exports owners)
  (let* ((selection (.call (.get init-exports tests) .select owners))
         (files (.get selection spec))
         (admit-current (.get selection admit-current)))
    (unless (pair? files)
      (error "no tests declared by selected Aitia modules" owners))
    (emit 'native-test-process-start owners)
    (dynamic-wind admit-current
      (lambda () (run-observed-files owners files))
      admit-current)
    (emit 'native-test-process-complete owners)))
