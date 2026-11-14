;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/mop Any Function Type. element?)
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/object .o .cc .ref .slot? object? compute-precedence-list!)

        (only-in :agentic-ai-lab/modules/governance/types
                 agentic-ai-lab-governance-profile?)
        :std/list/list)
(export SdlcScopeContract sdlc-record-type sdlc-record-field sdlc-record?
        standard-profile? sdlc-profile? sdlc-text?
        SdlcStandard SdlcIdentified SdlcBoundFact SdlcProject SdlcObligation SdlcEvidence
        SdlcTailoringRequest SdlcTraceNode SdlcTraceEdge SdlcTraceRule
        sdlc-bound-fact? sdlc-project? sdlc-obligation? sdlc-evidence?
        sdlc-tailoring-request? sdlc-trace-node? sdlc-trace-edge? sdlc-trace-rule?)

(def (sdlc-record-field name type-predicate: predicate)
  (list (make-keyword name) (list (.cc Type. sexp: name '.element? predicate))))

(def (sdlc-record-type identity-value direct-superclasses: (parents '()) direct-slots: (fields '()))
  (let (schema (apply Record (cons parents (apply append fields))))
    (.o (:: @ schema) identity: identity-value
        proto: (.o (:: @ (cons (.ref schema 'proto)
                               (map (lambda (parent) (.ref parent 'proto)) parents)))))))

(def (sdlc-record? descriptor value)
  (and (object? value)
       (memq (.ref descriptor 'proto) (compute-precedence-list! value))
       (element? descriptor value)
       #t))

(def (sdlc-text? value) (and (string? value) (> (string-length value) 0)))
(def (text-slots names)
  (map (lambda (name) (sdlc-record-field name type-predicate: sdlc-text?)) names))
(def (enum-slot name choices)
  (sdlc-record-field name
    type-predicate: (lambda (value) (if (memq value choices) #t #f))))
(def (requirements? values)
  (and (list? values)
       (every (lambda (r) (and (object? r) (.slot? r 'identity)
                               (sdlc-text? (.ref r 'identity)))) values)
       (let (ids (map (lambda (r) (.ref r 'identity)) values))
         (= (length ids) (length (delete-duplicates/hash ids))))))

;;; Record composes the inherited field constraints. The prototype preserves
;;; nominal membership across the same parent declarations.
(def SdlcSubject
  (sdlc-record-type 'sdlc/subject direct-slots: (text-slots '(subject revision))))
(def SdlcBoundFact
  (sdlc-record-type 'sdlc/bound-fact direct-superclasses: (list SdlcSubject)
    direct-slots: (text-slots '(scope))))
(def SdlcClause
  (sdlc-record-type 'sdlc/clause direct-slots: (text-slots '(standard requirement))))
(def SdlcIdentified
  (sdlc-record-type 'sdlc/identified direct-slots: (text-slots '(identity))))
(def SdlcStandard
  (sdlc-record-type 'sdlc/standard direct-superclasses: (list SdlcIdentified)
    direct-slots: (append (text-slots '(edition source-url))
      (list (enum-slot 'coverage '(partial complete))
            (enum-slot 'assessment '(not-evaluated))
            (sdlc-record-field 'requirements type-predicate: requirements?)))))
(def SdlcProject
  (sdlc-record-type 'sdlc/project direct-superclasses: (list SdlcBoundFact)
    direct-slots: (list (sdlc-record-field 'complete? type-predicate: boolean?))))
(def SdlcObligation
  (sdlc-record-type 'sdlc/obligation direct-superclasses: (list SdlcClause)
    direct-slots: (list (enum-slot 'applicability '(applicable unknown not-applicable)))))
(def SdlcEvidence
  (sdlc-record-type 'sdlc/evidence direct-superclasses: (list SdlcBoundFact SdlcClause SdlcIdentified)
    direct-slots: (append (text-slots '(producer)) (list (enum-slot 'outcome '(pass fail))))))
(def SdlcTailoringRequest
  (sdlc-record-type 'sdlc/tailoring-request direct-superclasses: (list SdlcSubject SdlcClause)
    direct-slots: (text-slots '(rationale))))
(def SdlcTraceNode
  (sdlc-record-type 'sdlc/trace-node direct-superclasses: (list SdlcBoundFact SdlcIdentified)
    direct-slots: (list (sdlc-record-field 'category type-predicate: symbol?))))
(def SdlcTraceEdge
  (sdlc-record-type 'sdlc/trace-edge direct-superclasses: (list SdlcBoundFact SdlcIdentified)
    direct-slots: (text-slots '(source target relation))))
(def SdlcTraceRule
  (sdlc-record-type 'sdlc/trace-rule direct-superclasses: (list SdlcIdentified)
    direct-slots: (map (lambda (name) (sdlc-record-field name type-predicate: symbol?))
                       '(source-category target-category))))

(def (sdlc-profile? value)
  (and (agentic-ai-lab-governance-profile? value) (.slot? value 'standards)
       (list? (.ref value 'standards))
       (every standard-profile? (.ref value 'standards))
       (let ((ids (map (lambda (s) (.ref s 'identity)) (.ref value 'standards))))
         (= (length ids) (length (delete-duplicates/hash ids))))))
(def (standard-profile? value) (sdlc-record? SdlcStandard value))
(def (sdlc-bound-fact? value) (sdlc-record? SdlcBoundFact value))
(def (sdlc-project? value) (sdlc-record? SdlcProject value))
(def (sdlc-obligation? value) (sdlc-record? SdlcObligation value))
(def (sdlc-evidence? value) (sdlc-record? SdlcEvidence value))
(def (sdlc-tailoring-request? value) (sdlc-record? SdlcTailoringRequest value))
(def (sdlc-trace-node? value) (sdlc-record? SdlcTraceNode value))
(def (sdlc-trace-edge? value) (sdlc-record? SdlcTraceEdge value))
(def (sdlc-trace-rule? value) (sdlc-record? SdlcTraceRule value))

(export SdlcCriterionEvidence sdlc-criterion-evidence?
        SdlcSafetyComponent sdlc-safety-component?)
(def SdlcCriterionEvidence
  (sdlc-record-type 'sdlc/criterion-evidence direct-superclasses: (list SdlcEvidence)
    direct-slots: (text-slots '(criterion source-digest))))
(def (sdlc-criterion-evidence? value) (sdlc-record? SdlcCriterionEvidence value))
(def (coverage-or-unknown? value)
  (or (eq? value 'unknown) (and (real? value) (<= 0 value 100))))
(def (complexity-or-unknown? value)
  (or (eq? value 'unknown) (and (exact-integer? value) (>= value 0))))
(def SdlcSafetyComponent
  (sdlc-record-type 'sdlc/safety-component direct-superclasses: (list SdlcBoundFact SdlcIdentified)
    direct-slots: (list
      (sdlc-record-field 'safety-critical? type-predicate: boolean?)
      (sdlc-record-field 'mcdc-percent type-predicate: coverage-or-unknown?)
      (sdlc-record-field 'cyclomatic-complexity type-predicate: complexity-or-unknown?))))
(def (sdlc-safety-component? value) (sdlc-record? SdlcSafetyComponent value))

(export SdlcTailoringPacket sdlc-tailoring-packet?
        SdlcAuthorityAttestation sdlc-authority-attestation?)
(def SdlcTailoringPacket
  (sdlc-record-type 'sdlc/tailoring-packet
    direct-superclasses: (list SdlcBoundFact SdlcClause SdlcIdentified)
    direct-slots: (text-slots '(rationale risk mitigations risk-acceptance archived-matrix))))
(def SdlcAuthorityAttestation
  (sdlc-record-type 'sdlc/authority-attestation
    direct-superclasses: (list SdlcBoundFact SdlcClause SdlcIdentified)
    direct-slots: (append (text-slots '(request signer record))
      (list (sdlc-record-field 'authority type-predicate: symbol?)
            (enum-slot 'decision '(approved rejected))))))
(def (sdlc-tailoring-packet? value) (sdlc-record? SdlcTailoringPacket value))
(def (sdlc-authority-attestation? value) (sdlc-record? SdlcAuthorityAttestation value))

(export SdlcStagePolicy sdlc-stage-policy? SdlcLifecycleState sdlc-lifecycle-state?
        SdlcVerificationRequest sdlc-verification-request?)
(def (nonempty-text-list? values)
  (and (list? values) (pair? values) (every sdlc-text? values)
       (= (length values) (length (delete-duplicates/hash values)))))
(def SdlcStagePolicy
  (sdlc-record-type 'sdlc/stage-policy direct-superclasses: (list SdlcIdentified)
    direct-slots: (list (enum-slot 'assessment-scope '(project institution))
                       (sdlc-record-field 'requirements type-predicate: nonempty-text-list?))))
(def SdlcLifecycleState
  (sdlc-record-type 'sdlc/lifecycle-state direct-superclasses: (list SdlcBoundFact)
    direct-slots: (text-slots '(stage))))
(def SdlcVerificationRequest
  (sdlc-record-type 'sdlc/verification-request direct-superclasses: (list SdlcBoundFact)
    direct-slots: (list (enum-slot 'purpose '(criterion-content classification-and-context tailoring-decision structured-inventory certification-decision history-discovery disposition-approval))
                       (sdlc-record-field 'facts type-predicate: object?))))
(def (sdlc-stage-policy? value) (sdlc-record? SdlcStagePolicy value))
(def (sdlc-lifecycle-state? value) (sdlc-record? SdlcLifecycleState value))
(def (sdlc-verification-request? value) (sdlc-record? SdlcVerificationRequest value))

(export SdlcSafetyInventory SdlcTraceInventory sdlc-safety-inventory? sdlc-trace-inventory?
        sdlc-artifact-digest?)
(def (sdlc-artifact-digest? value)
  (and (string? value) (= (string-length value) 64)
       (every (lambda (c) (or (char<=? #\0 c #\9) (char<=? #\a c #\f))) (string->list value))))
(def SdlcInventory
  (sdlc-record-type 'sdlc/inventory direct-superclasses: (list SdlcBoundFact SdlcIdentified)
    direct-slots: (list (sdlc-record-field 'artifact-digest type-predicate: sdlc-artifact-digest?)
                       (sdlc-record-field 'complete? type-predicate: boolean?))))
(def (instances-slot name predicate)
  (sdlc-record-field name
    type-predicate: (lambda (values) (and (list? values) (every predicate values)))))
(def SdlcSafetyInventory
  (sdlc-record-type 'sdlc/safety-inventory direct-superclasses: (list SdlcInventory)
    direct-slots: (list (instances-slot 'components sdlc-safety-component?))))
(def SdlcTraceInventory
  (sdlc-record-type 'sdlc/trace-inventory direct-superclasses: (list SdlcInventory)
    direct-slots: (list (instances-slot 'nodes sdlc-trace-node?) (instances-slot 'edges sdlc-trace-edge?))))
(def (sdlc-safety-inventory? value) (sdlc-record? SdlcSafetyInventory value))
(def (sdlc-trace-inventory? value) (sdlc-record? SdlcTraceInventory value))

(def SdlcScopeContract
  (.cc (Record flow-graph: [(Function (list Any) (list Any))]
               design-contract-digest: [(Function (list Any) (list Any))]
               design-implementation-review: [(Function (list Any) (list Any Any Any))])
       identity: 'sdlc/scope))
