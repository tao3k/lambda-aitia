// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package AitiaProjectArchitecture {
    private import ScalarValues::*;

    doc /* Authoritative SysML v2 architectural ownership and commit scope model
         * for Lambda Aitia. Rust projects CommitScope parts from the recorded
         * JJ cut via OpenSysML and supplies them to Scheme ASCENT semantics
         * instead of hand-maintaining flat path lists in .agents/aita/project.json. */

    part def CommitScope {
        doc /* Architectural scope owning a set of repository path prefixes. */
        attribute scopeName : String;
        attribute ownedPaths : String[1..*];
    }

    part gitopsScope : CommitScope {
        doc /* Commit engineering, workflow orchestration, Rust runtime, bindings, and CI gates. */
        attribute :>> scopeName = "gitops";
        attribute :>> ownedPaths = (
            "modules/gitops",
            "modules/project-config",
            "modules/sdlc",
            "modules/workflow",
            "user-interface/scenarios/github-gitops",
            "rust/Cargo.toml",
            "rust/Cargo.lock",
            "rust/workspace.just",
            "rust/crates/aitia-jj",
            "rust/crates/aitia-runtime",
            "rust/crates/aitia-python",
            "rust/scheme",
            "bindings",
            ".agents/aita",
            ".github/workflows",
            "dev/qualification",
            "dev/sysml",
            "docs/rfcs",
            "examples",
            "t/harness",
            "t/library",
            "t/yanxu/modules/workflow",
            "gerbil.pkg",
            "AGENTS.md",
            "justfile"
        );
    }

    part sdlcScope : CommitScope {
        doc /* Standard-free SDLC core ontology, obligations, and pluggable standard profiles. */
        attribute :>> scopeName = "sdlc";
        attribute :>> ownedPaths = (
            "modules/sdlc",
            "t/yanxu/modules/sdlc",
            "user-interface/profiles/nasa",
            "user-interface/profiles/software-engineering"
        );
    }

    part workflowScope : CommitScope {
        doc /* RFC 0008 native ASCENT obligation graph and typed FunFlow CAS DAG workflow domain. */
        attribute :>> scopeName = "workflow";
        attribute :>> ownedPaths = (
            "modules/workflow",
            "bindings/workflow-transport.ss",
            "t/yanxu/modules/workflow",
            "docs/rfcs/0008-ascent-obligation-funflow-dag.org"
        );
    }

    part sysmlScope : CommitScope {
        doc /* SysML v2 architecture models and OpenSysML Rust host projection. */
        attribute :>> scopeName = "sysml";
        attribute :>> ownedPaths = (
            "dev/sysml",
            "rust/crates/aitia-runtime/src/sysml.rs",
            "rust/crates/aitia-runtime/tests/integration/sysml_model.rs"
        );
    }

    part def HostCapabilitySpec {
        doc /* Rust HostCapabilityRegistry boundary aligned with FunFlow EffectClass. */
        attribute capabilityId : String;
        attribute effectClass : String;
    }

    part jjObserveCutCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.observe-cut";
        attribute :>> effectClass = "host-read";
    }

    part jjPrepareDescriptionCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.prepare-description";
        attribute :>> effectClass = "fenced-effect";
    }

    part jjApplyDescriptionCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.apply-description";
        attribute :>> effectClass = "fenced-effect";
    }

    part jjReconcileDescriptionCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.reconcile-description";
        attribute :>> effectClass = "host-read";
    }

    part jjRecoverPushCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.recover-push";
        attribute :>> effectClass = "host-read";
    }

    part jjPushReviewedCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.jj.push-reviewed";
        attribute :>> effectClass = "fenced-effect";
    }

    part githubObservePrCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "gitops.github.observe-pr";
        attribute :>> effectClass = "host-read";
    }

    part sysmlProjectScopesCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "sysml.project-scopes";
        attribute :>> effectClass = "host-read";
    }

    part sysmlRevisionScopesCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "sysml.revision-scopes";
        attribute :>> effectClass = "host-read";
    }

    part sysmlParseRevisionCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "sysml.parse-revision";
        attribute :>> effectClass = "host-read";
    }

    part sysmlParseWorkspaceCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "sysml.parse-workspace";
        attribute :>> effectClass = "host-read";
    }

    part pythonObservePytestCapability : HostCapabilitySpec {
        attribute :>> capabilityId = "python.observe-pytest";
        attribute :>> effectClass = "host-read";
    }

    part def WorkspaceRepo {
        doc /* Declarative multi-repository GitOps topology node projected directly by
             * the standalone Rust `aitia` binary into Scheme FunFlow wave scheduling. */
        attribute repoId : String;
        attribute directory : String;
        attribute dependsOn : String[0..*];
        attribute profile : String;
        attribute pushRemote : String;
        attribute pushBookmark : String;
    }
}
