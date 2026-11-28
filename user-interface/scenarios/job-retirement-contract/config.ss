;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Maintained POO design declaration for the bounded formal experiment.
;;; Source bindings are not Host evidence admission or implementation refinement.
(import (only-in :clan/poo/object .get .o) "objects.ss")
(export make-job-retirement-scope)

(def (make-job-retirement-scope sdlc)
  (def sdlc-design-contract (.get sdlc design-contract))
  (def sdlc-design-assumption (.get sdlc design-assumption))
  (def sdlc-design-guarantee (.get sdlc design-guarantee))
  (def safety
    (sdlc-design-guarantee
     "retirement-safety" "g1"
     "Retirement leaves no active or queued work; a cached grant cannot start a later effect."))
  (def retirement-contract
    (sdlc-design-contract
     "job-executor/retirement" "r1" "RFC/0004/retirement-ingress"
     '("review-retirement" "invalidate-cached-authority" "drain-known-work")
     '("retirement-review-cut") '()
     (list
      (sdlc-design-assumption "atomic-epoch-fence" "a1"
        "Closing issuance and advancing the authority epoch is one atomic step.")
      (sdlc-design-assumption "known-inventory" "a1"
        "Inventory at finalization covers all active and queued consumers.")
      (sdlc-design-assumption "no-new-grant" "a1"
        "No new grant is issued after closure in the modeled scope.")
      (sdlc-design-assumption "bounded-client" "a1"
        "The Quint composition models one cached grant, one request and one attempt."))
     (list safety) '()))
  (.o contract: retirement-contract guarantee: safety
      quint-sources: job-retirement-quint-sources
      lean-sources: job-retirement-lean-sources
      scheme-sources: job-retirement-scheme-sources))
