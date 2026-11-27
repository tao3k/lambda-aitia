-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

namespace LambdaAitiaProof.Modules.GitOps

/-- A successful publication compares the current head and installs a distinct operation. -/
def Publishes (expected before after : Nat) : Prop :=
  before = expected ∧ after ≠ before

/-- A successful admission takes a current, unused grant and marks it consumed. -/
def Admits (current : Bool) (before after : Bool) : Prop :=
  current = true ∧ before = false ∧ after = true

theorem sameExpectedHeadCannotPublishTwice
    {expected before middle after : Nat}
    (first : Publishes expected before middle) :
    ¬ Publishes expected middle after := by
  intro second
  exact first.2 (second.1.trans first.1.symm)

theorem consumedGrantCannotBeAdmittedAgain
    {current nextCurrent before middle after : Bool}
    (first : Admits current before middle) :
    ¬ Admits nextCurrent middle after := by
  intro second
  cases first.2.2.symm.trans second.2.1

theorem withdrawnGrantCannotBeAdmitted {before after : Bool} :
    ¬ Admits false before after := by
  intro admission
  cases admission.1

/-- Bazel Skyframe two-level Early Cutoff: upstream commit advanced, interface digest unchanged. -/
def EarlyCutoff (expectedCommit actualCommit expectedIface actualIface : Nat) : Prop :=
  expectedCommit ≠ actualCommit ∧ expectedIface = actualIface

/-- Bazel Bzlmod / IOHK CHaP transitive diamond coherence between two peer pins on a shared ancestor. -/
def DiamondCoherent (pinLeft pinRight : Nat) : Prop :=
  pinLeft = pinRight

/-- Wave dependency barrier: downstream fenced effects require upstream quiescence. -/
def DownstreamEffectAllowed (upstreamQuiescent : Bool) : Prop :=
  upstreamQuiescent = true

theorem earlyCutoffRequiresUnchangedInterface
    {expectedCommit actualCommit expectedIface actualIface : Nat}
    (h : EarlyCutoff expectedCommit actualCommit expectedIface actualIface) :
    expectedIface = actualIface :=
  h.2

theorem interfaceChangePreventsEarlyCutoff
    {expectedCommit actualCommit expectedIface actualIface : Nat}
    (hDiff : expectedIface ≠ actualIface) :
    ¬ EarlyCutoff expectedCommit actualCommit expectedIface actualIface := by
  intro hCutoff
  exact hDiff hCutoff.2

theorem diamondConflictBlocksConsumerClosure
    {pinLeft pinRight : Nat}
    (hConflict : pinLeft ≠ pinRight) :
    ¬ DiamondCoherent pinLeft pinRight := by
  intro hCoherent
  exact hConflict hCoherent

theorem waveBarrierPreventsPrematureDownstreamEffect :
    ¬ DownstreamEffectAllowed false := by
  intro hAllowed
  cases hAllowed

/-- Multi-repo Saga partial-wave barrier: consumer publish requires both concurrent peers. -/
def WaveConsumerCanPublish (peerLeftReady peerRightReady : Bool) : Prop :=
  peerLeftReady = true ∧ peerRightReady = true

/-- Durable checkpoint at-most-once publication guard. -/
def CheckpointAllowsPublish (alreadyPublished : Bool) : Prop :=
  alreadyPublished = false

/-- Signed human decision replay guard over applied decision IDs. -/
def FreshDecision (decisionId : Nat) (applied : List Nat) : Prop :=
  decisionId ∉ applied

theorem partialWaveBlocksConsumerPublish :
    ¬ WaveConsumerCanPublish true false := by
  intro h
  cases h.2

theorem checkpointPreventsDuplicatePublish :
    ¬ CheckpointAllowsPublish true := by
  intro h
  cases h

theorem appliedDecisionCannotReplay
    {decisionId : Nat} {applied : List Nat}
    (hMem : decisionId ∈ applied) :
    ¬ FreshDecision decisionId applied := by
  intro hFresh
  exact hFresh hMem

theorem semanticAstEquivalencePreservesCutoff
    {α β : Type} (hash : α → β) {astBefore astAfter : α}
    (hEq : astBefore = astAfter) :
    hash astBefore = hash astAfter :=
  congrArg hash hEq

/-- RFC 0010 Adapton/Salsa memo key equality across repo commit, upstream interface, and policy. -/
def CacheKeyMatches (rc ui pd ac aui apd : Nat) : Prop :=
  rc = ac ∧ ui = aui ∧ pd = apd

/-- RFC 0010 in-toto/SLSA offline release attestation validity predicate. -/
def AttestationValid (sigValid : Bool) (missingReports : Nat) : Prop :=
  sigValid = true ∧ missingReports = 0

theorem attestationCacheHitRequiresMatchingKey
    {rc ui pd ac aui apd : Nat}
    (hMatch : CacheKeyMatches rc ui pd ac aui apd) :
    ui = aui :=
  hMatch.2.1

theorem staleUpstreamInterfaceInvalidatesCache
    {rc ui pd ac aui apd : Nat}
    (hDiff : ui ≠ aui) :
    ¬ CacheKeyMatches rc ui pd ac aui apd := by
  intro hMatch
  exact hDiff hMatch.2.1

theorem forgedAttestationSignatureRejected {missingReports : Nat} :
    ¬ AttestationValid false missingReports := by
  intro hValid
  cases hValid.1

theorem incompleteWaveBundleRejected {sigValid : Bool} {k : Nat} :
    ¬ AttestationValid sigValid (Nat.succ k) := by
  intro hValid
  cases hValid.2

/-- RFC 0011 TUF k-of-n threshold attestation admissibility predicate. -/
def TufBundleAdmissible
    (distinctAuthorizedNonRevoked : Nat)
    (threshold : Nat)
    (hasRevokedSigner : Bool)
    (bundleEpoch minEpoch : Nat) : Prop :=
  threshold ≥ 1 ∧
  hasRevokedSigner = false ∧
  distinctAuthorizedNonRevoked ≥ threshold ∧
  bundleEpoch ≥ minEpoch

/-- RFC 0011 Counterfactual competing-branch evaluation never grants authority. -/
def CounterfactualEvaluationSafe (hypothetical actionAuthorized : Bool) : Prop :=
  hypothetical = true ∧ actionAuthorized = false

theorem duplicateKeyCannotSatisfyThreshold
    {threshold : Nat} (hTwo : threshold ≥ 2) {hasRevoked : Bool} {ep minEp : Nat} :
    ¬ TufBundleAdmissible 1 threshold hasRevoked ep minEp := by
  intro hAdm
  exact Nat.not_le_of_gt (Nat.lt_succ_self 1) (Nat.le_trans hTwo hAdm.2.2.1)

theorem revokedKeyExcludedFromQuorum
    {distinct threshold ep minEp : Nat} :
    ¬ TufBundleAdmissible distinct threshold true ep minEp := by
  intro hAdm
  cases hAdm.2.1

theorem epochRollbackRejected
    {distinct threshold ep minEp : Nat} (hOld : ep < minEp) :
    ¬ TufBundleAdmissible distinct threshold false ep minEp := by
  intro hAdm
  exact Nat.not_le_of_gt hOld hAdm.2.2.2

theorem counterfactualEvaluationPreservesZeroAuthority
    {hypothetical actionAuthorized : Bool}
    (hSafe : CounterfactualEvaluationSafe hypothetical actionAuthorized) :
    actionAuthorized = false :=
  hSafe.2

/-- RFC 0012 TUF dual-quorum root rotation admissibility predicate. -/
def RootRotationAdmissible
    (oldVer newVer oldMinEp newMinEp oldValid newValid oldThresh newThresh : Nat) : Prop :=
  newVer = oldVer + 1 ∧
  newMinEp ≥ oldMinEp ∧
  oldThresh ≥ 1 ∧
  newThresh ≥ 1 ∧
  oldValid ≥ oldThresh ∧
  newValid ≥ newThresh

/-- RFC 0012 Multi-epoch parent-linked attestation chain step validity predicate. -/
def AttestationLinkValid
    (prevHash parentHash : Nat) (prevEpoch nextEpoch : Nat) : Prop :=
  parentHash = prevHash ∧ nextEpoch > prevEpoch

theorem rootRotationRequiresDualQuorum
    {oldVer newVer oldMinEp newMinEp oldValid newValid oldThresh newThresh : Nat}
    (hRot : RootRotationAdmissible oldVer newVer oldMinEp newMinEp oldValid newValid oldThresh newThresh) :
    oldValid ≥ oldThresh ∧ newValid ≥ newThresh :=
  ⟨hRot.2.2.2.2.1, hRot.2.2.2.2.2⟩

theorem rootVersionSkipRejected
    {oldVer newVer oldMinEp newMinEp oldValid newValid oldThresh newThresh : Nat}
    (hSkip : newVer ≠ oldVer + 1) :
    ¬ RootRotationAdmissible oldVer newVer oldMinEp newMinEp oldValid newValid oldThresh newThresh := by
  intro hRot
  exact hSkip hRot.1

theorem attestationChainRequiresParentLink
    {prevHash parentHash prevEpoch nextEpoch : Nat}
    (hBroken : parentHash ≠ prevHash) :
    ¬ AttestationLinkValid prevHash parentHash prevEpoch nextEpoch := by
  intro hLink
  exact hBroken hLink.1

theorem attestationChainRequiresStrictlyIncreasingEpoch
    {prevHash parentHash prevEpoch nextEpoch : Nat}
    (hNonInc : nextEpoch ≤ prevEpoch) :
    ¬ AttestationLinkValid prevHash parentHash prevEpoch nextEpoch := by
  intro hLink
  exact Nat.not_le_of_gt hLink.2 hNonInc

/-- RFC 0013 Benveniste et al. Assume-Guarantee cross-repo contract discharge predicate. -/
def ContractDischarged (assumes guarantees : List Nat) : Prop :=
  ∀ a, a ∈ assumes → a ∈ guarantees

/-- RFC 0013 SysML-pinned TUF policy floor admissibility predicate. -/
def SysmlTufPolicySatisfied (rtThresh rtMinEp polThresh polMinEp : Nat) : Prop :=
  rtThresh ≥ polThresh ∧ rtMinEp ≥ polMinEp

theorem missingUpstreamGuaranteeBlocksComposition
    {a : Nat} {assumes guarantees : List Nat}
    (hAssumed : a ∈ assumes) (hNotGuaranteed : a ∉ guarantees) :
    ¬ ContractDischarged assumes guarantees := by
  intro hDischarged
  exact hNotGuaranteed (hDischarged a hAssumed)

theorem satisfiedAssumptionsAdmitComposition
    {assumes guarantees : List Nat}
    (hAll : ∀ a, a ∈ assumes → a ∈ guarantees) :
    ContractDischarged assumes guarantees :=
  hAll

theorem weakenedThresholdRejectedBySysmlPolicy
    {rtThresh rtMinEp polThresh polMinEp : Nat}
    (hWeak : rtThresh < polThresh) :
    ¬ SysmlTufPolicySatisfied rtThresh rtMinEp polThresh polMinEp := by
  intro hSat
  exact Nat.not_le_of_gt hWeak hSat.1

theorem weakenedMinEpochRejectedBySysmlPolicy
    {rtThresh rtMinEp polThresh polMinEp : Nat}
    (hWeak : rtMinEp < polMinEp) :
    ¬ SysmlTufPolicySatisfied rtThresh rtMinEp polThresh polMinEp := by
  intro hSat
  exact Nat.not_le_of_gt hWeak hSat.2

/-- RFC 0014 Air-gapped offline audit admissibility predicate. -/
def OfflineAuditAdmissible
    (verifierThresh verifierMinEp rtThresh rtMinEp : Nat)
    (chainValid actionAuthorized : Bool)
    (expectedRepos coveredRepos : List Nat) : Prop :=
  chainValid = true ∧
  actionAuthorized = false ∧
  rtThresh ≥ verifierThresh ∧
  rtMinEp ≥ verifierMinEp ∧
  ∀ r, r ∈ expectedRepos → r ∈ coveredRepos

theorem verifierPinnedPolicyOverridesUntrustedBundle
    {verifierThresh verifierMinEp rtThresh rtMinEp : Nat}
    {chainValid actionAuthorized : Bool}
    {expectedRepos coveredRepos : List Nat}
    (hWeak : rtThresh < verifierThresh) :
    ¬ OfflineAuditAdmissible
        verifierThresh verifierMinEp rtThresh rtMinEp
        chainValid actionAuthorized expectedRepos coveredRepos := by
  intro hAdm
  exact Nat.not_le_of_gt hWeak hAdm.2.2.1

theorem missingExpectedRepoBlocksOfflineAudit
    {r verifierThresh verifierMinEp rtThresh rtMinEp : Nat}
    {chainValid actionAuthorized : Bool}
    {expectedRepos coveredRepos : List Nat}
    (hExpected : r ∈ expectedRepos) (hMissing : r ∉ coveredRepos) :
    ¬ OfflineAuditAdmissible
        verifierThresh verifierMinEp rtThresh rtMinEp
        chainValid actionAuthorized expectedRepos coveredRepos := by
  intro hAdm
  exact hMissing (hAdm.2.2.2.2 r hExpected)

theorem airGappedVerdictGrantsNoAuthority
    {verifierThresh verifierMinEp rtThresh rtMinEp : Nat}
    {chainValid actionAuthorized : Bool}
    {expectedRepos coveredRepos : List Nat}
    (hAdm : OfflineAuditAdmissible
        verifierThresh verifierMinEp rtThresh rtMinEp
        chainValid actionAuthorized expectedRepos coveredRepos) :
    actionAuthorized = false :=
  hAdm.2.1

theorem completeChainAndInventoryAdmitOfflineAudit
    {verifierThresh verifierMinEp rtThresh rtMinEp : Nat}
    {expectedRepos coveredRepos : List Nat}
    (hThresh : rtThresh ≥ verifierThresh)
    (hEpoch : rtMinEp ≥ verifierMinEp)
    (hCov : ∀ r, r ∈ expectedRepos → r ∈ coveredRepos) :
    OfflineAuditAdmissible
      verifierThresh verifierMinEp rtThresh rtMinEp
      true false expectedRepos coveredRepos :=
  ⟨rfl, rfl, hThresh, hEpoch, hCov⟩

/-- RFC 0015 RFC 6962 binary Merkle inclusion proof validity predicate. -/
def MerkleInclusionValid
    (leafTag nodeTag : Nat) (computedRoot signedRoot : Nat) (actionAuthorized : Bool) : Prop :=
  leafTag ≠ nodeTag ∧ computedRoot = signedRoot ∧ actionAuthorized = false

theorem merkleDomainSeparationDistinct : (0 : Nat) ≠ 1 := by
  intro hEq
  cases hEq

theorem merkleProofRequiresMatchingRoot
    {leafTag nodeTag computedRoot signedRoot : Nat} {actionAuthorized : Bool}
    (hDiff : computedRoot ≠ signedRoot) :
    ¬ MerkleInclusionValid leafTag nodeTag computedRoot signedRoot actionAuthorized := by
  intro hValid
  exact hDiff hValid.2.1

theorem merkleInclusionPreservesZeroAuthority
    {leafTag nodeTag computedRoot signedRoot : Nat} {actionAuthorized : Bool}
    (hValid : MerkleInclusionValid leafTag nodeTag computedRoot signedRoot actionAuthorized) :
    actionAuthorized = false :=
  hValid.2.2

theorem tamperedLeafChangesMerkleRootUnderInjectiveHash
    {α β : Type} (rootOf : α → β)
    (hInj : ∀ x y, rootOf x = rootOf y → x = y)
    {leafBefore leafAfter : α} (hDiff : leafBefore ≠ leafAfter) :
    rootOf leafBefore ≠ rootOf leafAfter := by
  intro hEq
  exact hDiff (hInj leafBefore leafAfter hEq)

/-- RFC 0016 RFC 6962 §2.1.2 append-only transparency log consistency validity predicate. -/
def ConsistencyProofValid
    (firstSize secondSize expectedFirst recomputedFirst expectedSecond recomputedSecond : Nat)
    (actionAuthorized : Bool) : Prop :=
  firstSize ≥ 1 ∧
  firstSize ≤ secondSize ∧
  recomputedFirst = expectedFirst ∧
  recomputedSecond = expectedSecond ∧
  actionAuthorized = false

theorem consistencyProofRejectsLogTruncation
    {firstSize secondSize expectedFirst recomputedFirst expectedSecond recomputedSecond : Nat}
    {actionAuthorized : Bool}
    (hTrunc : secondSize < firstSize) :
    ¬ ConsistencyProofValid
        firstSize secondSize expectedFirst recomputedFirst
        expectedSecond recomputedSecond actionAuthorized := by
  intro hValid
  exact Nat.not_le_of_gt hTrunc hValid.2.1

theorem consistencyProofRequiresOldRootMatch
    {firstSize secondSize expectedFirst recomputedFirst expectedSecond recomputedSecond : Nat}
    {actionAuthorized : Bool}
    (hEquiv : recomputedFirst ≠ expectedFirst) :
    ¬ ConsistencyProofValid
        firstSize secondSize expectedFirst recomputedFirst
        expectedSecond recomputedSecond actionAuthorized := by
  intro hValid
  exact hEquiv hValid.2.2.1

theorem consistencyProofRequiresNewRootMatch
    {firstSize secondSize expectedFirst recomputedFirst expectedSecond recomputedSecond : Nat}
    {actionAuthorized : Bool}
    (hFork : recomputedSecond ≠ expectedSecond) :
    ¬ ConsistencyProofValid
        firstSize secondSize expectedFirst recomputedFirst
        expectedSecond recomputedSecond actionAuthorized := by
  intro hValid
  exact hFork hValid.2.2.2.1

theorem consistencyProofPreservesZeroAuthority
    {firstSize secondSize expectedFirst recomputedFirst expectedSecond recomputedSecond : Nat}
    {actionAuthorized : Bool}
    (hValid : ConsistencyProofValid
        firstSize secondSize expectedFirst recomputedFirst
        expectedSecond recomputedSecond actionAuthorized) :
    actionAuthorized = false :=
  hValid.2.2.2.2

/-- RFC 0017 witness-cosigned checkpoint quorum validity predicate. -/
def WitnessCheckpointQuorumValid
    (originMatches originSigValid : Bool)
    (distinctTrustedActiveWitnesses threshold : Nat)
    (actionAuthorized : Bool) : Prop :=
  originMatches = true ∧
  originSigValid = true ∧
  threshold ≥ 1 ∧
  distinctTrustedActiveWitnesses ≥ threshold ∧
  actionAuthorized = false

/-- RFC 0017 non-repudiable cross-auditor same-size split-view equivocation evidence predicate. -/
def SplitViewEquivocationEvidence
    (originMatches originSigValid : Bool)
    (leftSize rightSize leftRoot rightRoot : Nat)
    (actionAuthorized : Bool) : Prop :=
  originMatches = true ∧
  originSigValid = true ∧
  leftSize ≥ 1 ∧
  leftSize = rightSize ∧
  leftRoot ≠ rightRoot ∧
  actionAuthorized = false

theorem duplicateWitnessCannotSatisfyQuorum
    {originMatches originSigValid : Bool}
    {distinctTrustedActiveWitnesses threshold : Nat}
    {actionAuthorized : Bool}
    (hBelow : distinctTrustedActiveWitnesses < threshold) :
    ¬ WitnessCheckpointQuorumValid
        originMatches originSigValid distinctTrustedActiveWitnesses threshold actionAuthorized := by
  intro hValid
  exact Nat.not_le_of_gt hBelow hValid.2.2.2.1

theorem revokedWitnessExcludedFromCheckpointQuorum
    {originMatches originSigValid : Bool}
    {remainingActiveWitnesses threshold : Nat}
    {actionAuthorized : Bool}
    (hRevokedDrop : remainingActiveWitnesses < threshold) :
    ¬ WitnessCheckpointQuorumValid
        originMatches originSigValid remainingActiveWitnesses threshold actionAuthorized := by
  intro hValid
  exact Nat.not_le_of_gt hRevokedDrop hValid.2.2.2.1

theorem sameSizeDistinctRootsYieldEquivocation
    {size leftRoot rightRoot : Nat}
    (hPos : size ≥ 1)
    (hDiff : leftRoot ≠ rightRoot) :
    SplitViewEquivocationEvidence true true size size leftRoot rightRoot false :=
  ⟨rfl, rfl, hPos, rfl, hDiff, rfl⟩

theorem equivocationEvidencePreservesZeroAuthority
    {originMatches originSigValid : Bool}
    {leftSize rightSize leftRoot rightRoot : Nat}
    {actionAuthorized : Bool}
    (hEv : SplitViewEquivocationEvidence
        originMatches originSigValid leftSize rightSize leftRoot rightRoot actionAuthorized) :
    actionAuthorized = false :=
  hEv.2.2.2.2.2

/-- RFC 0018 unified witness-backed air-gapped audit admissibility predicate. -/
def UnifiedAirGapAuditValid
    (tufChainValid witnessQuorumMet consistencyValid headBoundToLog merkleInclusionValid : Bool)
    (gossipEquivocationDetected gossipUnresolvedPeer actionAuthorized : Bool) : Prop :=
  tufChainValid = true ∧
  witnessQuorumMet = true ∧
  consistencyValid = true ∧
  headBoundToLog = true ∧
  merkleInclusionValid = true ∧
  gossipEquivocationDetected = false ∧
  gossipUnresolvedPeer = false ∧
  actionAuthorized = false

theorem gossipEquivocationBlocksUnifiedAudit
    {tuf witness cons headBound merkle unresolved auth : Bool} :
    ¬ UnifiedAirGapAuditValid tuf witness cons headBound merkle true unresolved auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.2.2.2.2.1

theorem unresolvedPeerBlocksUnifiedAudit
    {tuf witness cons headBound merkle equiv auth : Bool} :
    ¬ UnifiedAirGapAuditValid tuf witness cons headBound merkle equiv true auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.2.2.2.2.2.1

theorem unboundHeadAttestationBlocksUnifiedAudit
    {tuf witness cons merkle equiv unresolved auth : Bool} :
    ¬ UnifiedAirGapAuditValid tuf witness cons false merkle equiv unresolved auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.2.2.1

theorem unifiedAirGapAuditPreservesZeroAuthority
    {tuf witness cons headBound merkle equiv unresolved auth : Bool}
    (hValid : UnifiedAirGapAuditValid tuf witness cons headBound merkle equiv unresolved auth) :
    auth = false :=
  hValid.2.2.2.2.2.2.2

/-- RFC 0019 DSSE in-toto v1 / SLSA v1.0 PAE envelope validity predicate. -/
def DsseInTotoValid
    (payloadTypeValid paeBound headDigestMatches : Bool)
    (distinctActiveSigners threshold epoch minEpoch : Nat)
    (actionAuthorized : Bool) : Prop :=
  payloadTypeValid = true ∧
  paeBound = true ∧
  headDigestMatches = true ∧
  threshold ≥ 1 ∧
  distinctActiveSigners ≥ threshold ∧
  epoch ≥ minEpoch ∧
  actionAuthorized = false

theorem dssePayloadTypeConfusionRejected
    {paeBound headOk : Bool} {signers threshold epoch minEpoch : Nat} {auth : Bool} :
    ¬ DsseInTotoValid false paeBound headOk signers threshold epoch minEpoch auth := by
  intro hValid
  exact Bool.noConfusion hValid.1

theorem dsseDuplicateOrRevokedQuorumRejected
    {pType paeBound headOk : Bool} {signers threshold epoch minEpoch : Nat} {auth : Bool}
    (hBelow : signers < threshold) :
    ¬ DsseInTotoValid pType paeBound headOk signers threshold epoch minEpoch auth := by
  intro hValid
  exact Nat.not_le_of_gt hBelow hValid.2.2.2.2.1

theorem dsseHeadDigestMismatchRejected
    {pType paeBound : Bool} {signers threshold epoch minEpoch : Nat} {auth : Bool} :
    ¬ DsseInTotoValid pType paeBound false signers threshold epoch minEpoch auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.2.1

theorem dsseInTotoPreservesZeroAuthority
    {pType paeBound headOk : Bool} {signers threshold epoch minEpoch : Nat} {auth : Bool}
    (hValid : DsseInTotoValid pType paeBound headOk signers threshold epoch minEpoch auth) :
    auth = false :=
  hValid.2.2.2.2.2.2

/-- RFC 0020 Sigstore Bundle v0.3 + federated multi-org witness quorum & freshness predicate. -/
def SigstoreFederatedBundleValid
    (dsseValid tlogInclusionValid : Bool)
    (witnessCount minWitnesses distinctOrgs minDistinctOrgs : Nat)
    (minTs maxTs notBefore notAfter observedSkew maxSkew : Nat)
    (actionAuthorized : Bool) : Prop :=
  dsseValid = true ∧
  tlogInclusionValid = true ∧
  witnessCount ≥ minWitnesses ∧
  distinctOrgs ≥ minDistinctOrgs ∧
  notBefore ≤ minTs ∧
  maxTs ≤ notAfter ∧
  observedSkew ≤ maxSkew ∧
  actionAuthorized = false

theorem singleOrgCollusionRejectedByFederation
    {dOk incOk : Bool} {wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew : Nat} {auth : Bool}
    (hCollusion : orgs < minOrgs) :
    ¬ SigstoreFederatedBundleValid dOk incOk wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew auth := by
  intro hValid
  exact Nat.not_le_of_gt hCollusion hValid.2.2.2.1

theorem excessiveWitnessSkewRejected
    {dOk incOk : Bool} {wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew : Nat} {auth : Bool}
    (hSkew : maxSkew < skew) :
    ¬ SigstoreFederatedBundleValid dOk incOk wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew auth := by
  intro hValid
  exact Nat.not_le_of_gt hSkew hValid.2.2.2.2.2.2.1

theorem staleWitnessTimestampRejected
    {dOk incOk : Bool} {wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew : Nat} {auth : Bool}
    (hStale : minTs < nb) :
    ¬ SigstoreFederatedBundleValid dOk incOk wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew auth := by
  intro hValid
  exact Nat.not_le_of_gt hStale hValid.2.2.2.2.1

theorem sigstoreFederatedBundlePreservesZeroAuthority
    {dOk incOk : Bool} {wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew : Nat} {auth : Bool}
    (hValid : SigstoreFederatedBundleValid dOk incOk wCount minW orgs minOrgs minTs maxTs nb na skew maxSkew auth) :
    auth = false :=
  hValid.2.2.2.2.2.2.2

/-- RFC 0021 detached sidecar AI audit & NASA commit provenance validity predicate. -/
def DetachedSidecarAuditValid
    (upstreamPollutionFree lensesCovered swe146Provenance conversationBound humanApproved : Bool)
    (currentContext aiAuditContext unaddressedHighFindings : Nat)
    (actionAuthorized : Bool) : Prop :=
  upstreamPollutionFree = true ∧
  currentContext = aiAuditContext ∧
  lensesCovered = true ∧
  swe146Provenance = true ∧
  conversationBound = true ∧
  unaddressedHighFindings = 0 ∧
  humanApproved = true ∧
  actionAuthorized = false

theorem upstreamPollutionBlocksDetachedAudit
    {lenses prov conv human : Bool} {curCtx aiCtx unaddressed : Nat} {auth : Bool} :
    ¬ DetachedSidecarAuditValid false lenses prov conv human curCtx aiCtx unaddressed auth := by
  intro hValid
  exact Bool.noConfusion hValid.1

theorem staleAiContextBlocksDetachedAudit
    {clean lenses prov conv human : Bool} {curCtx aiCtx unaddressed : Nat} {auth : Bool}
    (hStale : curCtx ≠ aiCtx) :
    ¬ DetachedSidecarAuditValid clean lenses prov conv human curCtx aiCtx unaddressed auth := by
  intro hValid
  exact hStale hValid.2.1

theorem unaddressedHighFindingBlocksDetachedAudit
    {clean lenses prov conv human : Bool} {curCtx aiCtx unaddressed : Nat} {auth : Bool}
    (hUnaddressed : unaddressed > 0) :
    ¬ DetachedSidecarAuditValid clean lenses prov conv human curCtx aiCtx unaddressed auth := by
  intro hValid
  have hZero : unaddressed = 0 := hValid.2.2.2.2.2.1
  rw [hZero] at hUnaddressed
  exact Nat.not_lt_zero 0 hUnaddressed

theorem detachedSidecarAuditPreservesZeroAuthority
    {clean lenses prov conv human : Bool} {curCtx aiCtx unaddressed : Nat} {auth : Bool}
    (hValid : DetachedSidecarAuditValid clean lenses prov conv human curCtx aiCtx unaddressed auth) :
    auth = false :=
  hValid.2.2.2.2.2.2.2

/-- RFC 0022 linked Scheme/POO gerbil-ascent -> Native AI / Marlin Agent Core closure predicate. -/
def SchemeAscentSidecarClosure
    (missingLenses ascentBlockers : Nat)
    (allEnginesSanctioned : Bool)
    (actionAuthorized : Bool) : Prop :=
  missingLenses = 0 ∧
  allEnginesSanctioned = true ∧
  ascentBlockers = 0 ∧
  actionAuthorized = false

theorem ascentMissingLensBlocksClosure
    {missing blockers : Nat} {sanctioned auth : Bool}
    (hMissing : missing > 0) :
    ¬ SchemeAscentSidecarClosure missing blockers sanctioned auth := by
  intro hValid
  have hZero : missing = 0 := hValid.1
  rw [hZero] at hMissing
  exact Nat.not_lt_zero 0 hMissing

theorem unsanctionedEngineBindingBlocksClosure
    {missing blockers : Nat} {auth : Bool} :
    ¬ SchemeAscentSidecarClosure missing blockers false auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.1

theorem ascentBlockerPreventsMarlinPromotion
    {missing blockers : Nat} {sanctioned auth : Bool}
    (hBlocked : blockers > 0) :
    ¬ SchemeAscentSidecarClosure missing blockers sanctioned auth := by
  intro hValid
  have hZero : blockers = 0 := hValid.2.2.1
  rw [hZero] at hBlocked
  exact Nat.not_lt_zero 0 hBlocked

theorem schemeAscentBridgePreservesZeroAuthority
    {missing blockers : Nat} {sanctioned auth : Bool}
    (hValid : SchemeAscentSidecarClosure missing blockers sanctioned auth) :
    auth = false :=
  hValid.2.2.2

/-- RFC 0023 Deterministic Engineering formal library reuse (`upstream-library-reuse`),
    ephemeral AI overlay anti-vacuity (`ephemeral-ai-overlay` requiring `@countermodel`
    and sidecar vault isolation), G2 mechanical defect / F3 guard-probe / PendingMethod
    closure predicate. -/
def DeFormalReviewClosure
    (ephemeralOverlay resolverPinned countermodelVerified sidecarVaultOnly proofClean modelPassed : Bool)
    (g2Defects redundantGuardProbes pendingOracles : Nat)
    (actionAuthorized : Bool) : Prop :=
  resolverPinned = true ∧
  proofClean = true ∧
  modelPassed = true ∧
  (ephemeralOverlay = true → countermodelVerified = true ∧ sidecarVaultOnly = true) ∧
  g2Defects = 0 ∧
  redundantGuardProbes = 0 ∧
  pendingOracles = 0 ∧
  actionAuthorized = false

theorem vacuousEphemeralOverlayBlocksReview
    {pinned vault clean passed auth : Bool} {g2 probes pending : Nat} :
    ¬ DeFormalReviewClosure true pinned false vault clean passed g2 probes pending auth := by
  intro hValid
  have hCm := (hValid.2.2.2.1 rfl).1
  exact Bool.noConfusion hCm

theorem unresolvedFormalLibraryBlocksReview
    {eph cm vault clean passed auth : Bool} {g2 probes pending : Nat} :
    ¬ DeFormalReviewClosure eph false cm vault clean passed g2 probes pending auth := by
  intro hValid
  exact Bool.noConfusion hValid.1

theorem g2DefectOrPendingOracleBlocksReview
    {eph pinned cm vault clean passed auth : Bool} {g2 probes pending : Nat}
    (hFail : g2 > 0 ∨ pending > 0) :
    ¬ DeFormalReviewClosure eph pinned cm vault clean passed g2 probes pending auth := by
  intro hValid
  cases hFail with
  | inl hG2 =>
    have hZero : g2 = 0 := hValid.2.2.2.2.1
    rw [hZero] at hG2
    exact Nat.not_lt_zero 0 hG2
  | inr hPend =>
    have hZero : pending = 0 := hValid.2.2.2.2.2.2.1
    rw [hZero] at hPend
    exact Nat.not_lt_zero 0 hPend

theorem deFormalReviewPreservesZeroAuthority
    {eph pinned cm vault clean passed auth : Bool} {g2 probes pending : Nat}
    (hValid : DeFormalReviewClosure eph pinned cm vault clean passed g2 probes pending auth) :
    auth = false :=
  hValid.2.2.2.2.2.2.2

/-- RFC 0024 process-isolated Marlin gRPC sidecar gateway control-plane confinement
    predicate (aligned with DE SM24 / SM25 / SM26). -/
def MarlinGrpcGatewayAdmissible
    (loopbackBind tokenConfigured tokenNonBlank tokenNonDefault
     estopActive rpcAuthenticated rpcFrameValid actionAuthorized : Bool) : Prop :=
  (loopbackBind = false → tokenConfigured = true ∧ tokenNonBlank = true ∧ tokenNonDefault = true) ∧
  (tokenConfigured = true → tokenNonBlank = true) ∧
  estopActive = false ∧
  rpcAuthenticated = true ∧
  rpcFrameValid = true ∧
  actionAuthorized = false

theorem nonLoopbackWithoutBearerRejected
    {nb nd estop authed frame auth : Bool} :
    ¬ MarlinGrpcGatewayAdmissible false false nb nd estop authed frame auth := by
  intro hValid
  have hCfg := (hValid.1 rfl).1
  exact Bool.noConfusion hCfg

theorem blankBearerCredentialRejected
    {lb nd estop authed frame auth : Bool} :
    ¬ MarlinGrpcGatewayAdmissible lb true false nd estop authed frame auth := by
  intro hValid
  have hNb := hValid.2.1 rfl
  exact Bool.noConfusion hNb

theorem activeEstopBlocksGatewayRpc
    {lb cfg nb nd authed frame auth : Bool} :
    ¬ MarlinGrpcGatewayAdmissible lb cfg nb nd true authed frame auth := by
  intro hValid
  exact Bool.noConfusion hValid.2.2.1

theorem marlinGrpcGatewayPreservesZeroAuthority
    {lb cfg nb nd estop authed frame auth : Bool}
    (hValid : MarlinGrpcGatewayAdmissible lb cfg nb nd estop authed frame auth) :
    auth = false :=
  hValid.2.2.2.2.2

end LambdaAitiaProof.Modules.GitOps
