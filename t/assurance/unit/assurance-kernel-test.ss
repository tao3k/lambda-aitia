;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/error Error?)
        (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/assurance/interface)

(export assurance-kernel-test)

(def digest-a (string-append "sha256:" (make-string 64 #\a)))
(def digest-b (string-append "sha256:" (make-string 64 #\b)))
(def artifact (assurance-artifact "artifact/source" "r1" 'supported digest-a))
(def claim (assurance-claim "claim/release" "r1" 'unknown digest-b))
(def obligation
  (assurance-obligation "obligation/verify" "r1" 'unknown digest-a))
(def evidence
  (assurance-evidence "evidence/test" "r1" 'supported digest-b))
(def dependency
  (assurance-relation "relation/depends" 'structural 'depends-on
                      "claim/release" "artifact/source" 'declared))
(def discharge
  (assurance-relation "relation/discharges" 'assurance 'discharges
                      "evidence/test" "obligation/verify" 'observed))

(def assurance-kernel-test
  (test-suite "Aitia POO-native assurance kernel"
    (test-case "nominal node identity is not granted by matching slots"
      (check-equal? (assurance-artifact? artifact) #t)
      (check-equal? (assurance-claim? artifact) #f)
      (check-equal?
       (assurance-artifact?
        (.o identity: "artifact/source" kind: 'artifact revision: "r1"
            state: 'supported content-digest: digest-a))
       #f)
      (check-equal? (assurance-artifact? (.o (:: @ artifact) kind: 'claim)) #f)
      (check-exception
       (assurance-artifact "artifact/source" "" 'supported digest-a) Error?))

    (test-case "relation kinds cannot cross their owned plane"
      (check-equal? (assurance-relation? dependency) #t)
      (check-exception
       (assurance-relation "bad" 'causal 'depends-on
                           "claim/release" "artifact/source" 'declared)
       Error?)
      (check-equal?
       (assurance-relation? (.o (:: @ dependency) plane: 'authority)) #f))

    (test-case "canonical snapshots are stable under input permutation"
      (let ((left
             (assurance-snapshot
              "snapshot/software" "r1"
              (list artifact claim obligation evidence)
              (list dependency discharge)))
            (right
             (assurance-snapshot
              "snapshot/software" "r1"
              (list evidence obligation claim artifact)
              (list discharge dependency))))
        (check-equal? (.ref left 'digest) (.ref right 'digest))
        (check-equal? (.ref left 'state) 'supported)
        (check-equal?
         (map (lambda (node) (.ref node 'identity)) (.ref left 'nodes))
         '("artifact/source" "claim/release" "evidence/test"
           "obligation/verify"))))

    (test-case "unequal duplicate identity is conflicted, never overwritten"
      (let ((snapshot
             (assurance-snapshot
              "snapshot/conflict" "r1"
              (list artifact
                    (assurance-artifact
                     "artifact/source" "r2" 'supported digest-b))
              '())))
        (check-equal? (.ref snapshot 'state) 'conflicted)
        (check-equal? (.ref snapshot 'conflicts) '("artifact/source"))))

    (test-case "missing relation endpoints remain an unknown frontier"
      (let ((snapshot
             (assurance-snapshot
              "snapshot/unknown" "r1" (list claim)
              (list dependency))))
        (check-equal? (.ref snapshot 'state) 'unknown)
        (check-equal? (.ref snapshot 'unresolved) '("artifact/source"))))

    (test-case "alternate evidence and temporal order grant no support"
      (check-equal?
       (assurance-support-admissible? discharge evidence obligation) #t)
      (check-equal?
       (assurance-support-admissible?
        discharge (.o (:: @ evidence) state: 'hypothesized) obligation)
       #f)
      (check-equal?
       (assurance-support-admissible?
        (.o (:: @ discharge) modality: 'counterfactual)
        evidence obligation)
       #f)
      (check-equal?
       (assurance-support-admissible?
        (assurance-relation "relation/precedes" 'causal 'precedes
                            "evidence/test" "obligation/verify" 'observed)
        evidence obligation)
       #f))))
