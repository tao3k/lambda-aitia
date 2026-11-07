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
                 testing-interface-max-heap-mib-for
                 testing-test-selector)
        :std/list/list
        (only-in :agentic-ai-lab/dev/modules/testing/testing-extension
                 make-agentic-ai-lab-testing-observability-profile
                 agentic-ai-lab-testing-observability-extension))

(export +lambda-aitia-testing-interface+
        lambda-aitia-sdlc-unit-testing-interface
        lambda-aitia-sdlc-unit-test-order)

(def +lambda-aitia-atomic-test-selector+
  (testing-test-selector 'contains "-test.ss"))

(def +lambda-aitia-source-admission-selector+
  (testing-test-selector 'contains "source-admission-test.ss"))

(def +lambda-aitia-module-test-selector+
  (testing-test-selector 'contains "/tests/"))

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

(def (observed-testing-interface testing)
  (agentic-ai-lab-testing-observability-extension
   (foldl
    (lambda (selector receiver)
      (testing-interface-map-profile receiver selector +testing-serial-resource-profile+))
    testing
    (list +lambda-aitia-source-admission-selector+ +lambda-aitia-module-test-selector+))
   (make-agentic-ai-lab-testing-observability-profile
    'lambda-aitia/testing 5)))

(def +lambda-aitia-testing-interface+
  (observed-testing-interface
   (testing-interface-map-profile
    +lambda-aitia-bounded-testing-interface+
    +lambda-aitia-atomic-test-selector+
    +testing-process-isolation-profile+)))

;; Catalog fixtures can share imports inside their existing 2 GiB
;; profile. Keep the ordinary 512 MiB fixtures process-isolated.
(def (lambda-aitia-sdlc-unit-testing-interface files)
  (observed-testing-interface
   (foldl
    (lambda (file testing)
      (if (= (testing-interface-max-heap-mib-for testing file) 512)
        (testing-interface-map-profile testing file +testing-process-isolation-profile+)
        testing))
    +lambda-aitia-bounded-testing-interface+
    files)))

;; Give the catalog batches a head start. ASP dispatches batches in input
;; order, so late catalog imports can otherwise overlap the last few fixtures.
(def (lambda-aitia-sdlc-unit-test-order testing files)
  (let-values (((catalog ordinary)
                (partition
                 (lambda (file)
                   (= (testing-interface-max-heap-mib-for testing file) 2048))
                 files)))
    (append catalog ordinary)))
