;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(export job-retirement-quint-sources job-retirement-lean-sources
        job-retirement-scheme-sources)

;;; Dependency closure for the retirement slice, not unrelated assurance gates.
;;; Lists name repository source assets; they are not a second workflow DSL.
(def job-retirement-quint-sources
  '("dev/proof/quint/EffectAdmission.qnt"
    "dev/proof/quint/WorkCore.qnt"
    "dev/proof/quint/WorkLifecycle.qnt"
    "dev/proof/quint/RetirementReview.qnt"
    "dev/proof/quint/RetirementIngress.qnt"
    "dev/proof/quint/package.json"
    "dev/proof/quint/package-lock.json"
    "dev/proof/quint/tlc-config.json"
    "dev/proof/quint/check_contract.py"
    "dev/proof/quint/check_scheme_replay.py"
    "dev/proof/quint/process_runner.py"))
(def job-retirement-lean-sources
  '("dev/proof/lean/LambdaAitiaProof/Modules/Sdlc/Retirement.lean"
    "dev/proof/lean/LambdaAitiaProof/Modules/Sdlc/RetirementIngress.lean"))
(def job-retirement-scheme-sources
  '("modules/sdlc/retirement-host.ss"
    "dev/proof/scheme/retirement-execution-test.ss"
    "dev/proof/scheme/retirement-replay-test.ss"
    "justfile"
    ".github/workflows/ci.yml"
    "build.ss"))
