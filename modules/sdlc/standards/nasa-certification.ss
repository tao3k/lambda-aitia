;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; NPR 7150.2D compliance dossier and independently verified authority decision.
;;; This module never impersonates NASA, authenticates a signer, or authorizes release.
(import (only-in :clan/poo/mop validate)
        (only-in :clan/poo/object .get .o .ref .slot? object?)
        :tao3k/yuanxu/contribution/verification
        "../types.ss"
        (only-in "nasa-7150-2d-profile.ss" Nasa7150_2D)
        :std/list/list
        :std/list/list
        (only-in :gerbil/runtime/hash list->hash-table-string))

(export SdlcComplianceDossier
        SdlcCertificationDecision
        sdlc-compliance-dossier?
        sdlc-certification-decision?
        nasa-compliance-dossier
        nasa-certification-decision
        nasa-certification-verification-request
        nasa-certification-verification-adapter
        nasa-certification-review)

;;; NASA owns its submission and authority-decision object family. Keeping the
;;; family beside its operations bounds incremental invalidation to this module.
(def (text-slot name)
  (sdlc-record-field name type-predicate: sdlc-text?))
(def SdlcComplianceDossier
  (sdlc-record-type 'sdlc/compliance-dossier
    direct-superclasses: (list SdlcBoundFact)
    direct-slots:
    (append
     (map text-slot '(identity standard edition))
     (list
      (sdlc-record-field 'software-class type-predicate: symbol?)
      (sdlc-record-field 'mapping-matrix-digest type-predicate: sdlc-artifact-digest?)
      (sdlc-record-field 'project-gate type-predicate: object?)
      (sdlc-record-field 'institution-gate type-predicate: object?)
      (sdlc-record-field 'complete? type-predicate: boolean?)))))
(def SdlcCertificationDecision
  (sdlc-record-type 'sdlc/certification-decision
    direct-superclasses: (list SdlcBoundFact)
    direct-slots:
    (append
     (map text-slot '(identity dossier signer record))
     (list
      (sdlc-record-field 'authority type-predicate: symbol?)
      (sdlc-record-field
       'decision type-predicate:
       (lambda (value) (if (memq value '(compliant noncompliant)) #t #f)))))))
(def (sdlc-compliance-dossier? value)
  (sdlc-record? SdlcComplianceDossier value))
(def (sdlc-certification-decision? value)
  (sdlc-record? SdlcCertificationDecision value))

(def (bound? value project)
  (every (lambda (slot)
           (equal? (.ref value slot) (.ref project slot)))
         '(subject revision scope)))

(def (exact-requirements? gate expected)
  (let* ((actual (.ref gate 'requirements))
         (actual-index
          (list->hash-table-string
           (map (lambda (identity) (cons identity #t)) actual))))
    (and (= (length actual) (length expected))
         (= (length actual) (length (delete-duplicates/hash actual)))
         (every (lambda (id) (hash-key? actual-index id)) expected))))

(def (eligible-gate? gate scope-value expected)
  (and (object? gate)
       (every (lambda (slot) (.slot? gate slot))
              '(stage status assessment-scope requirements admitted?
                reported-failures release-authorized?))
       (eq? (.ref gate 'assessment-scope) scope-value)
       (eq? (.ref gate 'status) 'stage-admitted)
       (eq? (.ref gate 'admitted?) #t)
       (eq? (.ref gate 'release-authorized?) #f)
       (null? (.ref gate 'reported-failures))
       (exact-requirements? gate expected)))

(def (catalog-identities institutional?)
  (map (lambda (row) (.ref row 'identity))
       (filter (lambda (row)
                 (eq? (not (.slot? row 'class-matrix)) institutional?))
               (.get Nasa7150_2D requirements))))

(def nasa-project-requirement-identities (catalog-identities #f))
(def nasa-institution-requirement-identities (catalog-identities #t))

(def (nasa-compliance-dossier identity-value project class-value matrix-digest
                              project-gate-value institution-gate-value)
  (unless (and (sdlc-project? project)
               (memq class-value '(a b c d e f))
               (sdlc-artifact-digest? matrix-digest))
    (error "invalid NASA compliance dossier inputs"))
  (let* ((complete-value
          (and (.ref project 'complete?)
               (eligible-gate? project-gate-value 'project
                               nasa-project-requirement-identities)
               (eligible-gate? institution-gate-value 'institution
                               nasa-institution-requirement-identities))))
    (validate
     SdlcComplianceDossier
     (.o (:: @ (.ref SdlcComplianceDossier 'proto))
         identity: identity-value
         subject: (.ref project 'subject)
         revision: (.ref project 'revision)
         scope: (.ref project 'scope)
         standard: "nasa/sdlc/npr-7150.2"
         edition: "NPR 7150.2D"
         software-class: class-value
         mapping-matrix-digest: matrix-digest
         project-gate: project-gate-value
         institution-gate: institution-gate-value
         complete?: complete-value))))

(def (nasa-certification-decision identity-value dossier-value authority-value
                                  signer-value record-value decision-value)
  (unless (sdlc-compliance-dossier? dossier-value)
    (error "invalid NASA compliance dossier"))
  (validate
   SdlcCertificationDecision
   (.o (:: @ (.ref SdlcCertificationDecision 'proto))
       identity: identity-value
       subject: (.ref dossier-value 'subject)
       revision: (.ref dossier-value 'revision)
       scope: (.ref dossier-value 'scope)
       dossier: (.ref dossier-value 'identity)
       authority: authority-value
       signer: signer-value
       record: record-value
       decision: decision-value)))

(def (nasa-certification-verification-request dossier-value decision-value)
  (unless (and (sdlc-compliance-dossier? dossier-value)
               (sdlc-certification-decision? decision-value)
               (bound? decision-value dossier-value)
               (equal? (.ref decision-value 'dossier)
                       (.ref dossier-value 'identity)))
    (error "certification decision is not bound to the dossier"))
  (validate
   SdlcVerificationRequest
   (.o (:: @ (.ref SdlcVerificationRequest 'proto))
       subject: (.ref dossier-value 'subject)
       revision: (.ref dossier-value 'revision)
       scope: (.ref dossier-value 'scope)
       purpose: 'certification-decision
       facts: (.o dossier: dossier-value decision: decision-value))))

(def (certification-slots value names)
  (map (lambda (name) (.ref value name)) names))
(def (certification-request-snapshot request)
  (unless (and (sdlc-verification-request? request)
               (eq? (.ref request 'purpose) 'certification-decision))
    (error "invalid NASA certification verification request"))
  (let* ((facts (.ref request 'facts))
         (dossier (.ref facts 'dossier))
         (decision (.ref facts 'decision)))
    (unless (and (sdlc-compliance-dossier? dossier)
                 (sdlc-certification-decision? decision)
                 (bound? dossier request)
                 (bound? decision request)
                 (equal? (.ref decision 'dossier) (.ref dossier 'identity)))
      (error "malformed NASA certification verification request"))
    (call-with-output-string
     (lambda (port)
       (write
        (list
         'nasa-certification-verification
         (certification-slots request '(subject revision scope))
         (certification-slots dossier
                              '(identity standard edition software-class
                                mapping-matrix-digest complete?))
         (certification-slots (.ref dossier 'project-gate)
                              '(stage status assessment-scope requirements
                                admitted? reported-failures))
         (certification-slots (.ref dossier 'institution-gate)
                              '(stage status assessment-scope requirements
                                admitted? reported-failures))
         (certification-slots decision
                              '(identity dossier authority signer record decision))
         (certification-slots (.get Nasa7150_2D source-digests)
                              '(chapter2 chapter3 chapter4 chapter5 chapter6 appendix-c)))
        port)))))
(def (nasa-certification-verification-adapter identity-value operation)
  (yuanxu-verification-adapter
   identity-value operation certification-request-snapshot))

(def (nasa-certification-review dossier-value decision-value adapter receipts now)
  (unless (and (sdlc-compliance-dossier? dossier-value)
               (sdlc-certification-decision? decision-value)
               (list? receipts) (exact-integer? now) (>= now 0))
    (error "invalid NASA certification review inputs"))
  (let* ((request (nasa-certification-verification-request
                   dossier-value decision-value))
         (admission (yuanxu-verification-admission adapter receipts now))
         (verified?
          (yuanxu-verification-admission-valid? admission request))
         (status-value
          (cond
           ((not (.ref dossier-value 'complete?)) 'dossier-incomplete)
           ((not verified?) 'authority-verification-required)
           ((eq? (.ref decision-value 'decision) 'compliant)
            'compliant-by-verified-authority)
           (else 'noncompliant-by-verified-authority))))
    (.o kind: 'sdlc.nasa-compliance-certification
        subject: (.ref dossier-value 'subject)
        revision: (.ref dossier-value 'revision)
        scope: (.ref dossier-value 'scope)
        dossier: (.ref dossier-value 'identity)
        decision: (.ref decision-value 'identity)
        authority: (.ref decision-value 'authority)
        status: status-value
        compliance:
        (cond ((eq? status-value 'compliant-by-verified-authority) 'compliant)
              ((eq? status-value 'noncompliant-by-verified-authority) 'noncompliant)
              (else 'not-evaluated))
        certification:
        (if verified? 'authority-verified 'not-certified)
        release-authorized?: #f)))
