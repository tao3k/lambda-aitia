;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Lambda Aitia projects NASA NPR 7150.2D into the domain-neutral
;;; Agentic AI Lab Standards protocol.  Source bytes remain behind an explicit POO
;;; Provider and are not read while the module, catalog, or Profile is loaded.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :gerbil/core path-expand)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/feature-system/source-lock-feature
                 require-source-lock-payload)
        (only-in :agentic-ai-lab/modules/standards/interface
                 AgenticAILabStandardValidationProvider.
                 agentic-ai-lab-standard-artifact
                 agentic-ai-lab-standard-artifact-ref
                 agentic-ai-lab-standard-artifact-source
                 agentic-ai-lab-standard-budget
                 agentic-ai-lab-standard-catalog
                 agentic-ai-lab-standard-digest
                 agentic-ai-lab-standard-edition-ref
                 agentic-ai-lab-standard-family
                 agentic-ai-lab-standard-make-validation-closure
                 agentic-ai-lab-standard-materialization-context
                 agentic-ai-lab-standard-resolve
                 agentic-ai-lab-standard-resolution-receipt-bundle
                 agentic-ai-lab-standard-resolution-receipt-valid?
                 agentic-ai-lab-standard-constraint-profile
                 agentic-ai-lab-standard-materialize
                 agentic-ai-lab-standard-materialization-receipt-valid?
                 agentic-ai-lab-standards-module)
        "sources.ss"
        :agentic-ai-lab/lambda-aitia/modules/sdlc/standards/nasa-7150-2d-catalog)

(export Nasa7150_2DStandardFamily
        Nasa7150_2DSourceProvider.
        nasa-7150-2d-local-source-provider
        nasa-7150-2d-standard-provider
        nasa-7150-2d-standard-catalog
        nasa-7150-2d-standards-module
        nasa-7150-2d-resolve
        nasa-7150-2d-validation-closure
        nasa-7150-2d-materialize-sources)

(def +nasa-7150-2d-provider-identity+ "lambda-aitia/nasa/sdlc/npr-7150.2/D")

(def Nasa7150_2DStandardFamily
  (agentic-ai-lab-standard-family
   "nasa/sdlc/npr-7150.2" "NASA" 'sdlc
   '(html scheme) "publicly-available-nasa-directive"
   '((contributor . lambda-aitia)
     (authority . nasa-nodis))))

;;; Filesystem choice is an explicit runtime Provider slot.  A caller may
;;; derive this prototype for another admitted source store without changing
;;; the Standard edition or its content identities.
(def Nasa7150_2DSourceProvider.
  (.o kind: 'lambda-aitia.nasa-source-provider
      identity: "lambda-aitia/nasa-source/abstract"
      root: #f
      .read-source:
      (lambda (relative-path)
        (error "abstract NASA source Provider cannot read" relative-path))))

(def (nasa-7150-2d-local-source-provider root-value)
  (unless (and (string? root-value) (> (string-length root-value) 0))
    (error "NASA source Provider root must be non-empty" root-value))
  (.o (:: @ Nasa7150_2DSourceProvider.)
      identity: "lambda-aitia/nasa-source/local"
      root: root-value
      .read-source:
      (lambda (relative-path)
        (call-with-input-file
         (path-expand relative-path root-value)
         read-all-as-string))))

(def (nasa-source-provider? value)
  (and (object? value)
       (.slot? value '.read-source)
       (procedure? (.ref value '.read-source))))

(def (nasa-source-artifact-ref source-provider-value lock-value spec-value)
  (let* ((identity-value (.ref spec-value 'identity))
         (digest-value (.ref spec-value 'digest))
         (relative-path-value (.ref spec-value 'path))
         (representation-value (.ref spec-value 'representation))
         (size-bytes-value (.ref spec-value 'size-bytes))
         (source-loader-value
          (lambda ()
            (let* ((payload-value
                    ((.ref source-provider-value '.read-source)
                     relative-path-value))
                   (lock-receipt-value
                    (require-source-lock-payload
                     lock-value identity-value payload-value)))
              (agentic-ai-lab-standard-artifact-source
               identity-value digest-value representation-value
               payload-value size-bytes-value
               (list (cons 'source-path relative-path-value)
                     (cons 'source-lock-receipt lock-receipt-value))))))
         (materializer-value
          (lambda (source-value)
            (agentic-ai-lab-standard-artifact
             identity-value digest-value representation-value
             (.ref source-value 'payload)
             (list (cons 'source-url (.ref spec-value 'canonical-uri))
                   (cons 'source-lock-digest
                         (.ref lock-value 'digest)))))))
    (agentic-ai-lab-standard-artifact-ref
     identity-value (.ref spec-value 'canonical-uri)
     (.ref spec-value 'exact-version)
     'normative-source representation-value digest-value '() size-bytes-value
     source-loader-value materializer-value
     (list (cons 'source-lock-id (.ref lock-value 'lock-id))))))

(def (nasa-7150-2d-standard-provider source-provider-value)
  (unless (nasa-source-provider? source-provider-value)
    (error "invalid NASA Standard source Provider" source-provider-value))
  (let* ((lock Nasa7150_2DSourcesLock)
         (artifacts
          (map (lambda (spec)
                 (nasa-source-artifact-ref source-provider-value lock spec))
               (.ref lock 'entries)))
         (artifact-identities (map (lambda (value) (.ref value 'identity)) artifacts))
         (edition-digest
          (agentic-ai-lab-standard-digest
           (map (lambda (value) (.ref value 'digest)) artifacts)))
         (edition-value
          (agentic-ai-lab-standard-edition-ref
           +nasa-7150-2d-edition-identity+ Nasa7150_2DStandardFamily
           +nasa-7150-2d-edition-canonical-uri+ "D"
           "NPR 7150.2D" 'us-federal edition-digest
           +nasa-7150-2d-source-ref+
           '() artifacts artifact-identities 'active
           '((effective . "2022-03-08") (expires . "2027-03-08"))
           (list (cons 'owner 'lambda-aitia)
                 (cons 'sources-lock-digest (.ref lock 'digest)))))
         (profile-value
          (agentic-ai-lab-standard-constraint-profile
           "lambda-aitia/nasa-npr-7150.2d/full" "2026-09-17"
           (list +nasa-7150-2d-edition-identity+)
           nasa-requirement-catalog '() artifact-identities '()
           (list (cons 'source 'nasa-nodis)
                 (cons 'owner 'lambda-aitia)
                 (cons 'sources-lock-digest (.ref lock 'digest)))
           'source-reviewed)))
    (.o (:: @ AgenticAILabStandardValidationProvider.)
        identity: +nasa-7150-2d-provider-identity+
        supported-families: (list (.ref Nasa7150_2DStandardFamily 'identity))
        source-provider: source-provider-value
        sources-lock: lock
        edition: edition-value
        constraint-profile: profile-value)))

(def (nasa-7150-2d-standard-catalog provider)
  (agentic-ai-lab-standard-catalog
   "lambda-aitia/nasa-npr-7150.2d/catalog"
   (list (.ref provider 'edition))
   '((selection . exact-edition))))

(def (nasa-7150-2d-standards-module source-provider)
  (let* ((provider (nasa-7150-2d-standard-provider source-provider))
         (catalog (nasa-7150-2d-standard-catalog provider)))
    (agentic-ai-lab-standards-module
     "lambda-aitia/modules/sdlc/standards/nasa-npr-7150.2d"
     catalog
     (agentic-ai-lab-standard-budget 1 6 2 250000 32)
     (.o nasa: provider))))

(def (nasa-7150-2d-resolve standards-module terminology-snapshot-digest)
  (agentic-ai-lab-standard-resolve
   (.ref standards-module 'catalog)
   (list +nasa-7150-2d-edition-identity+)
   (.ref standards-module 'budget)
   terminology-snapshot-digest))

(def (nasa-7150-2d-validation-closure standards-module subject-kind
                                      subject-snapshot-digest)
  (let* ((resolution
          (nasa-7150-2d-resolve
           standards-module
           (agentic-ai-lab-standard-digest 'nasa-7150-2d/no-terminology)))
         (provider (.ref (.ref standards-module 'providers) 'nasa)))
    (unless (agentic-ai-lab-standard-resolution-receipt-valid? resolution)
      (error "NASA Standard resolution failed" resolution))
    (agentic-ai-lab-standard-make-validation-closure
     "lambda-aitia/nasa-npr-7150.2d/validation-closure"
     (agentic-ai-lab-standard-resolution-receipt-bundle resolution)
     (.ref provider 'identity) subject-kind subject-snapshot-digest
     (.ref (.ref provider 'constraint-profile) 'constraints))))

(def (nasa-7150-2d-materialize-sources standards-module)
  (let* ((resolution
          (nasa-7150-2d-resolve
           standards-module
           (agentic-ai-lab-standard-digest 'nasa-7150-2d/no-terminology)))
         (bundle (agentic-ai-lab-standard-resolution-receipt-bundle resolution))
         (context
          (agentic-ai-lab-standard-materialization-context
           "lambda-aitia/nasa-npr-7150.2d/materialization"
           (.ref bundle 'artifacts))))
    (map
     (lambda (artifact)
       (let (receipt
             (agentic-ai-lab-standard-materialize context (.ref artifact 'identity)))
         (unless (agentic-ai-lab-standard-materialization-receipt-valid? receipt)
           (error "NASA Standard materialization failed" receipt))
         receipt))
     (.ref bundle 'artifacts))))
