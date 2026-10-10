;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Explicit, single-owner Scheme Host for the bounded retirement-ingress cut.
;;; Pure POO state transitions are committed only at this local Host boundary.
;;; This does not issue grants or claim durable, distributed, or Marlin authority.
(import (only-in :clan/poo/object .o .ref .slot? object?))
(export aitia-retirement-host
        aitia-retirement-host-snapshot
        aitia-retirement-effect-handoff
        aitia-retirement-host-request-cancellation!
        aitia-retirement-host-observe-completion!
        aitia-retirement-host-observe-queue-drained!
        aitia-retirement-host-complete-inventory!
        aitia-retirement-host-review-cut!
        aitia-retirement-host-observe-late-activity!
        aitia-retirement-host-observe-inventory-gap!
        aitia-retirement-host-close-ingress!
        aitia-retirement-host-request-start!
        aitia-retirement-host-attempt-start!
        aitia-retirement-host-retire!)

;;; The live state is keyed by host identity, never returned to callers.
(def retirement-host-states (make-hash-table-eq weak-keys: #t))

(def (host-state host)
  (let (state (and (object? host) (hash-get retirement-host-states host)))
    (unless (and state
                 (eq? (.ref state 'owner-thread) (current-thread)))
      (error "retirement Host requires its serialized owner thread"))
    state))

(def (state-view state)
  (.o kind: 'aitia.retirement-ingress-state.v1
      active?: (.ref state 'active?)
      queued?: (.ref state 'queued?)
      inventory-known?: (.ref state 'inventory-known?)
      reviewed?: (.ref state 'reviewed?)
      cancellation-requested?: (.ref state 'cancellation-requested?)
      late-activity-found?: (.ref state 'late-activity-found?)
      inventory-gap-found?: (.ref state 'inventory-gap-found?)
      retired?: (.ref state 'retired?)
      ingress-open?: (.ref state 'ingress-open?)
      authority-epoch: (.ref state 'authority-epoch)
      cached-grant-epoch: (.ref state 'cached-grant-epoch)
      pending?: (.ref state 'pending?)
      attempted?: (.ref state 'attempted?)))

(def (receipt action state accepted? reason handoff-executed?)
  (.o kind: 'aitia.retirement-ingress-receipt.v1
      action: action accepted?: accepted? reason: reason
      state: (state-view state)
      handoff-executed?: handoff-executed?
      durable?: #f distributed-authority?: #f))

(def (publish host action state accepted? reason)
  (hash-put! retirement-host-states host state)
  (receipt action state accepted? reason #f))

(def (aitia-retirement-host)
  (let ((host (.o kind: 'aitia.retirement-ingress-host.v1))
        (state (.o owner-thread: (current-thread)
                   active?: #t queued?: #t inventory-known?: #f
                   reviewed?: #f cancellation-requested?: #f
                   late-activity-found?: #f inventory-gap-found?: #f
                   retired?: #f ingress-open?: #t
                   authority-epoch: 0 cached-grant-epoch: 0
                   pending?: #f attempted?: #f)))
    (hash-put! retirement-host-states host state)
    host))

(def (aitia-retirement-host-snapshot host)
  (state-view (host-state host)))

;;; The named POO handoff is the only effect escape hatch. Its callback is
;;; invoked only after the Host has consumed a current pending request.
(def (aitia-retirement-effect-handoff run)
  (unless (procedure? run) (error "retirement handoff requires a procedure"))
  (.o kind: 'aitia.retirement-effect-handoff.v1 run: run))

(def (aitia-retirement-host-request-cancellation! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'request-cancellation state #f 'already-retired #f))
     ((.ref state 'cancellation-requested?)
      (receipt 'request-cancellation state #f 'already-requested #f))
     (else
      (publish host 'request-cancellation
               (.o (:: @ state) cancellation-requested?: #t)
               #t 'recorded)))))

(def (aitia-retirement-host-observe-completion! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'observe-completion state #f 'already-retired #f))
     ((not (.ref state 'active?))
      (receipt 'observe-completion state #f 'not-active #f))
     (else
      (publish host 'observe-completion
               (.o (:: @ state) active?: #f) #t 'observed)))))

(def (aitia-retirement-host-observe-queue-drained! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'observe-queue-drained state #f 'already-retired #f))
     ((not (.ref state 'queued?))
      (receipt 'observe-queue-drained state #f 'already-drained #f))
     (else
      (publish host 'observe-queue-drained
               (.o (:: @ state) queued?: #f) #t 'observed)))))

(def (aitia-retirement-host-complete-inventory! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'complete-inventory state #f 'already-retired #f))
     ((.ref state 'inventory-known?)
      (receipt 'complete-inventory state #f 'already-known #f))
     (else
      (publish host 'complete-inventory
               (.o (:: @ state) inventory-known?: #t) #t 'observed)))))

(def (aitia-retirement-host-review-cut! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'review-cut state #f 'already-retired #f))
     ((.ref state 'active?)
      (receipt 'review-cut state #f 'active-work #f))
     ((.ref state 'queued?)
      (receipt 'review-cut state #f 'queued-work #f))
     ((not (.ref state 'inventory-known?))
      (receipt 'review-cut state #f 'inventory-unknown #f))
     ((.ref state 'reviewed?)
      (receipt 'review-cut state #f 'already-reviewed #f))
     (else
      (publish host 'review-cut (.o (:: @ state) reviewed?: #t)
               #t 'reviewed)))))

(def (aitia-retirement-host-observe-late-activity! host)
  (let (state (host-state host))
    (cond
     ((or (.ref state 'retired?) (not (.ref state 'reviewed?))
          (.ref state 'late-activity-found?))
      (receipt 'observe-late-activity state #f 'not-admissible #f))
     (else
      (publish host 'observe-late-activity
               (.o (:: @ state) active?: #t late-activity-found?: #t)
               #t 'observed)))))

(def (aitia-retirement-host-observe-inventory-gap! host)
  (let (state (host-state host))
    (cond
     ((or (.ref state 'retired?) (not (.ref state 'reviewed?))
          (.ref state 'inventory-gap-found?))
      (receipt 'observe-inventory-gap state #f 'not-admissible #f))
     (else
      (publish host 'observe-inventory-gap
               (.o (:: @ state) inventory-known?: #f inventory-gap-found?: #t)
               #t 'observed)))))

;;; Closure and epoch advancement are one synchronous Host state publication.
(def (aitia-retirement-host-close-ingress! host)
  (let (state (host-state host))
    (if (.ref state 'ingress-open?)
      (publish host 'close-ingress
               (.o (:: @ state) ingress-open?: #f
                   authority-epoch: (+ 1 (.ref state 'authority-epoch)))
               #t 'fenced)
      (receipt 'close-ingress state #f 'already-closed #f))))

(def (aitia-retirement-host-request-start! host)
  (let (state (host-state host))
    (if (or (.ref state 'pending?) (.ref state 'attempted?))
      (receipt 'request-start state #f 'request-already-consumed #f)
      (publish host 'request-start (.o (:: @ state) pending?: #t)
               #t 'pending))))

(def (aitia-retirement-host-attempt-start! host handoff)
  (let (state (host-state host))
    (unless (and (object? handoff) (.slot? handoff 'kind)
                 (eq? (.ref handoff 'kind)
                      'aitia.retirement-effect-handoff.v1)
                 (.slot? handoff 'run) (procedure? (.ref handoff 'run)))
      (error "invalid retirement effect handoff"))
    (unless (.ref state 'pending?)
      (error "retirement start requires a pending request"))
    (let (consumed (.o (:: @ state) pending?: #f attempted?: #t))
      (cond
       ((not (= (.ref state 'cached-grant-epoch)
                (.ref state 'authority-epoch)))
        (publish host 'attempt-start consumed #f 'stale-grant))
       ((or (.ref state 'retired?) (not (.ref state 'ingress-open?)))
        (publish host 'attempt-start consumed #f 'ingress-closed))
       (else
        ;; Consume before handoff so a reentrant call cannot start twice.
        (let (started (.o (:: @ consumed) active?: #t))
          (hash-put! retirement-host-states host started)
          ((.ref handoff 'run))
          (receipt 'attempt-start started #t 'started #t)))))))

(def (aitia-retirement-host-retire! host)
  (let (state (host-state host))
    (cond
     ((.ref state 'retired?)
      (receipt 'retire state #f 'already-retired #f))
     ((.ref state 'active?)
      (receipt 'retire state #f 'active-work #f))
     ((.ref state 'queued?)
      (receipt 'retire state #f 'queued-work #f))
     ((not (.ref state 'inventory-known?))
      (receipt 'retire state #f 'inventory-unknown #f))
     ((not (.ref state 'reviewed?))
      (receipt 'retire state #f 'review-missing #f))
     ((.ref state 'ingress-open?)
      (receipt 'retire state #f 'ingress-open #f))
     ((= (.ref state 'cached-grant-epoch) (.ref state 'authority-epoch))
      (receipt 'retire state #f 'grant-current #f))
     (else
      (publish host 'retire (.o (:: @ state) retired?: #t)
               #t 'retired)))))
