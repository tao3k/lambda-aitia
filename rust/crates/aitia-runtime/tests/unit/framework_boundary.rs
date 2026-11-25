// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Executable architectural boundary gate for `aitia-runtime`.
//!
//! Enforces the thin Rust Host Capability Frame Mapper design so future agents
//! keep higher-order workflow orchestration, scope merging, and semantic policy
//! in Scheme (POO + ASCENT + FunFlow) and SysML v2 rather than growing bespoke
//! imperative pipelines in Rust.

use aitia_runtime::{
    CapabilityError, CapabilityFrame, CapabilityId, HostCapability, HostCapabilityRegistry,
    HostEffectClass, HostReceipt,
};
use std::{collections::BTreeSet, fs, path::Path};

const ALLOWED_TOP_LEVEL_SRC_FILES: &[&str] = &[
    "capability.rs",
    "cli.rs",
    "cli_commit.rs",
    "cli_flow.rs",
    "lib.rs",
    "limits.rs",
    "org_edit.rs",
    "program.rs",
    "pytest.rs",
    "review_provider.rs",
    "session.rs",
    "source_tree.rs",
    "sysml.rs",
];

// Monotonic shrinkage ratchet for legacy imperative CLI orchestration files.
// As workflows migrate to Scheme FunFlow + HostCapabilityRegistry, lower these
// ceilings rather than raising them.
const CLI_LINE_CEILINGS: &[(&str, usize)] = &[
    ("cli.rs", 820),
    ("cli_commit.rs", 845),
    ("cli_flow.rs", 160),
];

#[test]
fn rust_runtime_stays_within_approved_host_frame_mapper_topology() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let src_dir = manifest_dir.join("src");
    let allowed: BTreeSet<&str> = ALLOWED_TOP_LEVEL_SRC_FILES.iter().copied().collect();

    let mut actual = BTreeSet::new();
    for entry in fs::read_dir(&src_dir).expect("read aitia-runtime/src") {
        let entry = entry.expect("read dir entry");
        let path = entry.path();
        if path.is_file() && path.extension().and_then(|e| e.to_str()) == Some("rs") {
            let name = path
                .file_name()
                .and_then(|n| n.to_str())
                .expect("utf-8 rust filename")
                .to_owned();
            assert!(
                allowed.contains(name.as_str()),
                "Unapproved module `src/{name}` in aitia-runtime: add new host effects as a \
                 `HostCapability` in `src/capability.rs` and keep higher-order workflows in Scheme POO/ASCENT/FunFlow."
            );
            actual.insert(name);
        }
    }
    assert!(
        actual.contains("capability.rs"),
        "aitia-runtime must preserve src/capability.rs as the HostCapabilityRegistry boundary"
    );
}

#[test]
fn legacy_imperative_cli_files_obey_monotonic_shrinkage_ratchet() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    for &(file, ceiling) in CLI_LINE_CEILINGS {
        let text = fs::read_to_string(src_dir.join(file)).expect("read cli source file");
        let lines = text.lines().count();
        assert!(
            lines <= ceiling,
            "src/{file} grew to {lines} lines (ceiling {ceiling}): do not add new imperative \
             orchestration in Rust CLI files; author workflows in Scheme FunFlow and dispatch via HostCapabilityRegistry."
        );
    }
}

#[test]
fn rust_does_not_mutate_scheme_naming_policy_or_merge_scopes() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    for file in ["cli.rs", "cli_commit.rs", "cli_flow.rs", "sysml.rs"] {
        let text = fs::read_to_string(src_dir.join(file)).expect("read runtime source file");
        assert!(
            !text.contains("merge_sysml_scopes"),
            "src/{file} must not merge SysML scopes into Scheme naming policy in Rust; forward raw `sysmlScopes` receipts to Scheme."
        );
    }
}

#[test]
fn sysml_v2_owns_project_commit_scopes_not_project_json() {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let project_json_path = repo_root.join(".agents/aita/project.json");
    let project_json: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&project_json_path).expect("read project.json"))
            .expect("parse project.json");
    let naming = &project_json["programs"]["jj"]["settings"]["naming"];
    assert!(
        naming.get("scopes").is_none(),
        ".agents/aita/project.json must not declare hand-maintained `naming.scopes`; declare `CommitScope` parts in dev/sysml/project-architecture.sysml."
    );

    let sysml_arch_path = repo_root.join("dev/sysml/project-architecture.sysml");
    let sysml_text =
        fs::read_to_string(&sysml_arch_path).expect("read dev/sysml/project-architecture.sysml");
    assert!(
        sysml_text.contains("part def CommitScope"),
        "dev/sysml/project-architecture.sysml must declare `part def CommitScope`"
    );
    assert!(
        sysml_text.contains("part def HostCapabilitySpec"),
        "dev/sysml/project-architecture.sysml must declare `part def HostCapabilitySpec`"
    );

    // Bidirectional parity gate: EVERY HostCapability registered in src/capability.rs
    // must be declared as a HostCapabilitySpec in dev/sysml/project-architecture.sysml,
    // and vice versa (0 undocumented or shadow host capabilities).
    let capability_rs =
        fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join("src/capability.rs"))
            .expect("read src/capability.rs");
    let mut rust_caps = BTreeSet::new();
    let lines: Vec<&str> = capability_rs.lines().collect();
    for window in lines.windows(2) {
        if window[0].contains("fn capability_id(&self) -> &'static str") {
            let trimmed = window[1].trim();
            if let Some(id) = trimmed.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
                rust_caps.insert(id.to_owned());
            }
        }
    }
    let mut sysml_caps = BTreeSet::new();
    for line in sysml_text.lines() {
        if let Some(rest) = line.split("capabilityId = \"").nth(1)
            && let Some(id) = rest.split('"').next()
        {
            sysml_caps.insert(id.to_owned());
        }
    }
    assert!(
        !rust_caps.is_empty(),
        "src/capability.rs must register at least one HostCapability"
    );
    assert_eq!(
        rust_caps, sysml_caps,
        "Rust HostCapabilityRegistry and dev/sysml/project-architecture.sysml HostCapabilitySpec drifted out of sync!"
    );
}

#[test]
fn host_capability_registry_enforces_fenced_effects_and_zero_authority() {
    struct TestRead;
    impl HostCapability for TestRead {
        fn capability_id(&self) -> &'static str {
            "jj.read-test"
        }
        fn effect_class(&self) -> HostEffectClass {
            HostEffectClass::HostRead
        }
        fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
            Ok(HostReceipt {
                capability: CapabilityId::new(self.capability_id()),
                effect_class: self.effect_class(),
                payload: frame.payload.clone(),
                action_authorized: true,
            })
        }
    }

    struct TestFenced;
    impl HostCapability for TestFenced {
        fn capability_id(&self) -> &'static str {
            "jj.fenced-test"
        }
        fn effect_class(&self) -> HostEffectClass {
            HostEffectClass::FencedEffect
        }
        fn invoke(&self, _frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
            Ok(HostReceipt::observe(
                self.capability_id(),
                self.effect_class(),
                "{}".to_owned(),
            ))
        }
    }

    let mut registry = HostCapabilityRegistry::new();
    registry.register(Box::new(TestRead));
    registry.register(Box::new(TestFenced));

    let unknown = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("missing.capability"),
        effect_class: HostEffectClass::HostRead,
        payload: "{}".to_owned(),
        fence_token: None,
    });
    assert!(matches!(
        unknown,
        Err(CapabilityError::UnknownCapability(_))
    ));

    let mismatch = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("jj.fenced-test"),
        effect_class: HostEffectClass::HostRead,
        payload: "{}".to_owned(),
        fence_token: Some("tok".to_owned()),
    });
    assert!(matches!(
        mismatch,
        Err(CapabilityError::EffectClassMismatch { .. })
    ));

    let missing_token = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("jj.fenced-test"),
        effect_class: HostEffectClass::FencedEffect,
        payload: "{}".to_owned(),
        fence_token: None,
    });
    assert!(matches!(
        missing_token,
        Err(CapabilityError::MissingFenceToken(_))
    ));

    let read = registry
        .dispatch(&CapabilityFrame {
            capability: CapabilityId::new("jj.read-test"),
            effect_class: HostEffectClass::HostRead,
            payload: "{\"ok\":true}".to_owned(),
            fence_token: None,
        })
        .expect("registered read capability succeeds");
    assert!(!read.action_authorized);

    let with_token = registry
        .dispatch(&CapabilityFrame {
            capability: CapabilityId::new("jj.fenced-test"),
            effect_class: HostEffectClass::FencedEffect,
            payload: "{}".to_owned(),
            fence_token: Some("scheme-approved-fence".to_owned()),
        })
        .expect("fenced capability executes with fence token");
    assert!(!with_token.action_authorized);

    // Batch dispatch validates EVERY frame before executing any capability (fail-closed)
    let bad_batch = registry.dispatch_batch(&[
        CapabilityFrame {
            capability: CapabilityId::new("jj.read-test"),
            effect_class: HostEffectClass::HostRead,
            payload: "{}".to_owned(),
            fence_token: None,
        },
        CapabilityFrame {
            capability: CapabilityId::new("jj.fenced-test"),
            effect_class: HostEffectClass::FencedEffect,
            payload: "{}".to_owned(),
            fence_token: None,
        },
    ]);
    assert!(matches!(
        bad_batch,
        Err(CapabilityError::MissingFenceToken(_))
    ));

    let good_batch = registry
        .dispatch_batch(&[
            CapabilityFrame {
                capability: CapabilityId::new("jj.read-test"),
                effect_class: HostEffectClass::HostRead,
                payload: "{\"n\":1}".to_owned(),
                fence_token: None,
            },
            CapabilityFrame {
                capability: CapabilityId::new("jj.fenced-test"),
                effect_class: HostEffectClass::FencedEffect,
                payload: "{}".to_owned(),
                fence_token: Some("tok-1".to_owned()),
            },
        ])
        .expect("valid batch succeeds with zero authority");
    assert_eq!(good_batch.len(), 2);
    assert!(good_batch.iter().all(|receipt| !receipt.action_authorized));
}
