;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Declarative test Profiles.  Gerbil test remains the execution framework.
(import (only-in :clan/poo/object .cc)
        (only-in :asp-gerbil-scheme/testing-api
                 +asp-testing-interface+
                 +testing-memory-profile+
                 +testing-process-isolation-profile+
                 +testing-serial-resource-profile+
                 testing-interface-add-profile
                 testing-interface-map-profile
                 testing-test-selector)
        (only-in :std/srfi/1 foldl)
        (only-in :poo-flow/src/module-system/observability/testing-extension
                 make-poo-flow-testing-observability-profile
                 poo-flow-testing-observability-extension))

(export +lambda-aitia-testing-interface+)

(def +lambda-aitia-atomic-test-selector+
  (testing-test-selector 'contains "-test.ss"))

(def +lambda-aitia-source-admission-selector+
  (testing-test-selector 'contains "source-admission-test.ss"))

(def +lambda-aitia-catalog-memory-profile+
  (.cc +testing-memory-profile+ maxHeapMiB: 2048))

;;; The default test process is 512 MiB. Only tests that load the complete NASA
;;; catalog or prepare the complete SDLC source graph receive the bounded 2 GiB
;;; profile; no Aitia test is allowed to inherit an unbounded Gambit heap.
(def +lambda-aitia-large-memory-selectors+
  (map (lambda (fragment) (testing-test-selector 'contains fragment))
       '("nasa-" "sdlc-trace-test.ss" "source-admission-test.ss")))

(def +lambda-aitia-bounded-testing-interface+
  (foldl
   (lambda (selector testing)
     (testing-interface-map-profile
      testing selector +lambda-aitia-catalog-memory-profile+))
   (testing-interface-add-profile
    +asp-testing-interface+
    (.cc +testing-memory-profile+ maxHeapMiB: 512))
   +lambda-aitia-large-memory-selectors+))

(def +lambda-aitia-testing-interface+
  (poo-flow-testing-observability-extension
   (testing-interface-map-profile
    (testing-interface-map-profile
     +lambda-aitia-bounded-testing-interface+
     +lambda-aitia-atomic-test-selector+
     +testing-process-isolation-profile+)
    +lambda-aitia-source-admission-selector+
    +testing-serial-resource-profile+)
   (make-poo-flow-testing-observability-profile
    'lambda-aitia/testing 5)))
