;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Legacy module-selection projection is standard-free. The NASA Standard is
;;; selected through its own typed nasa/sdlc Module Profile, not an SDLC flag.
(import (only-in :clan/poo/object .o .get)
        "types.ss" "objects.ss" "func.ss" "review.ss" "impact.ss"
        "design.ss" "implementation.ss" "verification.ss")
(export make-sdlc-scope)

(def accepts-standard? standard-profile?)

(def (make-sdlc-scope assurance)
  (def digest (make-sdlc-design-contract-digester (.get assurance digest)))
  (def implementation (make-sdlc-implementation assurance digest))
  (.o profile: SdlcProfile standard-profile: StandardProfile.
      profile?: sdlc-profile? standard-profile?: accepts-standard?
      with-standards: sdlc-with-standards contribution: sdlc-contribution
      default-contribution: (sdlc-contribution SdlcProfile)
      flow-stages: +sdlc-flow-stages+ flow-graph: sdlc-flow-graph
      project: sdlc-project project?: sdlc-project? bound-fact?: sdlc-bound-fact?
      obligation: sdlc-obligation obligation?: sdlc-obligation?
      evidence: sdlc-evidence evidence?: sdlc-evidence?
      tailoring-request: sdlc-tailoring-request tailoring-request?: sdlc-tailoring-request?
      review: sdlc-review trace-review: sdlc-trace-review
      trace-node: sdlc-trace-node trace-edge: sdlc-trace-edge trace-rule: sdlc-trace-rule
      change-impact: sdlc-change-impact
      design-assumption: sdlc-design-assumption design-guarantee: sdlc-design-guarantee
      design-variation: sdlc-design-variation design-contract: sdlc-design-contract
      design-clause?: sdlc-design-clause? design-variation?: sdlc-design-variation?
      design-contract?: sdlc-design-contract? design-contract-digest: digest
      design-replacement-review: sdlc-design-replacement-review
      design-implementation-link: (.get implementation link)
      design-implementation-link?: (.get implementation link?)
      design-implementation-review: (.get implementation review)
      design-guarantee-support-review:
      (make-sdlc-guarantee-support-review assurance digest implementation)))
