// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/// Quint formal specification of RFC 0015:
/// RFC 6962 Domain-Separated Binary Merkle Inclusion Proofs (leaf tag 0 vs node tag 1)
/// and Zero-Authority Offline Verification Invariants.
module MerkleInclusionProof {
  pure val LEAF_TAG: int = 0
  pure val NODE_TAG: int = 1

  /// Deterministic injective algebraic model of tagged hashing for bounded verification.
  pure def leafHash(leafVal: int): int =
    LEAF_TAG * 100000 + leafVal

  pure def nodeHash(left: int, right: int): int =
    NODE_TAG * 1000000 + left * 1000 + right

  /// 4-leaf Merkle tree over (l0, l1, l2, l3):
  ///   p01 = nodeHash(leafHash(l0), leafHash(l1))
  ///   p23 = nodeHash(leafHash(l2), leafHash(l3))
  ///   root = nodeHash(p01, p23)
  pure def treeRoot(l0: int, l1: int, l2: int, l3: int): int =
    nodeHash(
      nodeHash(leafHash(l0), leafHash(l1)),
      nodeHash(leafHash(l2), leafHash(l3))
    )

  /// Verify inclusion proof for leaf index 1 (siblings: left=leafHash(l0), right=p23).
  pure def foldProofIdx1(
    claimedLeaf: int,
    sib0SideLeft: bool,
    sib0Hash: int,
    sib1SideLeft: bool,
    sib1Hash: int
  ): int = {
    val h0 = leafHash(claimedLeaf)
    val h1 = if (sib0SideLeft) nodeHash(sib0Hash, h0) else nodeHash(h0, sib0Hash)
    if (sib1SideLeft) nodeHash(sib1Hash, h1) else nodeHash(h1, sib1Hash)
  }

  var signedRoot: int
  var computedRoot: int
  var domainSeparated: bool
  var proofVerified: bool
  var actionAuthorized: bool

  action init = all {
    signedRoot' = treeRoot(10, 20, 30, 40),
    computedRoot' = 0,
    domainSeparated' = LEAF_TAG != NODE_TAG,
    proofVerified' = false,
    actionAuthorized' = false,
  }

  action verifyProofIdx1(
    claimedLeaf: int,
    sib0SideLeft: bool,
    sib0Hash: int,
    sib1SideLeft: bool,
    sib1Hash: int,
    expectedRoot: int
  ): bool = {
    val cRoot = foldProofIdx1(claimedLeaf, sib0SideLeft, sib0Hash, sib1SideLeft, sib1Hash)
    all {
      signedRoot' = expectedRoot,
      computedRoot' = cRoot,
      domainSeparated' = (LEAF_TAG != NODE_TAG),
      proofVerified' = ((LEAF_TAG != NODE_TAG) and (cRoot == expectedRoot)),
      actionAuthorized' = false,
    }
  }

  /// Negative control: accept proof without comparing computedRoot against signedRoot.
  action unsafeAcceptWithoutRootCheck(claimedLeaf: int): bool = all {
    computedRoot' = leafHash(claimedLeaf),
    proofVerified' = true,
    signedRoot' = signedRoot,
    domainSeparated' = domainSeparated,
    actionAuthorized' = false,
  }

  val merkleInclusionSafetyInvariant: bool = and {
    not(actionAuthorized),
    domainSeparated,
    proofVerified implies (computedRoot == signedRoot),
  }

  run validInclusionProofAcceptedTest = {
    val root = treeRoot(10, 20, 30, 40)
    val sib0 = leafHash(10)
    val sib1 = nodeHash(leafHash(30), leafHash(40))
    init
      .then(verifyProofIdx1(20, true, sib0, false, sib1, root))
      .expect(proofVerified and merkleInclusionSafetyInvariant)
  }

  run tamperedLeafRejectedTest = {
    val root = treeRoot(10, 20, 30, 40)
    val sib0 = leafHash(10)
    val sib1 = nodeHash(leafHash(30), leafHash(40))
    init
      .then(verifyProofIdx1(21, true, sib0, false, sib1, root))
      .expect(not(proofVerified) and merkleInclusionSafetyInvariant)
  }

  run swappedSiblingOrderRejectedTest = {
    val root = treeRoot(10, 20, 30, 40)
    val sib0 = leafHash(10)
    val sib1 = nodeHash(leafHash(30), leafHash(40))
    init
      .then(verifyProofIdx1(20, false, sib0, false, sib1, root))
      .expect(not(proofVerified) and merkleInclusionSafetyInvariant)
  }

  run domainSeparationPreventsSecondPreimageTest = {
    val root = treeRoot(10, 20, 30, 40)
    val p01 = nodeHash(leafHash(10), leafHash(20))
    val p23 = nodeHash(leafHash(30), leafHash(40))
    // Presenting internal node hash `p01` as a leaf value cannot match `nodeHash(p01, p23)`!
    init
      .then(verifyProofIdx1(p01, false, p23, false, 0, root))
      .expect(not(proofVerified) and merkleInclusionSafetyInvariant)
  }

  run staleRootMismatchRejectedTest = {
    val staleRoot = treeRoot(10, 20, 30, 41)
    val sib0 = leafHash(10)
    val sib1 = nodeHash(leafHash(30), leafHash(40))
    init
      .then(verifyProofIdx1(20, true, sib0, false, sib1, staleRoot))
      .expect(not(proofVerified) and merkleInclusionSafetyInvariant)
  }

  run unsafeSkipRootCheckViolatesInvariantTest =
    init
      .then(unsafeAcceptWithoutRootCheck(99))
      .expect(not(merkleInclusionSafetyInvariant))
}
