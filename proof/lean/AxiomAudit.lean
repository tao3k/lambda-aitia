-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
--
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import LambdaAitiaProof.Modules.Assurance
import LambdaAitiaProof.Modules.Sdlc

open LambdaAitiaProof.Modules

#print axioms Assurance.Invalidation.impactMonotoneForFixedSnapshot
#print axioms Assurance.Invalidation.unresolvedFrontierBlocksClosure
#print axioms Assurance.Invalidation.inertReceiptGrantsNoAuthority
#print axioms Assurance.Composition.componentOnlyEvidenceCannotSupportComposite
#print axioms Assurance.Composition.directObligationNeeded
#print axioms Assurance.Composition.directWitnessDiffersFromComponentObligation
#print axioms Sdlc.Design.refinesRefl
#print axioms Sdlc.Design.refinesTrans
#print axioms Sdlc.Design.strongerAssumptionBlocks
#print axioms Sdlc.Design.droppedGuaranteeBlocks
#print axioms Sdlc.Retirement.initialSafe
#print axioms Sdlc.Retirement.stepPreservesSafety
#print axioms Sdlc.Retirement.reachableSafe
#print axioms Sdlc.Retirement.cancellationDoesNotJustifyRetirement
#print axioms Sdlc.Retirement.oldReviewDoesNotJustifyRetirement
#print axioms Sdlc.Retirement.unknownInventoryBlocksRetirement
#print axioms Sdlc.RetirementIngress.initialSafe
#print axioms Sdlc.RetirementIngress.currentGrantExcludesRetirement
#print axioms Sdlc.RetirementIngress.stepPreservesSafety
#print axioms Sdlc.RetirementIngress.reachableSafe
