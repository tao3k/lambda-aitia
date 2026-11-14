// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

module AiAssuranceObjectives {
  type SourceStatus = Effective | Draft | Guidance
  type Role = AssistedDevelopment | DeliveredAi | RuntimeAgent

  pure def normativeSource(status: SourceStatus, adopted: bool): bool =
    status == Effective and adopted

  pure def obligations(roles: Set[Role]): Set[str] =
    (if (roles.contains(AssistedDevelopment))
      Set("generated-source-verification", "generation-provenance") else Set())
    .union(if (roles.contains(DeliveredAi))
      Set("configuration-evaluation", "independent-review") else Set())
    .union(if (roles.contains(RuntimeAgent))
      Set("tool-authority", "safe-refusal", "independent-review") else Set())

  pure def currentEvidence(dependencies: Set[str], changed: Set[str]): bool =
    dependencies.intersect(changed) == Set()

  pure val sourceVerification = Set("revision", "toolchain")
  pure val retrievalEvaluation = Set("model", "dataset", "index", "prompt", "policy")

  run adoptedEffectiveSourceTest = assert(normativeSource(Effective, true))
  run draftAndGuidanceExcludedTest = assert(and {
    not(normativeSource(Draft, true)),
    not(normativeSource(Guidance, true)),
    not(normativeSource(Effective, false)),
  })

  run assistedRepairTest = assert(and {
    obligations(Set(AssistedDevelopment)) ==
      Set("generated-source-verification", "generation-provenance"),
    currentEvidence(sourceVerification, Set("index")),
    not(currentEvidence(sourceVerification, Set("revision"))),
  })

  run deliveredAgentTest = assert(and {
    obligations(Set(DeliveredAi, RuntimeAgent)) ==
      Set("configuration-evaluation", "independent-review", "tool-authority", "safe-refusal"),
    not(currentEvidence(retrievalEvaluation, Set("index"))),
    not(currentEvidence(retrievalEvaluation, Set("model"))),
    not(currentEvidence(retrievalEvaluation, Set("policy"))),
    currentEvidence(sourceVerification, Set("model")),
  })
}
