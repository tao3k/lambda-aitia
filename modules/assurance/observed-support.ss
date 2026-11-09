;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref)
        (only-in "objects.ss" assurance-relation)
        (only-in "func.ss" assurance-snapshot assurance-bind-obligation-to-snapshot)
        (only-in "evidence-admission.ss" assurance-verifier-input assurance-verifier-outcome
                 assurance-verifier-outcome-digest)
        (only-in "host.ss" assurance-verification-host assurance-host-admit
                 assurance-host-required-support assurance-host-revoke-admission!))
(export assurance-assess-observed-support assurance-observed-support-reader)

(def (assurance-assess-observed-support
      fact-cut claim-value obligation-value evidence-value artifacts source-reader attempt verify
      challenge: (challenge #f))
  ((assurance-observed-support-reader fact-cut claim-value obligation-value evidence-value
                                      artifacts source-reader attempt verify challenge: challenge)))

;; One delivery owns at most one admission. Assessment never refreshes the
;; lease or reissues a seal after the source or admission becomes stale.
(def (assurance-observed-support-reader
      fact-cut claim-value obligation-value evidence-value artifacts source-reader attempt verify
      current?: (current? (lambda () #t)) clock: (clock (lambda () 0)) lease: (lease 1)
      challenge: (challenge #f))
  (let* ((snapshot-id (.ref obligation-value 'snapshot))
         (revision (.ref claim-value 'revision))
         (producer (.ref evidence-value 'producer))
         (tool (.ref evidence-value 'tool))
         (version (.ref evidence-value 'tool-version)))
    (def (snapshot-with obligation-node)
      (assurance-snapshot snapshot-id revision snapshot-id
                          (map (lambda (artifact)
                                 (cons (.ref artifact 'identity) (.ref artifact 'revision)))
                               artifacts)
                          (list (cons (.ref claim-value 'identity) revision))
                          fact-cut tool version
                          (append artifacts (list claim-value obligation-node)
                                  (cond (challenge (list evidence-value challenge))
                                        (attempt (list evidence-value))
                                        (else '())))
                          (cons (assurance-relation "requires-support" 'assurance 'supports
                                                    (.ref obligation-node 'identity)
                                                    (.ref claim-value 'identity) 'declared)
                                (cond
                                 (challenge
                                  (list (assurance-relation "observed-challenge" 'assurance 'defeats
                                                            (.ref challenge 'identity)
                                                            (.ref claim-value 'identity) 'observed)))
                                 (attempt
                                  (list (assurance-relation "observed-support" 'assurance 'discharges
                                                              (.ref evidence-value 'identity)
                                                              (.ref obligation-node 'identity) 'observed)))
                                 (else '())))))
    (let* ((bound (assurance-bind-obligation-to-snapshot obligation-value
                                                         (snapshot-with obligation-value)))
           (snapshot-value (snapshot-with bound))
           (outcome
            (and attempt
                 (assurance-verifier-outcome
                  attempt 'succeeded producer: producer tool: tool tool-version: version
                  subject: (.ref claim-value 'subject) scope: (.ref claim-value 'scope)
                  obligation: (.ref bound 'identity) snapshot-revision: revision
                  snapshot-context-digest: (.ref snapshot-value 'context-digest)
                  inputs: (map assurance-verifier-input artifacts)
                  output-digest: (.ref evidence-value 'content-digest))))
           (execution-digest (and outcome (assurance-verifier-outcome-digest outcome)))
           (host
            (assurance-verification-host
             producer verify clock lease (lambda () snapshot-value)
             source-reader: source-reader
             execution-reader: (lambda (identity)
                                 (and (equal? identity attempt) execution-digest))))
           (admission (and outcome (current?)
                           (assurance-host-admit host bound evidence-value outcome)))
           (retired? #f))
      (def (retire!)
        (when admission
          (assurance-host-revoke-admission! host admission)
          (set! admission #f))
        (set! retired? #t)
        'reopened)
      (lambda ()
        (cond
         (retired? 'reopened)
         ((not (current?)) (retire!))
         (else
          (let (assessment (assurance-host-required-support
                            host claim-value (if admission (list admission) '())))
            (if (and (current?)
                     (or (not admission) (pair? (.ref assessment 'witnesses))))
                assessment
                (retire!)))))))))
