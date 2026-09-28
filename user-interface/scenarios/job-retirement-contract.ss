;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Maintained POO design declaration for the bounded formal experiment.
;;; Source bindings are not Host evidence admission or implementation refinement.
(import (only-in :poo-flow/lambda-aitia/modules/sdlc/design
                 sdlc-design-contract sdlc-design-assumption sdlc-design-guarantee))
(export job-retirement-contract job-retirement-safety
        job-retirement-tla-sources job-retirement-lean-sources)

(def job-retirement-safety
  (sdlc-design-guarantee
   "retirement-safety" "g1"
   "Retirement leaves no active or queued work; a cached grant cannot start a later effect."))
(def job-retirement-contract
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
      "The TLA+ composition models one cached grant, one request and one attempt."))
   (list job-retirement-safety) '()))

;;; Dependency closure for the retirement slice, not unrelated assurance gates.
;;; Lists name repository source assets; they are not a second workflow DSL.
(def job-retirement-tla-sources
  '("proof/tla/EffectAdmission.tla"
    "proof/tla/WorkLifecycle.tla"
    "proof/tla/RetirementReview.tla"
    "proof/tla/RetirementIngress.tla"
    "proof/tla/WorkLifecycle.cfg"
    "proof/tla/WorkCancellation.cfg"
    "proof/tla/WorkCancellationReachable.cfg"
    "proof/tla/WorkQuiescenceReachable.cfg"
    "proof/tla/RetirementReview.cfg"
    "proof/tla/RetirementReviewCancellation.cfg"
    "proof/tla/RetirementReviewStale.cfg"
    "proof/tla/RetirementReviewUnknown.cfg"
    "proof/tla/RetirementReviewReachable.cfg"
    "proof/tla/RetirementIngress.cfg"
    "proof/tla/RetirementIngressUnfenced.cfg"
    "proof/tla/RetirementIngressCachedGrant.cfg"
    "proof/tla/RetirementIngressRejected.cfg"
    "proof/tla/RetirementIngressStarted.cfg"))
(def job-retirement-lean-sources
  '("proof/lean/LambdaAitiaProof/Modules/Sdlc/Retirement.lean"
    "proof/lean/LambdaAitiaProof/Modules/Sdlc/RetirementIngress.lean"))
