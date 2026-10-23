;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test check-equal? test-case test-suite)
        (only-in :agentic-ai-lab/core/module-system/source/objects
                 agentic-ai-lab-module-source-ref-metadata
                 agentic-ai-lab-module-source-ref-value)
        (only-in :yuanxu/module-system/source/collection make-agentic-ai-lab-contribution-module-source agentic-ai-lab-module-source-collection-interfaces))

(export lambda-aitia-source-collection-test)

(def (metadata-ref source-ref key)
  (let (entry (assq key (agentic-ai-lab-module-source-ref-metadata source-ref)))
    (and entry (cdr entry))))

(def lambda-aitia-module-source
  (make-agentic-ai-lab-contribution-module-source
   'lambda-aitia "."))

(def lambda-aitia-source-collection-test
  (test-suite "Aitia module ownership and registered load path"
    (test-case "Aitia discovers its complete software engineering module set"
      (let (sources (agentic-ai-lab-module-source-collection-interfaces lambda-aitia-module-source))
        (check-equal?
         (map agentic-ai-lab-module-source-ref-value sources)
         '("modules/ADR/interface.ss"
           "modules/assurance/interface.ss"
           "modules/formal-methods/interface.ss"
           "modules/gitops/interface.ss"
           "modules/sdlc/interface.ss"))
        (check-equal?
         (map (lambda (source) (metadata-ref source 'module-key)) sources)
         '((custom . ADR) (custom . assurance) (custom . formal-methods)
           (custom . gitops) (custom . sdlc)))))

    (test-case "the package-local GitOps module retains Aitia ownership"
      (let* ((sources (agentic-ai-lab-module-source-collection-interfaces lambda-aitia-module-source))
             (source (list-ref sources 3)))
        (check-equal? (metadata-ref source 'source-collection) 'lambda-aitia)
        (check-equal?
         (agentic-ai-lab-module-source-ref-value source)
         "modules/gitops/interface.ss")))))
