;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :poo-flow/src/module-system/loader/source
                 poo-flow-module-source-ref-metadata
                 poo-flow-module-source-ref-value)
        (only-in :poo-flow/src/module-system/loader/module-source-interface
                 make-poo-flow-contribution-module-source
                 poo-flow-load-modules))

(export lambda-aitia-source-collection-test)

(def (metadata-ref source-ref key)
  (let (entry (assq key (poo-flow-module-source-ref-metadata source-ref)))
    (and entry (cdr entry))))

(def lambda-aitia-module-source
  (make-poo-flow-contribution-module-source
   'lambda-aitia "."))

(def lambda-aitia-source-collection-test
  (test-suite "Aitia module ownership and registered load path"
    (test-case "Aitia discovers ADR, Assurance, GitOps and SDLC as its public modules"
      (let (sources (poo-flow-load-modules lambda-aitia-module-source))
        (check-equal?
         (map poo-flow-module-source-ref-value sources)
         '("modules/ADR/interface.ss"
           "modules/assurance/interface.ss"
           "modules/gitops/interface.ss"
           "modules/sdlc/interface.ss"))
        (check-equal?
         (map (lambda (source) (metadata-ref source 'module-key)) sources)
         '((custom . ADR) (custom . assurance) (custom . gitops)
           (custom . sdlc)))))

    (test-case "the package-local GitOps module retains Aitia ownership"
      (let* ((sources (poo-flow-load-modules lambda-aitia-module-source))
             (source (caddr sources)))
        (check-equal? (metadata-ref source 'source-collection) 'lambda-aitia)
        (check-equal?
         (poo-flow-module-source-ref-value source)
         "modules/gitops/interface.ss")))))
