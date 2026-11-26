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

end LambdaAitiaProof.Modules.GitOps
