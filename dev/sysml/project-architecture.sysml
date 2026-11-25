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
            "modules/workflow",
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
            "dev/sysml",
            "docs/rfcs",
            "t/library",
            "t/yanxu/modules/workflow",
            "gerbil.pkg",
            "AGENTS.md",
            "justfile"
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
}
