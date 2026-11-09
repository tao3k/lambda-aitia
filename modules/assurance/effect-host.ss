;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Optional Cedar integration for a serialized local effect owner.
;;; The configured runtime operations evaluate policy and deliver the effect.
;;; Editable preflights, requests, tokens and reports never issue capabilities.
(import (only-in :clan/poo/object .o .ref)
        (only-in :std/encoding/hex hex-decode)
        (only-in :std/hash/misc hash-remove!)
        (only-in :yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in "cedar-preflight.ss" assurance-host-cedar-request-current?)
        :agentic-ai-lab/modules/governance/policy/authorized-effect-token
        (only-in :agentic-ai-lab/modules/authorization/providers/cedar/decision
                 agentic-ai-lab-cedar-decision-permit?
                 agentic-ai-lab-cedar-decision->semantic-root
                 agentic-ai-lab-cedar-decision->authorized-effect-token))
(export assurance-effect-host assurance-effect-host-epoch
        assurance-effect-host-authorize! assurance-effect-host-grant-current?
        assurance-effect-host-reserve! assurance-effect-host-deliver!
        assurance-effect-host-revoke!)

(def hosts (make-hash-table-eq weak-keys: #t))
(def grants (make-hash-table-eq weak-keys: #t))
(def reservations (make-hash-table-eq weak-keys: #t))

(def (entry host)
  (let (state (hash-get hosts host))
    (unless (and state (eq? (vector-ref state 0) (current-thread)))
      (error "effect Host requires its exact serialized owner"))
    (when (vector-ref state 7) (error "effect Host mutation during runtime handoff"))
    state))
(def (instant state)
  (let (now ((vector-ref state 3)))
    (unless (and (exact-integer? now) (>= now (vector-ref state 8)))
      (error "effect Host clock must be monotonic and nonnegative"))
    (vector-set! state 8 now)
    now))
(def (handoff state operation)
  (dynamic-wind
    (lambda () (vector-set! state 7 #t))
    operation
    (lambda () (vector-set! state 7 #f))))

;;; Runtime authorize: Request -> CedarDecision or #f (deny/indeterminate).
;;; Runtime policy-current?: policy id, revision, policy digest, entity digest -> #t.
;;; Runtime deliver: Request Token -> delivered / failed / indeterminate.
;;; 'delivered is an attributable acknowledgement, not inferred from start.
(def (assurance-effect-host authorize deliver clock lease policy-current?)
  (unless (and (procedure? authorize) (procedure? deliver) (procedure? clock)
               (exact-integer? lease) (> lease 0) (procedure? policy-current?))
    (error "invalid effect Host runtime configuration"))
  (let (host (.o kind: 'aitia.effect-host.v1))
    (hash-put! hosts host
               (vector (current-thread) authorize deliver clock lease 0 0 #f 0 policy-current?))
    host))
(def (assurance-effect-host-epoch host) (vector-ref (entry host) 5))
(def (assurance-effect-host-revoke! host)
  (let (state (entry host))
    (vector-set! state 5 (+ 1 (vector-ref state 5)))))

(def (grant-entry host grant)
  (let (issued (hash-get grants grant))
    (and issued (eq? host (vector-ref issued 0))
         (equal? (.ref grant 'expires-at) (vector-ref issued 5))
         (equal? (.ref grant 'epoch) (vector-ref issued 4))
         (equal? (agentic-ai-lab-authorized-effect-token-digest (.ref grant 'token))
                 (vector-ref issued 6)) issued)))
(def (runtime-policy-current? state policy-id policy-revision binding)
  (eq? #t
       (handoff state
         (lambda ()
           ((vector-ref state 9)
            (string-copy policy-id) (string-copy policy-revision)
            (string-copy (.ref binding 'policy-digest))
            (string-copy (.ref binding 'entity-digest)))))))

(def (current-grant state host grant)
  (let (issued (grant-entry host grant))
    (and (current? state issued grant) (grant-entry host grant))))

(def (current? state issued grant)
  (and issued
       (= (vector-ref state 5) (vector-ref issued 4))
       (< (instant state) (vector-ref issued 5))
       (or (runtime-policy-current? state (vector-ref issued 8) (vector-ref issued 9)
                                    (.ref (vector-ref issued 3) 'binding))
           (begin
             ;; An observed policy replacement permanently retires this grant.
             (hash-remove! grants grant)
             #f))
       (assurance-host-cedar-request-current? (vector-ref issued 1) (vector-ref issued 2))
       ;; Source validation may take time. Apply strict expiry to the same
       ;; final instant passed to the token validator, whose endpoint is
       ;; otherwise inclusive; an earlier clock sample must not authorize use.
       (let (now (instant state))
         (and (< now (vector-ref issued 5))
              (.ref (agentic-ai-lab-authorized-effect-token-validate
                     (vector-ref issued 3)
                     (agentic-ai-lab-token-validation-context
                      (.ref (vector-ref issued 3) 'semantic-root)
                      (.ref (vector-ref issued 3) 'binding)
                      now (vector-ref state 5) '())) 'accepted?)))))
(def (assurance-effect-host-grant-current? host grant)
  (let (state (entry host))
    (and (current-grant state host grant) #t)))

(def (assurance-effect-host-authorize! host verification-host request)
  (let* ((state (entry host)) (now (instant state)) (epoch (vector-ref state 5)))
    (and (assurance-host-cedar-request-current? verification-host request)
         (let* ((context (.ref request 'context))
                (policy-id (string-copy (.ref context 'aitia_policy)))
                (policy-revision (string-copy (.ref context 'aitia_policy_revision)))
                (decision (handoff state (lambda () ((vector-ref state 1) request))))
                (decision-binding
                 (and decision (agentic-ai-lab-cedar-decision-permit? decision)
                      (map (lambda (slot) (string-copy (.ref decision slot)))
                           '(policy-digest entity-digest decision-digest)))))
           (and decision-binding
                (equal? (.ref decision 'policy-id) policy-id)
                (runtime-policy-current? state policy-id policy-revision decision)
                (= epoch (vector-ref state 5))
                (< (instant state) (+ now (vector-ref state 4)))
                (assurance-host-cedar-request-current? verification-host request)
                (equal? decision-binding
                        (map (lambda (slot) (.ref decision slot))
                             '(policy-digest entity-digest decision-digest)))
                (agentic-ai-lab-cedar-decision-permit? decision)
                (equal? (.ref decision 'policy-id) policy-id)
                (let* ((next (+ 1 (vector-ref state 6)))
                       (bundle (.ref context 'aitia_snapshot_semantic_digest))
                       (intent (.ref request 'intent))
                       (handoff-value (.ref request 'handoff))
                       (sequence (.ref handoff-value 'sequence))
                       (payload (hex-decode (.ref handoff-value 'payload-hex)))
                       (root (agentic-ai-lab-cedar-decision->semantic-root decision bundle intent))
                       (binding
                        (agentic-ai-lab-effect-binding
                         bundle epoch (.ref decision 'policy-digest) (.ref decision 'entity-digest)
                         (.ref decision 'decision-digest) intent next (.ref request 'action)
                         'configured-runtime 'local sequence sequence 'local 0 0
                         (u8vector-length payload) (source-lock-payload-digest payload) 'local))
                       (until (+ now (vector-ref state 4)))
                       (token (agentic-ai-lab-cedar-decision->authorized-effect-token
                               decision next next root binding
                               (agentic-ai-lab-token-validity now now until epoch)
                               'strict 1 'configured-runtime "local-adapter"))
                       (grant (let ((token-value token) (epoch-value epoch))
                                (.o kind: 'aitia.effect-grant.v1 token: token-value epoch: epoch-value expires-at: until))))
                  (vector-set! state 6 next)
                  (hash-put! grants grant
                             (vector host verification-host request token epoch until
                                     (agentic-ai-lab-authorized-effect-token-digest token) #f
                                     policy-id policy-revision))
                  grant))))))

;;; Reservation consumes the grant once, but executes no external effect.
(def (assurance-effect-host-reserve! host grant)
  (let* ((state (entry host)) (issued (current-grant state host grant)))
    (and issued (not (vector-ref issued 7))
         (let (reservation (.o kind: 'aitia.effect-reservation.v1))
           (vector-set! issued 7 #t)
           (hash-put! reservations reservation (vector host grant issued #f))
           reservation))))

(def (delivery-receipt outcome-value invoked?)
  (.o kind: 'aitia.effect-delivery.v1 outcome: outcome-value handoff-executed?: invoked?
      delivered?: (eq? outcome-value 'delivered) durable?: #f distributed-authority?: #f))
(def (assurance-effect-host-deliver! host reservation)
  (let* ((state (entry host)) (issued (hash-get reservations reservation)))
    (cond
     ((or (not issued) (not (eq? host (vector-ref issued 0))) (vector-ref issued 3))
      (delivery-receipt 'rejected #f))
     (else
      ;; Consume even on rejection / exception / unknown acknowledgement.
      (vector-set! issued 3 #t)
      (let (grant-state (vector-ref issued 2))
        (if (current-grant state host (vector-ref issued 1))
          (let (outcome
                (handoff state
                         (lambda () ((vector-ref state 2) (vector-ref grant-state 2)
                                     (vector-ref grant-state 3)))))
            (unless (memq outcome '(delivered failed indeterminate))
              (error "runtime delivery returned an invalid acknowledgement" outcome))
            (delivery-receipt outcome #t))
          (delivery-receipt 'rejected #f)))))))
